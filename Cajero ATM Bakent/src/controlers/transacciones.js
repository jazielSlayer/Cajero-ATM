import bcrypt from "bcrypt";
import { connect } from "../database.js";
import { getTasaBOB } from "./Cambio.js";

const MONEDAS_SOPORTADAS = new Set([
    "BOB", "USD", "EUR", "BRL", "ARS", "CLP", "PEN", "COP",
]);

// ─── Helper: obtiene el ID_Moneda desde la tabla moneda por código ────────────
async function getIdMoneda(connection, codigo) {
    const [[row]] = await connection.query(
        "SELECT ID FROM moneda WHERE Codigo = ? AND Activa = 1 LIMIT 1",
        [codigo.toUpperCase()]
    );
    return row ? row.ID : null;
}

// ─────────────────────────────────────────────────────────────────────────────
//  realizarRetiro
// ─────────────────────────────────────────────────────────────────────────────
export const realizarRetiro = async (req, res) => {
    const {
        numero_tarjeta,
        pin,
        monto,
        moneda               = "BOB",
        tipo_tasa            = "oficial",
        metodo               = "ATM",
        confirmar_conversion = false,
    } = req.body;

    if (!numero_tarjeta || !pin || !monto) {
        return res.status(400).json({
            error: "Faltan campos requeridos: numero_tarjeta, pin, monto.",
        });
    }

    const monedaUpper = moneda.toUpperCase();
    if (!MONEDAS_SOPORTADAS.has(monedaUpper)) {
        return res.status(400).json({ error: `Moneda no soportada: ${moneda}.` });
    }
    if (!["oficial", "binance"].includes(tipo_tasa)) {
        return res.status(400).json({ error: "tipo_tasa debe ser 'oficial' o 'binance'." });
    }

    const montoNum = parseFloat(monto);
    if (isNaN(montoNum) || montoNum <= 0) {
        return res.status(400).json({ error: "El monto debe ser un número mayor a 0." });
    }

    const connection = await connect();

    try {
        // ── 1. Verificar tarjeta y PIN ────────────────────────────────────────
        const [[tarjeta]] = await connection.query(
            `SELECT tar.Pin AS pin_hash, tar.ID_Cuenta AS cuenta_id
             FROM   Tarjeta tar
             WHERE  tar.Numero_tarjeta = ? AND tar.Estado = 'activa'`,
            [numero_tarjeta]
        );
        if (!tarjeta) {
            return res.status(404).json({ error: "Tarjeta no encontrada o no activa." });
        }
        const pinOk = await bcrypt.compare(String(pin), tarjeta.pin_hash);
        if (!pinOk) return res.status(401).json({ error: "PIN incorrecto." });

        // ── 2. Resolver IDs de moneda ─────────────────────────────────────────
        const idMoneda = await getIdMoneda(connection, monedaUpper);
        if (!idMoneda) {
            return res.status(400).json({ error: `Moneda no encontrada en BD: ${monedaUpper}.` });
        }
        const idBOB = await getIdMoneda(connection, "BOB");

        // ── 3. Consultar saldo en la moneda solicitada ────────────────────────
        const [[saldoMoneda]] = await connection.query(
            `SELECT sm.ID, sm.Saldo
             FROM   saldo_moneda sm
             WHERE  sm.ID_Cuenta = ? AND sm.ID_Moneda = ?`,
            [tarjeta.cuenta_id, idMoneda]
        );

        const tieneSaldoDirecto = saldoMoneda && parseFloat(saldoMoneda.Saldo) >= montoNum;

        // ── 4a. Retiro directo ────────────────────────────────────────────────
        if (tieneSaldoDirecto) {
            let tasa = 1;
            if (monedaUpper !== "BOB") tasa = await getTasaBOB(monedaUpper, tipo_tasa);
            const montoBOB = parseFloat((montoNum * tasa).toFixed(2));

            await connection.query("SET @transaccion_id = 0;");
            await connection.query("SET @mensaje = '';");
            await connection.query(
                "CALL sp_realizar_retiro(?, ?, ?, ?, ?, ?, @transaccion_id, @mensaje)",
                [tarjeta.pin_hash, montoNum, idMoneda, metodo, tasa, tipo_tasa]
            );
            const [[output]] = await connection.query(
                "SELECT @transaccion_id AS transaccion_id, @mensaje AS mensaje"
            );
            if (output.transaccion_id === -1) {
                return res.status(400).json({ error: output.mensaje });
            }
            return res.json({
                transaccionId: output.transaccion_id,
                mensaje: output.mensaje,
                conversion: false,
                detalle: {
                    montoRetirado:  `${montoNum} ${monedaUpper}`,
                    equivalenteBOB: `${montoBOB} BOB`,
                    tasa: { valor: tasa, tipo: tipo_tasa },
                },
            });
        }

        // ── 4b. No tiene saldo en esa moneda ──────────────────────────────────
        if (monedaUpper === "BOB") {
            return res.status(400).json({
                error: `Saldo insuficiente en BOB. Disponible: ${saldoMoneda ? saldoMoneda.Saldo : 0} BOB.`,
            });
        }

        // Tasa: cuántos BOB necesito para obtener 1 unidad de la moneda pedida
        const tasaBOBaMoneda = await getTasaBOB(monedaUpper, tipo_tasa);
        const montoBOBNecesario = parseFloat((montoNum * tasaBOBaMoneda).toFixed(2));

        // Consultar saldo BOB disponible
        const [[saldoBOB]] = await connection.query(
            `SELECT sm.Saldo FROM saldo_moneda sm
             WHERE  sm.ID_Cuenta = ? AND sm.ID_Moneda = ?`,
            [tarjeta.cuenta_id, idBOB]
        );
        const saldoBOBActual = saldoBOB ? parseFloat(saldoBOB.Saldo) : 0;

        if (saldoBOBActual < montoBOBNecesario) {
            return res.status(400).json({
                error: `Saldo insuficiente. Necesita ${montoBOBNecesario} BOB para retirar ${montoNum} ${monedaUpper}. Saldo BOB disponible: ${saldoBOBActual} BOB.`,
                requiere_conversion: true,
                detalle_conversion: {
                    montoSolicitado:    `${montoNum} ${monedaUpper}`,
                    montoBOBNecesario:  `${montoBOBNecesario} BOB`,
                    saldoBOBDisponible: `${saldoBOBActual} BOB`,
                    tasa: { valor: tasaBOBaMoneda, tipo: tipo_tasa },
                },
            });
        }

        // ── Informar al usuario antes de convertir ────────────────────────────
        if (!confirmar_conversion) {
            return res.status(202).json({
                requiere_confirmacion: true,
                mensaje: `No tiene saldo en ${monedaUpper}. Se convertirán ${montoBOBNecesario} BOB.`,
                detalle_conversion: {
                    montoSolicitado:    `${montoNum} ${monedaUpper}`,
                    montoBOBNecesario:  `${montoBOBNecesario} BOB`,
                    saldoBOBDisponible: `${saldoBOBActual} BOB`,
                    tasa: { valor: tasaBOBaMoneda, tipo: tipo_tasa },
                },
                instruccion: "Reenvíe con confirmar_conversion: true para ejecutar.",
            });
        }

        // ── Conversión confirmada ─────────────────────────────────────────────
        await connection.query("SET @transaccion_id = 0;");
        await connection.query("SET @mensaje = '';");
        await connection.query(
            "CALL sp_realizar_retiro_conversion(?, ?, ?, ?, ?, ?, @transaccion_id, @mensaje)",
            [tarjeta.pin_hash, montoNum, idMoneda, metodo, tasaBOBaMoneda, tipo_tasa]
        );
        const [[outputConv]] = await connection.query(
            "SELECT @transaccion_id AS transaccion_id, @mensaje AS mensaje"
        );
        if (outputConv.transaccion_id === -1) {
            return res.status(400).json({ error: outputConv.mensaje });
        }
        return res.json({
            transaccionId: outputConv.transaccion_id,
            mensaje: outputConv.mensaje,
            conversion: true,
            detalle: {
                montoRetirado:      `${montoNum} ${monedaUpper}`,
                montoBOBDescontado: `${montoBOBNecesario} BOB`,
                tasa: { valor: tasaBOBaMoneda, tipo: tipo_tasa },
            },
        });

    } catch (err) {
        console.error("Error al realizar retiro:", err);
        return res.status(500).json({ error: "Error interno al realizar retiro." });
    }
};

