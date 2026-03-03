import { connect } from "../database.js"; 


export const loginUser = async (req, res) => {
    const connection = await connect();
    const { correo } = req.body;

    try {
        const [rows] = await connection.query(
            'CALL sp_buscar_usuario_login(?)',
            [correo]
        );

        const usuario = rows[0]?.[0];
        if (!usuario) return res.status(404).json({ error: 'Usuario no encontrado' });

        res.json(usuario);
    } catch (err) {
        console.error('Error en login:', err);
        res.status(500).json({ error: 'Error interno en el login' });
    }
};