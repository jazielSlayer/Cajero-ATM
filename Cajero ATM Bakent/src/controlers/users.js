import { connect } from "../database.js";

export const getUsuariosCompleto = async (req, res) => {
    const db = await connect();
    const [rows] = await db.query('SELECT * FROM vista_usuarios_completo');
    res.json(rows);
};

export const createUser = async (req, res) => {
    const connection = await connect();

    const {
        nombre,apellido,direccion,telefono,edad,correo,contrasena,
        id_rol,numero_cuenta, tipo_cuenta, saldo_inicial,
        numero_tarjeta,pin,tipo_tarjeta, fecha_vencimiento} = req.body;

    try {
        await connection.query('SET @usuario_id = 0;');
        await connection.query("SET @mensaje = '';");

        const callParams = [
            nombre,apellido,direccion,
            telefono,edad,correo,contrasena,    
            id_rol,numero_cuenta,tipo_cuenta,saldo_inicial,
            numero_tarjeta,pin,tipo_tarjeta,fecha_vencimiento];

        await connection.query(
            'CALL sp_registrar_usuario(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?, @usuario_id, @mensaje)',
            callParams
        );

        const [[output]] = await connection.query(
            'SELECT @usuario_id AS usuario_id, @mensaje AS mensaje'
        );

        res.json({
            usuarioId: output.usuario_id,
            mensaje: output.mensaje
        });
    } catch (err) {
        console.error('Error al registrar usuario:', err);
        res.status(500).json({ error: 'Error interno al intentar crear el usuario' });
    }
};