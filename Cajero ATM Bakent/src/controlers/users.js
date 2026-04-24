import { connect } from "../database.js";
import bcrypt from "bcrypt";
import {
    generarCodigo,
    guardarCodigo,
    validarCodigo,
    correoEstaVerificado,
    limpiarVerificacion,
} from "./verificacion_email/emailVerificacion.js";
import { enviarCodigoVerificacion, enviarDatosRegistro } from "./verificacion_email/mailer.js";

const SALT_ROUNDS = 10;

// ─────────────────────────────────────────────────────────────────────────────
// HELPER — misma lógica que actividad.js
// Si la transacción fue en moneda extranjera, usa los campos _original
// para que el frontend vea el saldo en la moneda real de la operación.
// ─────────────────────────────────────────────────────────────────────────────
function normalizarSaldos(t) {
    const esMonedaExtranjera = t.Moneda_origen && t.Moneda_origen !== "BOB";

    return {
        ...t,
        // Monto que se muestra: en la moneda real de la operación
        Monto: esMonedaExtranjera
            ? parseFloat(t.Monto_original ?? t.Monto)
            : parseFloat(t.Monto),

        // Saldo antes/después en la moneda de la operación
        Saldo_anterior: esMonedaExtranjera
            ? t.Saldo_anterior_original
            : t.Saldo_anterior,

        Saldo_posterior: esMonedaExtranjera
            ? t.Saldo_posterior_original
            : t.Saldo_posterior,

        // Guardamos los valores BOB por si el frontend los necesita
        Saldo_anterior_BOB:  t.Saldo_anterior,
        Saldo_posterior_BOB: t.Saldo_posterior,
        Monto_BOB:           parseFloat(t.Monto),

        // Indicador de moneda real para el frontend
        moneda_saldo: esMonedaExtranjera ? t.Moneda_origen : "BOB",
    };
}

// ─────────────────────────────────────────────────────────────────────────────
// PASO 1 – Solicitar código de verificación
// ─────────────────────────────────────────────────────────────────────────────
export const solicitarVerificacion = async (req, res) => {
    const { correo } = req.body;

    if (!correo) {
        return res.status(400).json({ error: "El campo correo es requerido." });
    }

    const connection = await connect();
    const [[existente]] = await connection.query(
        "SELECT ID FROM Users WHERE Correo = ? LIMIT 1",
        [correo]
    );
    if (existente) {
        return res.status(409).json({ error: "Este correo ya está registrado." });
    }

    const codigo = generarCodigo();
    guardarCodigo(correo, codigo);

    try {
        await enviarCodigoVerificacion(correo, codigo);
        return res.json({
            mensaje: `Código de verificación enviado a ${correo}. Válido por 10 minutos.`,
        });
    } catch (err) {
        console.error("Error al enviar código:", err);
        return res.status(500).json({ error: "No se pudo enviar el correo. Verifica la dirección." });
    }
};

// ─────────────────────────────────────────────────────────────────────────────
// PASO 2 – Confirmar código
// ─────────────────────────────────────────────────────────────────────────────
export const confirmarCodigo = (req, res) => {
    const { correo, codigo } = req.body;

    if (!correo || !codigo) {
        return res.status(400).json({ error: "correo y codigo son requeridos." });
    }

    const resultado = validarCodigo(correo, codigo.trim());

    if (!resultado.ok) {
        return res.status(400).json({ error: resultado.motivo });
    }

    return res.json({ mensaje: "Correo verificado correctamente. Ya puedes completar el registro." });
};

// ─────────────────────────────────────────────────────────────────────────────
// PASO 3 – Crear usuario
// ─────────────────────────────────────────────────────────────────────────────
function generarPin() {
    return Math.floor(1000 + Math.random() * 9000).toString();
}
function generarNumeroCuenta() {
    const timestamp = Date.now().toString().slice(-8);
    const random    = Math.floor(10000000 + Math.random() * 90000000).toString();
    return timestamp + random;
}
function generarNumeroTarjeta() {
    const timestamp = Date.now().toString().slice(-7);
    const random    = Math.floor(100000000 + Math.random() * 900000000).toString();
    return ("4" + timestamp + random).slice(0, 16);
}
function generarFechaVencimiento() {
    const fecha = new Date();
    fecha.setFullYear(fecha.getFullYear() + 5);
    return fecha.toISOString().split("T")[0];
}

