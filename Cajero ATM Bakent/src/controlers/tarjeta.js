import bcrypt from 'bcrypt';
import { connect } from "../database.js";

export const cambiarEstadoTarjeta = async (req, res) => {
    const connection = await connect();
    const { numero_tarjeta, pin, nombre_completo, nuevo_estado } = req.body;

    try {
        // Buscar el hash del PIN por número de tarjeta (identificador único)
        const [[tarjeta]] = await connection.query(
            `SELECT tar.Pin AS pin_hash
             FROM Tarjeta tar
             WHERE tar.Numero_tarjeta = ?`,
            [numero_tarjeta]
        );

        if (!tarjeta) {
            return res.status(404).json({ error: 'Tarjeta no encontrada.' });
        }

        // Verificar PIN con bcrypt antes de llamar al SP
        const pinOk = await bcrypt.compare(pin, tarjeta.pin_hash);
        if (!pinOk) {
            return res.status(401).json({ error: 'PIN incorrecto.' });
        }

        // Pasar el hash al SP — su WHERE tar.Pin = p_pin busca por hash exacto
        await connection.query("SET @mensaje = '';");

        await connection.query(
            'CALL sp_cambiar_estado_tarjeta(?, ?, ?, @mensaje)',
            [tarjeta.pin_hash, nombre_completo, nuevo_estado]
        );

        const [[output]] = await connection.query('SELECT @mensaje AS mensaje');

        if (output.mensaje.startsWith('Error')) {
            return res.status(400).json({ error: output.mensaje });
        }

        res.json({ mensaje: output.mensaje });

    } catch (err) {
        console.error('Error al cambiar estado de tarjeta:', err);
        res.status(500).json({ error: 'Error interno al cambiar estado de tarjeta' });
    }
};