// ─────────────────────────────────────────────────────────────────────────────
//  realizarDeposito
// ─────────────────────────────────────────────────────────────────────────────
export const realizarDeposito = async (req, res) => {
    const {
        correo,
        numero_tarjeta,
        contrasena,
        pin,
        monto,
        moneda_origen  = "BOB",
        moneda_destino = "BOB",
        tipo_tasa      = "oficial",
        metodo         = "ATM",
    } = req.body;

    if (!correo || !numero_tarjeta || !contrasena || !pin || !monto) {
        return res.status(400).json({
            error: "Faltan campos: correo, numero_tarjeta, contrasena, pin, monto.",
        });
    }

    const monedaOrigenUpper  = moneda_origen.toUpperCase();
    const monedaDestinoUpper = moneda_destino.toUpperCase();

    if (!MONEDAS_SOPORTADAS.has(monedaOrigenUpper)) {
        return res.status(400).json({ error: `Moneda origen no soportada: ${moneda_origen}.` });
    }
    if (!MONEDAS_SOPORTADAS.has(monedaDestinoUpper)) {
        return res.status(400).json({ error: `Moneda destino no soportada: ${moneda_destino}.` });
    }
    if (!["oficial", "binance"].includes(tipo_tasa)) {
        return res.status(400).json({ error: "tipo_tasa debe ser 'oficial' o 'binance'." });
    }

    const montoNum = parseFloat(monto);
    if (isNaN(montoNum) || montoNum <= 0) {
        return res.status(400).json({ error: "El monto debe ser un número mayor a 0." });
    }

    const connection = await connect();

    try {
        // ── 1. Autenticación ──────────────────────────────────────────────────
        const [[usuario]] = await connection.query(
            `SELECT u.Contrasena AS contrasena_hash, tar.Pin AS pin_hash, c.ID AS cuenta_id
             FROM   Users u
             INNER JOIN Cuenta  c   ON c.ID_Users   = u.ID
             INNER JOIN Tarjeta tar ON tar.ID_Cuenta = c.ID
             WHERE  u.Correo = ? AND tar.Numero_tarjeta = ?
               AND  u.Estado = 'activo' AND tar.Estado = 'activa'`,
            [correo, numero_tarjeta]
        );
        if (!usuario) {
            return res.status(404).json({ error: "Usuario o tarjeta no encontrada." });
        }
        const [contrasenaOk, pinOk] = await Promise.all([
            bcrypt.compare(String(contrasena), usuario.contrasena_hash),
            bcrypt.compare(String(pin),        usuario.pin_hash),
        ]);
        if (!contrasenaOk) return res.status(401).json({ error: "Contraseña incorrecta." });
        if (!pinOk)        return res.status(401).json({ error: "PIN incorrecto." });

        // ── 2. IDs de moneda ──────────────────────────────────────────────────
        const [idMonedaOrigen, idMonedaDestino] = await Promise.all([
            getIdMoneda(connection, monedaOrigenUpper),
            getIdMoneda(connection, monedaDestinoUpper),
        ]);
        if (!idMonedaOrigen)  return res.status(400).json({ error: `Moneda origen no encontrada: ${monedaOrigenUpper}.` });
        if (!idMonedaDestino) return res.status(400).json({ error: `Moneda destino no encontrada: ${monedaDestinoUpper}.` });

        // ── 3. Calcular montos y tasas ────────────────────────────────────────
        let tasaOrigenABOB  = 1;
        let tasaDestinoABOB = 1;

        if (monedaOrigenUpper  !== "BOB") tasaOrigenABOB  = await getTasaBOB(monedaOrigenUpper,  tipo_tasa);
        if (monedaDestinoUpper !== "BOB") tasaDestinoABOB = await getTasaBOB(monedaDestinoUpper, tipo_tasa);

        const montoBOB = parseFloat((montoNum * tasaOrigenABOB).toFixed(2));
        const montoEnDestino = (monedaOrigenUpper === monedaDestinoUpper)
            ? montoNum
            : parseFloat((montoBOB / tasaDestinoABOB).toFixed(6));

        // ── 4. Ejecutar SP ────────────────────────────────────────────────────
        await connection.query("SET @transaccion_id = 0;");
        await connection.query("SET @mensaje = '';");
        await connection.query(
            `CALL sp_realizar_deposito_multimoneda(
                ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, @transaccion_id, @mensaje
             )`,
            [
                correo,
                montoNum,
                idMonedaOrigen,
                montoEnDestino,
                idMonedaDestino,
                metodo,
                usuario.contrasena_hash,
                usuario.pin_hash,
                tasaOrigenABOB,
                tipo_tasa,
            ]
        );
        const [[output]] = await connection.query(
            "SELECT @transaccion_id AS transaccion_id, @mensaje AS mensaje"
        );
        if (output.transaccion_id === -1) {
            return res.status(400).json({ error: output.mensaje });
        }
        return res.json({
            transaccionId: output.transaccion_id,
            mensaje: output.mensaje,
            detalle: {
                montoRecibido:   `${montoNum} ${monedaOrigenUpper}`,
                montoAcreditado: `${montoEnDestino} ${monedaDestinoUpper}`,
                equivalenteBOB:  `${montoBOB} BOB`,
                tasa: {
                    tipo:           tipo_tasa,
                    origen_a_BOB:   tasaOrigenABOB,
                    destino_a_BOB:  tasaDestinoABOB,
                    moneda_origen:  monedaOrigenUpper,
                    moneda_destino: monedaDestinoUpper,
                },
            },
        });

    } catch (err) {
        console.error("Error al realizar depósito:", err);
        return res.status(500).json({ error: "Error interno al realizar depósito." });
    }
};

