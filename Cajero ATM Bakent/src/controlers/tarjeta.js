import { connect } from "../database.js"; 
export const cambiarEstadoTarjeta = async (req, res) => {
    const connection = await connect();
    const { tarjeta_id, usuario_id, nuevo_estado } = req.body;

    try {
        await connection.query("SET @mensaje = '';");

        await connection.query(
            'CALL sp_cambiar_estado_tarjeta(?, ?, ?, @mensaje)',
            [tarjeta_id, usuario_id, nuevo_estado]
        );

        const [[output]] = await connection.query(
            'SELECT @mensaje AS mensaje'
        );

        if (output.mensaje.startsWith('Error'))
            return res.status(400).json({ error: output.mensaje });

        res.json({ mensaje: output.mensaje });
    } catch (err) {
        console.error('Error al cambiar estado de tarjeta:', err);
        res.status(500).json({ error: 'Error interno al cambiar estado de tarjeta' });
    }
};