export const createUser = async (req, res) => {
    const {
        nombre, apellido, direccion, telefono, edad,
        correo, contrasena,
        tipo_tarjeta, tipo_cuenta,
    } = req.body;

    if (!correoEstaVerificado(correo)) {
        return res.status(403).json({
            error: "El correo no ha sido verificado. Completa el proceso de verificación antes de registrarte.",
        });
    }

    const connection = await connect();

    try {
        const pin               = generarPin();
        const numero_cuenta     = generarNumeroCuenta();
        const numero_tarjeta    = generarNumeroTarjeta();
        const fecha_vencimiento = generarFechaVencimiento();
        const saldo_inicial     = 0.00;
        const id_rol            = 2;

        const [contrasenaHash, pinHash] = await Promise.all([
            bcrypt.hash(contrasena, SALT_ROUNDS),
            bcrypt.hash(pin, SALT_ROUNDS),
        ]);

        await connection.query("SET @usuario_id = 0;");
        await connection.query("SET @mensaje = '';");

        await connection.query(
            "CALL sp_registrar_usuario(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?, @usuario_id, @mensaje)",
            [
                nombre, apellido, direccion, telefono, edad,
                correo, contrasenaHash,
                id_rol,
                numero_cuenta, tipo_cuenta, saldo_inicial,
                numero_tarjeta, pinHash, tipo_tarjeta, fecha_vencimiento,
            ]
        );

        const [[output]] = await connection.query(
            "SELECT @usuario_id AS usuario_id, @mensaje AS mensaje"
        );

        if (output.usuario_id === -1) {
            return res.status(400).json({ error: output.mensaje });
        }

        limpiarVerificacion(correo);

        try {
            await enviarDatosRegistro(correo, {
                nombre,
                numero_cuenta,
                numero_tarjeta,
                pin,
                fecha_vencimiento,
            });
        } catch (mailErr) {
            console.error("Advertencia: usuario creado pero falló el envío del correo con datos:", mailErr);
        }

        return res.json({
            usuarioId: output.usuario_id,
            mensaje:   "Usuario registrado exitosamente. Se enviaron los datos de acceso a tu correo.",
        });

    } catch (err) {
        console.error("Error al registrar usuario:", err);
        return res.status(500).json({ error: "Error interno al intentar crear el usuario." });
    }
};

// ─────────────────────────────────────────────────────────────────────────────
// DatosUsuario — ✅ CORREGIDO: usa query directa en vez del SP para tener
// acceso a todos los campos multi-moneda, luego aplica normalizarSaldos.
// ─────────────────────────────────────────────────────────────────────────────
export const DatosUsuario = async (req, res) => {
    const connection = await connect();
    const { nombre_completo } = req.body;

    try {
        // ── 1. Datos del usuario + cuenta + tarjeta ───────────────────────────
        const [[datosUsuario]] = await connection.query(
            `SELECT
                vuc.usuario_id,
                vuc.Correo,
                vuc.Nombre,
                vuc.Apellido,
                vuc.nombre_completo,
                vuc.Direccion,
                vuc.Telefono,
                vuc.Edad,
                vcr.Numero_cuenta,
                vcr.saldo_bob          AS Saldo,
                vcr.estado_cuenta,
                vcr.Numero_tarjeta,
                tar.Pin,
                vcr.Tipo_tarjeta,
                vcr.Fecha_vencimiento
             FROM vista_usuarios_completo vuc
             INNER JOIN vista_cuentas_resumen vcr ON vcr.usuario_id = vuc.usuario_id
             INNER JOIN Tarjeta tar ON tar.Numero_tarjeta = vcr.Numero_tarjeta
             WHERE vuc.nombre_completo = ?
             LIMIT 1`,
            [nombre_completo]
        );

        if (!datosUsuario) {
            return res.status(404).json({ error: "Usuario no encontrado" });
        }

        // ── 2. Transacciones CON todos los campos multi-moneda ────────────────
        // ✅ FIX: A diferencia del SP original, aquí seleccionamos explícitamente
        //    Moneda_origen, Monto_original, Saldo_anterior_original y
        //    Saldo_posterior_original para poder aplicar normalizarSaldos.
        const [transaccionesRaw] = await connection.query(
            `SELECT
                vtc.transaccion_id,
                vtc.ID_Tipo_Transaccion,
                vtc.tipo_transaccion,
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
                vtc.cuenta_origen,
                vtc.cuenta_destino,
                vtc.nombre_destinatario,
                vtc.correo_destinatario,
                vtc.nombre_remitente
             FROM vista_transacciones_completo vtc
             INNER JOIN vista_usuarios_completo vuc ON vtc.usuario_id = vuc.usuario_id
             WHERE vuc.nombre_completo = ?
             ORDER BY vtc.Fecha_transaccion DESC`,
            [nombre_completo]
        );

        // ── 3. Aplicar normalización de moneda (igual que actividad.js) ───────
        const transacciones = transaccionesRaw.map(normalizarSaldos);

        // ── 4. Separar por tipo ───────────────────────────────────────────────
        const depositos      = transacciones.filter(t => t.tipo_transaccion === "Deposito");
        const retiros        = transacciones.filter(t => t.tipo_transaccion === "Retiro");
        const transferencias = transacciones.filter(t => t.tipo_transaccion === "Transferencia");
        const otrasTransacciones = transacciones.filter(t => t.tipo_transaccion !== "Deposito");

        return res.json({
            usuario: {
                usuario_id:      datosUsuario.usuario_id,
                correo:          datosUsuario.Correo,
                nombre:          datosUsuario.Nombre,
                apellido:        datosUsuario.Apellido,
                nombre_completo: datosUsuario.nombre_completo,
                direccion:       datosUsuario.Direccion,
                telefono:        datosUsuario.Telefono,
                edad:            datosUsuario.Edad,
                cuenta: {
                    numero_cuenta: datosUsuario.Numero_cuenta,
                    saldo:         datosUsuario.Saldo,
                    estado:        datosUsuario.estado_cuenta,
                },
                tarjeta: {
                    numero_tarjeta:    datosUsuario.Numero_tarjeta,
                    pin:               datosUsuario.Pin,
                    tipo_tarjeta:      datosUsuario.Tipo_tarjeta,
                    fecha_vencimiento: datosUsuario.Fecha_vencimiento,
                },
            },
            transacciones: otrasTransacciones,
            depositos,
            retiros,
            transferencias,
        });

    } catch (err) {
        console.error("Error en DatosUsuario:", err);
        return res.status(500).json({ error: "Error interno al obtener datos del usuario" });
    }
};