// ─────────────────────────────────────────────────────────────────────────────
//  realizarTransferencia
// ─────────────────────────────────────────────────────────────────────────────
export const realizarTransferencia = async (req, res) => {
    const {
        numero_de_cuenta,
        numero_cuenta_destino,
        monto,
        metodo               = "ATM",
        descripcion,
        moneda_origen        = "BOB",
        moneda_destino       = "BOB",
        tipo_tasa            = "oficial",
        confirmar_conversion = false,
    } = req.body;

    if (!numero_de_cuenta || !numero_cuenta_destino || !monto) {
        return res.status(400).json({
            error: "Faltan campos: numero_de_cuenta, numero_cuenta_destino, monto.",
        });
    }

    const monedaOrigenUpper  = moneda_origen.toUpperCase();
    const monedaDestinoUpper = moneda_destino.toUpperCase();

    if (!MONEDAS_SOPORTADAS.has(monedaOrigenUpper)) {
        return res.status(400).json({ error: `Moneda origen no soportada: ${moneda_origen}.` });
    }
    if (!MONEDAS_SOPORTADAS.has(monedaDestinoUpper)) {
        return res.status(400).json({ error: `Moneda destino no soportada: ${moneda_destino}.` });
    }
    if (!["oficial", "binance"].includes(tipo_tasa)) {
        return res.status(400).json({ error: "tipo_tasa debe ser 'oficial' o 'binance'." });
    }

    const montoNum = parseFloat(monto);
    if (isNaN(montoNum) || montoNum <= 0) {
        return res.status(400).json({ error: "El monto debe ser un número mayor a 0." });
    }

    const connection = await connect();

    try {
        // ── 1. Resolver IDs de moneda ─────────────────────────────────────────
        const [idMonedaOrigen, idMonedaDestino, idBOB] = await Promise.all([
            getIdMoneda(connection, monedaOrigenUpper),
            getIdMoneda(connection, monedaDestinoUpper),
            getIdMoneda(connection, "BOB"),
        ]);
        if (!idMonedaOrigen)  return res.status(400).json({ error: `Moneda origen no encontrada: ${monedaOrigenUpper}.` });
        if (!idMonedaDestino) return res.status(400).json({ error: `Moneda destino no encontrada: ${monedaDestinoUpper}.` });

        // ── 2. Cuenta origen — FIX: ya no se selecciona c.Saldo (no existe) ──
        const [[cuentaOrigen]] = await connection.query(
            `SELECT c.ID
             FROM   Cuenta c
             WHERE  c.Numero_cuenta = ? AND c.Estado = 'activa'`,
            [numero_de_cuenta]
        );
        if (!cuentaOrigen) {
            return res.status(404).json({ error: "Cuenta origen no encontrada o no activa." });
        }

        // ── 3. Saldo en moneda_origen ─────────────────────────────────────────
        const [[saldoOrigenMoneda]] = await connection.query(
            `SELECT sm.ID, sm.Saldo FROM saldo_moneda sm
             WHERE  sm.ID_Cuenta = ? AND sm.ID_Moneda = ?`,
            [cuentaOrigen.ID, idMonedaOrigen]
        );
        const saldoDisponible   = saldoOrigenMoneda ? parseFloat(saldoOrigenMoneda.Saldo) : 0;
        const tieneSaldoDirecto = saldoDisponible >= montoNum;

        // ── 4. Calcular tasas y monto a acreditar ─────────────────────────────
        let tasaOrigenABOB  = 1;
        let tasaDestinoABOB = 1;
        if (monedaOrigenUpper  !== "BOB") tasaOrigenABOB  = await getTasaBOB(monedaOrigenUpper,  tipo_tasa);
        if (monedaDestinoUpper !== "BOB") tasaDestinoABOB = await getTasaBOB(monedaDestinoUpper, tipo_tasa);

        const montoBOBEquivalente = parseFloat((montoNum * tasaOrigenABOB).toFixed(2));
        const montoAcreditarDestino = (monedaOrigenUpper === monedaDestinoUpper)
            ? montoNum
            : parseFloat((montoBOBEquivalente / tasaDestinoABOB).toFixed(6));

        // ── 5. Sin saldo directo → intentar desde BOB ─────────────────────────
        if (!tieneSaldoDirecto && monedaOrigenUpper !== "BOB") {
            const [[saldoBOBOrigen]] = await connection.query(
                `SELECT sm.Saldo FROM saldo_moneda sm
                 WHERE  sm.ID_Cuenta = ? AND sm.ID_Moneda = ?`,
                [cuentaOrigen.ID, idBOB]
            );
            const saldoBOBActual = saldoBOBOrigen ? parseFloat(saldoBOBOrigen.Saldo) : 0;

            if (saldoBOBActual < montoBOBEquivalente) {
                return res.status(400).json({
                    error: `Saldo insuficiente en ${monedaOrigenUpper} y en BOB. Necesita ${montoBOBEquivalente} BOB. Disponible: ${saldoBOBActual} BOB.`,
                    requiere_conversion: true,
                    detalle_conversion: {
                        montoSolicitado:      `${montoNum} ${monedaOrigenUpper}`,
                        montoBOBNecesario:    `${montoBOBEquivalente} BOB`,
                        saldoBOBDisponible:   `${saldoBOBActual} BOB`,
                        montoAcreditaDestino: `${montoAcreditarDestino} ${monedaDestinoUpper}`,
                        tasa: { valor: tasaOrigenABOB, tipo: tipo_tasa },
                    },
                });
            }

            if (!confirmar_conversion) {
                return res.status(202).json({
                    requiere_confirmacion: true,
                    mensaje: `Sin saldo en ${monedaOrigenUpper}. Se usarán ${montoBOBEquivalente} BOB.`,
                    detalle_conversion: {
                        montoSolicitado:      `${montoNum} ${monedaOrigenUpper}`,
                        montoBOBNecesario:    `${montoBOBEquivalente} BOB`,
                        saldoBOBDisponible:   `${saldoBOBActual} BOB`,
                        montoAcreditaDestino: `${montoAcreditarDestino} ${monedaDestinoUpper}`,
                        tasa: { valor: tasaOrigenABOB, tipo: tipo_tasa },
                    },
                    instruccion: "Reenvíe con confirmar_conversion: true para ejecutar.",
                });
            }

            // Ejecutar tomando BOB como origen
            return await _ejecutarTransferencia(connection, res, {
                numero_de_cuenta,
                numero_cuenta_destino,
                montoOrigen:        montoBOBEquivalente,
                idMonedaOrigen:     idBOB,
                montoBOBEquivalente,
                montoDestino:       montoAcreditarDestino,
                idMonedaDestino,
                monedaOrigenLabel:  "BOB",
                monedaDestinoLabel: monedaDestinoUpper,
                tasaOrigenABOB:     1,
                tasaDestinoABOB,
                tipo_tasa,
                metodo,
                descripcion,
            });
        }

        // ── 6. Transferencia directa ──────────────────────────────────────────
        return await _ejecutarTransferencia(connection, res, {
            numero_de_cuenta,
            numero_cuenta_destino,
            montoOrigen:        montoNum,
            idMonedaOrigen,
            montoBOBEquivalente,
            montoDestino:       montoAcreditarDestino,
            idMonedaDestino,
            monedaOrigenLabel:  monedaOrigenUpper,
            monedaDestinoLabel: monedaDestinoUpper,
            tasaOrigenABOB,
            tasaDestinoABOB,
            tipo_tasa,
            metodo,
            descripcion,
        });

    } catch (err) {
        console.error("Error al realizar transferencia:", err);
        return res.status(500).json({ error: "Error interno al realizar transferencia." });
    }
};

