import bcrypt from 'bcrypt';
import { connect } from "../database.js";

export const loginUser = async (req, res) => {
    const connection = await connect();
    const { correo, contrasena } = req.body;  // ← solo estos dos campos

    if (!correo || !contrasena) {
        return res.status(400).json({ error: 'Correo y contraseña son requeridos' });
    }

    try {
        const [rows] = await connection.query(
            'CALL sp_buscar_usuario_login(?)',
            [correo]
        );

        const usuario = rows[0]?.[0];
        if (!usuario) {
            return res.status(404).json({ error: 'Usuario no encontrado' });
        }

        const contrasenaOk = await bcrypt.compare(contrasena, usuario.contrasena_hash);

        if (!contrasenaOk) {
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