import { connect } from "../database.js"; 

export const realizarRetiro = async (req, res) => {
    const connection = await connect();
    const { cuenta_id, monto, metodo } = req.body;

    try {
        await connection.query('SET @transaccion_id = 0;');
        await connection.query("SET @mensaje = '';");

        await connection.query(
            'CALL sp_realizar_retiro(?, ?, ?, @transaccion_id, @mensaje)',
            [cuenta_id, monto, metodo]
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


export const realizarTransferencia = async (req, res) => {
    const connection = await connect();
    const { cuenta_origen_id, cuenta_destino_id, monto, metodo, descripcion } = req.body;

    try {
        await connection.query('SET @transaccion_id = 0;');
        await connection.query("SET @mensaje = '';");

        await connection.query(
            'CALL sp_realizar_transferencia(?, ?, ?, ?, ?, @transaccion_id, @mensaje)',
            [cuenta_origen_id, cuenta_destino_id, monto, metodo, descripcion]
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
    const { usuario_id } = req.params;
    const { fecha_inicio, fecha_fin, tipo_transaccion, limite } = req.query;

    try {
        const [rows] = await connection.query(
            'CALL sp_transacciones_usuario(?, ?, ?, ?, ?)',
            [
                usuario_id,
                fecha_inicio    || null,
                fecha_fin       || null,
                tipo_transaccion ? parseInt(tipo_transaccion) : null,
                limite          ? parseInt(limite) : null
            ]
        );

        res.json(rows[0]);
    } catch (err) {
        console.error('Error al obtener transacciones:', err);
        res.status(500).json({ error: 'Error interno al obtener transacciones' });
    }
};