// ─── Helper: ejecuta el SP de transferencia multimoneda ──────────────────────
async function _ejecutarTransferencia(connection, res, params) {
    const {
        numero_de_cuenta, numero_cuenta_destino,
        montoOrigen, idMonedaOrigen,
        montoBOBEquivalente,
        montoDestino, idMonedaDestino,
        monedaOrigenLabel, monedaDestinoLabel,
        tasaOrigenABOB, tasaDestinoABOB, tipo_tasa,
        metodo, descripcion,
    } = params;

    await connection.query("SET @transaccion_id = 0;");
    await connection.query("SET @mensaje = '';");
    await connection.query(
        `CALL sp_realizar_transferencia_multimoneda(
            ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, @transaccion_id, @mensaje
         )`,
        [
            numero_de_cuenta,
            numero_cuenta_destino,
            montoOrigen,
            idMonedaOrigen,
            montoDestino,
            idMonedaDestino,
            metodo,
            descripcion || null,
            tasaOrigenABOB,
            tasaDestinoABOB,
            tipo_tasa,
        ]
    );
    const [[output]] = await connection.query(
        "SELECT @transaccion_id AS transaccion_id, @mensaje AS mensaje"
    );

    if (output.transaccion_id === -1) {
        return res.status(400).json({ error: output.mensaje });
    }

    return res.json({
        transaccionId: output.transaccion_id,
        mensaje: output.mensaje,
        detalle: {
            montoDebitado:   `${montoOrigen} ${monedaOrigenLabel}`,
            montoAcreditado: `${montoDestino} ${monedaDestinoLabel}`,
            equivalenteBOB:  `${montoBOBEquivalente} BOB`,
            tasa: {
                tipo:          tipo_tasa,
                origen_a_BOB:  tasaOrigenABOB,
                destino_a_BOB: tasaDestinoABOB,
            },
        },
    });
}

