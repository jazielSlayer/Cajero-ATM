import { connect } from "../database.js";

// ──────────────────────────────────────────────────────────────
//  Helpers
// ──────────────────────────────────────────────────────────────
function calcularNotificaciones(cuentas, tarjetas) {
    const notifs = [];
    const hoy = new Date();

    tarjetas.forEach((tar) => {
        const venc = new Date(tar.Fecha_vencimiento);
        const diasRestantes = Math.ceil((venc - hoy) / (1000 * 60 * 60 * 24));

        if (diasRestantes < 0) {
            notifs.push({
                tipo:   "error",
                icono:  "ti-credit-card-off",
                titulo: "Tarjeta vencida",
                mensaje: `Tu tarjeta ${tar.Numero_tarjeta.slice(-4)} venció el ${venc.toLocaleDateString("es-ES")}.`,
                fecha:  tar.Fecha_vencimiento,
            });
        } else if (diasRestantes <= 30) {
            notifs.push({
                tipo:   "warning",
                icono:  "ti-credit-card",
                titulo: "Tarjeta próxima a vencer",
                mensaje: `Tu tarjeta terminada en ${tar.Numero_tarjeta.slice(-4)} vence en ${diasRestantes} día(s).`,
                fecha:  tar.Fecha_vencimiento,
            });
        }
    });

    cuentas.forEach((c) => {
        const saldo = parseFloat(c.saldo_bob);
        if (c.estado_cuenta !== "activa") {
            notifs.push({
                tipo:   "error",
                icono:  "ti-lock",
                titulo: "Cuenta bloqueada / cerrada",
                mensaje: `La cuenta ${c.Numero_cuenta} está en estado: ${c.estado_cuenta}.`,
                fecha:  null,
            });
        } else if (saldo < 100) {
            notifs.push({
                tipo:   "warning",
                icono:  "ti-moneybag",
                titulo: "Saldo bajo",
                mensaje: `La cuenta ${c.Numero_cuenta} tiene saldo bajo: Bs. ${saldo.toFixed(2)}.`,
                fecha:  null,
            });
        }
    });

    return notifs;
}

function agruparPorMes(transacciones) {
    const meses = {};
    transacciones.forEach((t) => {
        const fecha = new Date(t.Fecha_transaccion);
        const clave = `${fecha.getFullYear()}-${String(fecha.getMonth() + 1).padStart(2, "0")}`;
        if (!meses[clave]) {
            meses[clave] = { mes: clave, depositos: 0, retiros: 0, transferencias: 0 };
        }
        const tipo = (t.tipo_transaccion || "").toLowerCase();
        const monto = parseFloat(t.Monto_original ?? t.Monto);
        if      (tipo === "deposito")       meses[clave].depositos       += monto;
        else if (tipo === "retiro")         meses[clave].retiros         += monto;
        else if (tipo === "transferencia")  meses[clave].transferencias  += monto;
    });
    return Object.values(meses).sort((a, b) => a.mes.localeCompare(b.mes));
}

function calcularResumen(transacciones) {
    let totalDepositos = 0, totalRetiros = 0, totalTransferencias = 0;
    const porTipo = {};

    transacciones.forEach((t) => {
        const tipo  = (t.tipo_transaccion || "Otro").toLowerCase();
        const monto = parseFloat(t.Monto_original ?? t.Monto);
        porTipo[tipo] = (porTipo[tipo] || 0) + monto;
        if      (tipo === "deposito")      totalDepositos      += monto;
        else if (tipo === "retiro")        totalRetiros        += monto;
        else if (tipo === "transferencia") totalTransferencias += monto;
    });

    return {
        totalDepositos:      parseFloat(totalDepositos.toFixed(2)),
        totalRetiros:        parseFloat(totalRetiros.toFixed(2)),
        totalTransferencias: parseFloat(totalTransferencias.toFixed(2)),
        balance:             parseFloat((totalDepositos - totalRetiros - totalTransferencias).toFixed(2)),
        cantidadTotal:       transacciones.length,
        distribucionPorTipo: Object.entries(porTipo).map(([tipo, total]) => ({
            tipo,
            total:    parseFloat(total.toFixed(2)),
            cantidad: transacciones.filter(
                (t) => (t.tipo_transaccion || "").toLowerCase() === tipo
            ).length,
        })),
    };
}

