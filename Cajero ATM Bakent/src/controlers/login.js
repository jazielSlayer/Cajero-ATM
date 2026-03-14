import bcrypt from 'bcrypt';
import { connect } from "../database.js";

export const loginUser = async (req, res) => {
    const connection = await connect();
    const { numero_tarjeta, contrasena, pin } = req.body;

    try {
        const [rows] = await connection.query(
            'CALL sp_buscar_usuario_login(?)',
            [numero_tarjeta]
        );

        const usuario = rows[0]?.[0];
        if (!usuario) {
            return res.status(404).json({ error: 'Usuario no encontrado' });
        }

        const [contrasenaOk, pinOk] = await Promise.all([
            bcrypt.compare(contrasena, usuario.contrasena_hash),
            bcrypt.compare(pin,        usuario.pin_hash)
        ]);

        if (!contrasenaOk || !pinOk) {
            return res.status(401).json({ error: 'Credenciales incorrectas' });
        }

        res.json({
            nombre_completo: usuario.nombre_completo,
            Nombre_rol:      usuario.Nombre_rol,
            estado_usuario:  usuario.estado_usuario
        });

    } catch (err) {
        console.error('Error en login:', err);
        res.status(500).json({ error: 'Error interno en el login' });
    }
};