// ─────────────────────────────────────────────────────────────────────────────
//  consultarSaldos — FIX: SP corregido para usar JOIN con tabla moneda
// ─────────────────────────────────────────────────────────────────────────────
export const consultarSaldos = async (req, res) => {
    const { numero_cuenta } = req.params;

    if (!numero_cuenta) {
        return res.status(400).json({ error: "Falta el número de cuenta." });
    }

    const connection = await connect();

    try {
        // FIX: consulta directa en lugar del SP roto (que usaba sm.Codigo_moneda
        // que no existe — saldo_moneda solo tiene ID_Moneda)
        const [filas] = await connection.query(
            `SELECT
                m.Codigo              AS Codigo_moneda,
                m.Nombre              AS nombre_moneda,
                m.Simbolo,
                sm.Saldo,
                sm.Fecha_modificacion AS ultima_actualizacion
             FROM   saldo_moneda sm
             INNER JOIN moneda m ON sm.ID_Moneda = m.ID
             INNER JOIN Cuenta  c ON sm.ID_Cuenta = c.ID
             WHERE  c.Numero_cuenta = ?
             ORDER BY sm.Saldo DESC`,
            [numero_cuenta]
        );

        return res.json({ numero_cuenta, saldos: filas });
    } catch (err) {
        console.error("Error al consultar saldos:", err);
        return res.status(500).json({ error: "Error interno al consultar saldos." });
    }
};

