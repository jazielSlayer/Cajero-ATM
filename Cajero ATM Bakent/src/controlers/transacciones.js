import { connect } from "../database.js"; 

export const realizarRetiro = async (req, res) => {
    const connection = await connect();
    const { pin, monto, metodo } = req.body;

    try {
        await connection.query('SET @transaccion_id = 0;');
        await connection.query("SET @mensaje = '';");

        await connection.query(
            'CALL sp_realizar_retiro(?, ?, ?, @transaccion_id, @mensaje)',
            [pin, monto, metodo]
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

export const realizarDeposito = async (req, res) => {
    const connection = await connect();
    const { correo, monto, metodo, contrasena, pin } = req.body; // ✅ correo en vez de cuenta_id

    try {
        await connection.query('SET @transaccion_id = 0;');
        await connection.query("SET @mensaje = '';");

        await connection.query(
            'CALL sp_realizar_deposito(?, ?, ?, ?, ?, @transaccion_id, @mensaje)',
            [correo, monto, metodo, contrasena, pin]
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


export const getTransaccionesUsuario = async (req, res) => {
    const connection = await connect();
    const { nombre_completo, tipo_transaccion } = req.body; 

    try {
        const [rows] = await connection.query(
            'CALL sp_transacciones_usuario(?, ?)',
            [
                nombre_completo,
                tipo_transaccion
            ]
        );

        res.json(rows[0]);
    } catch (err) {
        console.error('Error al obtener transacciones:', err);
        res.status(500).json({ error: 'Error interno al obtener transacciones' });
    }
};