// ✅ FIX: Elige el saldo correcto según la moneda de la transacción.
// Si la operación fue en una moneda distinta a BOB, usa Saldo_anterior_original
// (que contiene el saldo en la moneda real). Si fue en BOB, usa Saldo_anterior.
function normalizarSaldos(t) {
    const esMonedaExtranjera =
        t.Moneda_origen && t.Moneda_origen !== "BOB";

    return {
        ...t,
        // Saldo de referencia para mostrar al usuario: en la moneda de la operación
        Saldo_anterior: esMonedaExtranjera
            ? t.Saldo_anterior_original   // ej: 37.85 USD
            : t.Saldo_anterior,           // ej: 9636.42 BOB

        Saldo_posterior: esMonedaExtranjera
            ? t.Saldo_posterior_original  // ej: 27.85 USD
            : t.Saldo_posterior,          // ej: 9539.82 BOB

        // Conservamos también los valores en BOB por si el frontend los necesita
        Saldo_anterior_BOB:  t.Saldo_anterior,
        Saldo_posterior_BOB: t.Saldo_posterior,

        // Indicador útil para el frontend
        moneda_saldo: esMonedaExtranjera ? t.Moneda_origen : "BOB",
    };
}

// ──────────────────────────────────────────────────────────────
//  POST /actividad/completa
// ──────────────────────────────────────────────────────────────
export const getActividadCompleta = async (req, res) => {
    const {
        nombre_completo,
        fecha_desde,
        fecha_hasta,
        tipo_transaccion,
        palabra_clave,
        numero_cuenta,
    } = req.body;

    if (!nombre_completo) {
        return res.status(400).json({ error: "Se requiere nombre_completo." });
    }

    const connection = await connect();

    try {
        // ── 1. Datos del usuario ──────────────────────────────────────────────
        const [[usuario]] = await connection.query(
            `SELECT vuc.usuario_id, vuc.Correo, vuc.Nombre, vuc.Apellido,
                    vuc.nombre_completo, vuc.Direccion, vuc.Telefono,
                    vuc.Edad, vuc.rol, vuc.estado_usuario, vuc.fecha_registro
             FROM vista_usuarios_completo vuc
             WHERE vuc.nombre_completo = ? LIMIT 1`,
            [nombre_completo]
        );
        if (!usuario) return res.status(404).json({ error: "Usuario no encontrado." });

        // ── 2. Cuentas vinculadas ─────────────────────────────────────────────
        const [cuentas] = await connection.query(
            `SELECT c.ID AS cuenta_id, c.Numero_cuenta, c.Tipo_cuenta,
                    c.Estado AS estado_cuenta, c.Fecha_creacion AS fecha_apertura,
                    tar.Numero_tarjeta, tar.Tipo_tarjeta, tar.Estado AS estado_tarjeta,
                    tar.Fecha_vencimiento, tc.Es_principal, tc.Orden
             FROM Cuenta c
             LEFT JOIN tarjeta_cuenta tc ON tc.ID_Cuenta = c.ID
             LEFT JOIN Tarjeta tar        ON tar.ID = tc.ID_Tarjeta
             WHERE c.ID_Users = ?
             ORDER BY tc.Es_principal DESC, tc.Orden ASC`,
            [usuario.usuario_id]
        );

        // ── 3. Saldos multi-moneda por cuenta ─────────────────────────────────
        const cuentaIds = [...new Set(cuentas.map((c) => c.cuenta_id))];
        let saldosMap = {};
        if (cuentaIds.length > 0) {
            const placeholders = cuentaIds.map(() => "?").join(",");
            const [saldos] = await connection.query(
                `SELECT sm.ID_Cuenta, m.Codigo, m.Nombre AS nombre_moneda,
                        m.Simbolo, sm.Saldo, sm.Fecha_modificacion
                 FROM saldo_moneda sm
                 INNER JOIN moneda m ON m.ID = sm.ID_Moneda
                 WHERE sm.ID_Cuenta IN (${placeholders})
                 ORDER BY sm.Saldo DESC`,
                cuentaIds
            );
            saldos.forEach((s) => {
                if (!saldosMap[s.ID_Cuenta]) saldosMap[s.ID_Cuenta] = [];
                saldosMap[s.ID_Cuenta].push(s);
            });
        }

        const cuentasEnriquecidas = cuentas.map((c) => ({
            ...c,
            saldos:    saldosMap[c.cuenta_id] || [],
            saldo_bob: (saldosMap[c.cuenta_id] || []).find((s) => s.Codigo === "BOB")?.Saldo ?? 0,
        }));

        // ── 4. Tarjetas (para notificaciones) ────────────────────────────────
        const [tarjetas] = await connection.query(
            `SELECT tar.Numero_tarjeta, tar.Tipo_tarjeta, tar.Estado, tar.Fecha_vencimiento
             FROM Tarjeta tar WHERE tar.ID_Users = ?`,
            [usuario.usuario_id]
        );

        // ── 5. Transacciones filtradas ────────────────────────────────────────
        // ✅ FIX: se agregan Saldo_anterior_original y Saldo_posterior_original
        let sql = `
            SELECT
                vtc.transaccion_id,
                vtc.ID_Tipo_Transaccion,
                vtc.Fecha_transaccion,
                vtc.Monto,
                vtc.Monto_original,
                vtc.Moneda_origen,
                vtc.Monto_destino,
                vtc.Moneda_destino,
                vtc.Saldo_anterior,
                vtc.Saldo_posterior,
                vtc.Saldo_anterior_original,
                vtc.Saldo_posterior_original,
                vtc.Metodo_transaccion,
                vtc.estado_transaccion,
                vtc.Descripcion,
                vtc.tipo_transaccion,
                vtc.cuenta_origen,
                vtc.tipo_cuenta_origen,
                vtc.cuenta_destino,
                vtc.nombre_destinatario,
                vtc.correo_destinatario,
                vtc.nombre_remitente
            FROM vista_transacciones_completo vtc
            WHERE vtc.usuario_id = ?
        `;
        const params = [usuario.usuario_id];

        if (fecha_desde) {
            sql += " AND DATE(vtc.Fecha_transaccion) >= ?";
            params.push(fecha_desde);
        }
        if (fecha_hasta) {
            sql += " AND DATE(vtc.Fecha_transaccion) <= ?";
            params.push(fecha_hasta);
        }
        if (tipo_transaccion && tipo_transaccion !== "Todos") {
            sql += " AND vtc.tipo_transaccion = ?";
            params.push(tipo_transaccion);
        }
        if (palabra_clave) {
            sql += " AND (vtc.Descripcion LIKE ? OR vtc.nombre_destinatario LIKE ? OR vtc.cuenta_destino LIKE ?)";
            const like = `%${palabra_clave}%`;
            params.push(like, like, like);
        }
        if (numero_cuenta) {
            sql += " AND (vtc.cuenta_origen = ? OR vtc.cuenta_destino = ?)";
            params.push(numero_cuenta, numero_cuenta);
        }

        sql += " ORDER BY vtc.Fecha_transaccion DESC";

        const [transaccionesRaw] = await connection.query(sql, params);

        // ✅ FIX: normalizar saldos según la moneda de cada transacción
        const transacciones = transaccionesRaw.map(normalizarSaldos);

        // ── 6. Todas las transacciones (para gráficos / resumen) ─────────────
        const [todasTransacciones] = await connection.query(
            `SELECT
                vtc.Monto,
                vtc.Monto_original,
                vtc.Moneda_origen,
                vtc.tipo_transaccion,
                vtc.Fecha_transaccion
             FROM vista_transacciones_completo vtc
             WHERE vtc.usuario_id = ?
             ORDER BY vtc.Fecha_transaccion ASC`,
            [usuario.usuario_id]
        );

        const resumen          = calcularResumen(todasTransacciones);
        const actividadMensual = agruparPorMes(todasTransacciones);
        const notificaciones   = calcularNotificaciones(cuentasEnriquecidas, tarjetas);

        return res.json({
            usuario: {
                id:              usuario.usuario_id,
                nombre:          usuario.Nombre,
                apellido:        usuario.Apellido,
                nombre_completo: usuario.nombre_completo,
                correo:          usuario.Correo,
                rol:             usuario.rol,
                estado:          usuario.estado_usuario,
                fecha_registro:  usuario.fecha_registro,
            },
            cuentas:           cuentasEnriquecidas,
            tarjetas,
            transacciones,
            resumen,
            actividadMensual,
            notificaciones,
            filtrosAplicados: {
                fecha_desde:      fecha_desde      || null,
                fecha_hasta:      fecha_hasta      || null,
                tipo_transaccion: tipo_transaccion || null,
                palabra_clave:    palabra_clave    || null,
                numero_cuenta:    numero_cuenta    || null,
            },
        });
    } catch (err) {
        console.error("Error en getActividadCompleta:", err);
        return res.status(500).json({ error: "Error interno al obtener actividad." });
    }
};