export const getUsuariosCompleto = async (req, res) => {
    const db = await connect();
    const [rows] = await db.query("SELECT * FROM vista_usuarios_completo");
    res.json(rows);
};

export const consultarSaldosUsuario = async (req, res) => {
    const nombre_completo = decodeURIComponent(req.params.nombre_completo ?? "").trim();

    if (!nombre_completo) {
        return res.status(400).json({ error: "El parámetro nombre_completo es requerido." });
    }

    const connection = await connect();

    try {
        const [[usuario]] = await connection.query(
            `SELECT
                vuc.usuario_id,
                vuc.nombre_completo,
                vuc.Correo         AS correo,
                vuc.estado_usuario,
                c.ID               AS cuenta_id,
                c.Numero_cuenta    AS numero_cuenta,
                c.Tipo_cuenta      AS tipo_cuenta,
                c.Estado           AS estado_cuenta
             FROM vista_usuarios_completo vuc
             INNER JOIN Cuenta c ON c.ID_Users = vuc.usuario_id
             WHERE vuc.nombre_completo = ?
               AND vuc.estado_usuario  = 'activo'
               AND c.Estado            = 'activa'
             LIMIT 1`,
            [nombre_completo]
        );

        if (!usuario) {
            return res.status(404).json({
                error: `No se encontró un usuario activo con nombre: "${nombre_completo}".`,
            });
        }

        const [saldos] = await connection.query(
            `SELECT
                m.Codigo              AS moneda,
                m.Nombre              AS nombre_moneda,
                m.Simbolo             AS simbolo,
                sm.Saldo              AS saldo,
                sm.Fecha_modificacion AS ultima_actualizacion
             FROM saldo_moneda sm
             INNER JOIN moneda m ON sm.ID_Moneda = m.ID
             WHERE sm.ID_Cuenta = ?
             ORDER BY sm.Saldo DESC`,
            [usuario.cuenta_id]
        );

        const saldoBOB = saldos.find((s) => s.moneda === "BOB");
        const saldo_total_bob = saldoBOB ? parseFloat(saldoBOB.saldo) : 0;

        return res.json({
            usuario: {
                nombre_completo: usuario.nombre_completo,
                correo:          usuario.correo,
                numero_cuenta:   usuario.numero_cuenta,
                tipo_cuenta:     usuario.tipo_cuenta,
            },
            saldos: saldos.map((s) => ({
                moneda:               s.moneda,
                nombre_moneda:        s.nombre_moneda,
                simbolo:              s.simbolo,
                saldo:                parseFloat(s.saldo),
                ultima_actualizacion: s.ultima_actualizacion,
            })),
            saldo_total_bob,
        });

    } catch (err) {
        console.error("Error al consultar saldos:", err);
        return res.status(500).json({ error: "Error interno al consultar saldos." });
    }
};