// ─────────────────────────────────────────────────────────────────────────────
//  consultarTasas
// ─────────────────────────────────────────────────────────────────────────────
export const consultarTasas = async (req, res) => {
    try {
        const connection = await connect();
        const [tasas] = await connection.query(
            `SELECT Moneda_origen, Moneda_destino, Tasa, Tipo_tasa, Fecha_actualizacion
             FROM   tasa_cambio_cache
             ORDER  BY Tipo_tasa, Moneda_origen`
        );
        return res.json({ tasas });
    } catch (err) {
        console.error("Error al consultar tasas:", err);
        return res.status(500).json({ error: "Error al obtener tasas de cambio." });
    }
};

// ─────────────────────────────────────────────────────────────────────────────
//  getTransaccionesUsuario
// ─────────────────────────────────────────────────────────────────────────────
export const getTransaccionesUsuario = async (req, res) => {
    const connection = await connect();
    const { nombre_completo, tipo_transaccion } = req.body;

    try {
        const [rows] = await connection.query(
            'CALL sp_transacciones_usuario(?, ?)',
            [nombre_completo, tipo_transaccion ?? null]
        );

        res.json(rows[0]);

    } catch (err) {
        console.error('Error al obtener transacciones:', err);
        res.status(500).json({ error: 'Error interno al obtener transacciones' });
    }
};