// ──────────────────────────────────────────────────────────────
//  POST /actividad/exportar  — CSV
// ──────────────────────────────────────────────────────────────
export const exportarTransaccionesCSV = async (req, res) => {
    const { nombre_completo, fecha_desde, fecha_hasta, tipo_transaccion, palabra_clave } = req.body;

    if (!nombre_completo) {
        return res.status(400).json({ error: "Se requiere nombre_completo." });
    }

    const connection = await connect();
    try {
        const [[usuario]] = await connection.query(
            "SELECT usuario_id FROM vista_usuarios_completo WHERE nombre_completo = ? LIMIT 1",
            [nombre_completo]
        );
        if (!usuario) return res.status(404).json({ error: "Usuario no encontrado." });

        // ✅ FIX: incluir columnas originales en el CSV
        let sql = `
            SELECT
                vtc.transaccion_id           AS ID,
                vtc.Fecha_transaccion        AS Fecha,
                vtc.tipo_transaccion         AS Tipo,
                vtc.Monto_original           AS Monto_original,
                vtc.Moneda_origen            AS Moneda,
                vtc.Monto                    AS Monto_BOB,
                vtc.Monto_destino            AS Monto_acreditado,
                vtc.Moneda_destino           AS Moneda_destino,
                -- ✅ Saldos en la moneda real de la transacción
                vtc.Saldo_anterior_original  AS Saldo_anterior,
                vtc.Saldo_posterior_original AS Saldo_posterior,
                -- Saldos en BOB como referencia adicional
                vtc.Saldo_anterior           AS Saldo_anterior_BOB,
                vtc.Saldo_posterior          AS Saldo_posterior_BOB,
                vtc.Metodo_transaccion       AS Metodo,
                vtc.estado_transaccion       AS Estado,
                vtc.Descripcion,
                vtc.cuenta_origen            AS Cuenta_Origen,
                vtc.cuenta_destino           AS Cuenta_Destino,
                vtc.nombre_destinatario      AS Destinatario
            FROM vista_transacciones_completo vtc
            WHERE vtc.usuario_id = ?
        `;
        const params = [usuario.usuario_id];

        if (fecha_desde) { sql += " AND DATE(vtc.Fecha_transaccion) >= ?"; params.push(fecha_desde); }
        if (fecha_hasta) { sql += " AND DATE(vtc.Fecha_transaccion) <= ?"; params.push(fecha_hasta); }
        if (tipo_transaccion && tipo_transaccion !== "Todos") {
            sql += " AND vtc.tipo_transaccion = ?";
            params.push(tipo_transaccion);
        }
        if (palabra_clave) {
            const like = `%${palabra_clave}%`;
            sql += " AND (vtc.Descripcion LIKE ? OR vtc.nombre_destinatario LIKE ?)";
            params.push(like, like);
        }
        sql += " ORDER BY vtc.Fecha_transaccion DESC";

        const [filas] = await connection.query(sql, params);

        if (filas.length === 0) {
            return res.json({ csv: "", mensaje: "Sin transacciones para exportar." });
        }

        const headers = Object.keys(filas[0]).join(",");
        const rows = filas.map((f) =>
            Object.values(f)
                .map((v) => (v === null ? "" : `"${String(v).replace(/"/g, '""')}"`))
                .join(",")
        );
        const csv = [headers, ...rows].join("\n");

        return res.json({ csv, total: filas.length });
    } catch (err) {
        console.error("Error exportarTransaccionesCSV:", err);
        return res.status(500).json({ error: "Error interno al exportar." });
    }
};