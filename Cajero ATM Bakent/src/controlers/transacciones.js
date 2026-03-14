import bcrypt from 'bcrypt';
import { connect } from "../database.js";

// ─────────────────────────────────────────────
export const realizarRetiro = async (req, res) => {
    const connection = await connect();
    const { numero_tarjeta, pin, monto, metodo } = req.body;

    try {
        // 1. Buscar hash del PIN por número de tarjeta
        const [[tarjeta]] = await connection.query(
            `SELECT tar.Pin AS pin_hash
             FROM Tarjeta tar
             WHERE tar.Numero_tarjeta = ?
               AND tar.Estado = 'activa'`,
            [numero_tarjeta]
        );

        if (!tarjeta) {
            return res.status(404).json({ error: 'Tarjeta no encontrada o no activa.' });
        }

        // 2. Verificar PIN con bcrypt
        const pinOk = await bcrypt.compare(pin, tarjeta.pin_hash);
        if (!pinOk) {
            return res.status(401).json({ error: 'PIN incorrecto.' });
        }

        // 3. Llamar al SP pasando el hash — su WHERE tar.Pin = p_pin lo encuentra
        await connection.query('SET @transaccion_id = 0;');
        await connection.query("SET @mensaje = '';");

        await connection.query(
            'CALL sp_realizar_retiro(?, ?, ?, @transaccion_id, @mensaje)',
            [tarjeta.pin_hash, monto, metodo]
        );

        const [[output]] = await connection.query(
            'SELECT @transaccion_id AS transaccion_id, @mensaje AS mensaje'
        );

        if (output.transaccion_id === -1)
            return res.status(400).json({ error: output.mensaje });

        res.json({ transaccionId: output.transaccion_id, mensaje: output.mensaje });

    } catch (err) {
        console.error('Error al realizar retiro:', err);
        res.status(500).json({ error: 'Error interno al realizar retiro' });
    }
};

// ─────────────────────────────────────────────
export const realizarDeposito = async (req, res) => {
    const connection = await connect();
    const { correo, numero_tarjeta, monto, metodo, contrasena, pin } = req.body;

    try {
        // 1. Buscar hashes de contraseña y PIN por correo + número de tarjeta
        const [[usuario]] = await connection.query(
            `SELECT u.Contrasena AS contrasena_hash, tar.Pin AS pin_hash
             FROM Users u
             INNER JOIN Cuenta  c   ON c.ID_Users    = u.ID
             INNER JOIN Tarjeta tar ON tar.ID_Cuenta  = c.ID
             WHERE u.Correo          = ?
               AND tar.Numero_tarjeta = ?
               AND u.Estado           = 'activo'
               AND tar.Estado         = 'activa'`,
            [correo, numero_tarjeta]
        );

        if (!usuario) {
            return res.status(404).json({ error: 'Usuario o tarjeta no encontrada.' });
        }

        // 2. Verificar contraseña y PIN con bcrypt
        const [contrasenaOk, pinOk] = await Promise.all([
            bcrypt.compare(contrasena, usuario.contrasena_hash),
            bcrypt.compare(pin,        usuario.pin_hash)
        ]);

        if (!contrasenaOk || !pinOk) {
            return res.status(401).json({ error: 'Credenciales incorrectas.' });
        }

        // 3. Llamar al SP pasando los hashes — sus comparaciones internas con '=' funcionan
        await connection.query('SET @transaccion_id = 0;');
        await connection.query("SET @mensaje = '';");

        await connection.query(
            'CALL sp_realizar_deposito(?, ?, ?, ?, ?, @transaccion_id, @mensaje)',
            [correo, monto, metodo, usuario.contrasena_hash, usuario.pin_hash]
        );

        const [[output]] = await connection.query(
            'SELECT @transaccion_id AS transaccion_id, @mensaje AS mensaje'
        );

        if (output.transaccion_id === -1)
            return res.status(400).json({ error: output.mensaje });

        res.json({ transaccionId: output.transaccion_id, mensaje: output.mensaje });

    } catch (err) {
        console.error('Error al realizar depósito:', err);
        res.status(500).json({ error: 'Error interno al realizar depósito' });
    }
};

// ─────────────────────────────────────────────
// La transferencia no usa PIN ni contraseña — el SP funciona igual que antes
export const realizarTransferencia = async (req, res) => {
    const connection = await connect();
    const { numero_de_cuenta, numero_cuenta_destino, monto, metodo, descripcion } = req.body;

    try {
        await connection.query('SET @transaccion_id = 0;');
        await connection.query("SET @mensaje = '';");

        await connection.query(
            'CALL sp_realizar_transferencia(?, ?, ?, ?, ?, @transaccion_id, @mensaje)',
            [numero_de_cuenta, numero_cuenta_destino, monto, metodo, descripcion]
        );

        const [[output]] = await connection.query(
            'SELECT @transaccion_id AS transaccion_id, @mensaje AS mensaje'
        );

        if (output.transaccion_id === -1)
            return res.status(400).json({ error: output.mensaje });

        res.json({ transaccionId: output.transaccion_id, mensaje: output.mensaje });

    } catch (err) {
        console.error('Error al realizar transferencia:', err);
        res.status(500).json({ error: 'Error interno al realizar transferencia' });
    }
};

// ─────────────────────────────────────────────
// Sin credenciales — el SP funciona igual que antes
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