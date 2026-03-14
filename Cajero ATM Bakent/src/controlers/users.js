import { connect } from "../database.js";
import bcrypt from 'bcrypt';

const SALT_ROUNDS = 10;

export const getUsuariosCompleto = async (req, res) => {
    const db = await connect();
    const [rows] = await db.query('SELECT * FROM vista_usuarios_completo');
    res.json(rows);
};



// Genera un PIN de 4 dígitos aleatorio
function generarPin() {
    return Math.floor(1000 + Math.random() * 9000).toString();
}

// Genera número de cuenta de 16 dígitos único
function generarNumeroCuenta() {
    const timestamp = Date.now().toString().slice(-8);
    const random   = Math.floor(10000000 + Math.random() * 90000000).toString();
    return timestamp + random; // 16 dígitos
}

// Fecha de vencimiento: 5 años desde hoy
function generarFechaVencimiento() {
    const fecha = new Date();
    fecha.setFullYear(fecha.getFullYear() + 5);
    return fecha.toISOString().split('T')[0]; // YYYY-MM-DD
}

export const createUser = async (req, res) => {
    const connection = await connect();

    const {
        nombre, apellido, direccion, telefono, edad,
        correo, contrasena,
        numero_tarjeta, tipo_tarjeta, tipo_cuenta
    } = req.body;

    try {
        // Valores autogenerados
        const pin              = generarPin();
        const numero_cuenta    = generarNumeroCuenta();
        const fecha_vencimiento = generarFechaVencimiento();
        const saldo_inicial    = 0.00;
        const id_rol           = 2; // Cliente por defecto

        // Hashear contraseña y PIN
        const [contrasenaHash, pinHash] = await Promise.all([
            bcrypt.hash(contrasena, SALT_ROUNDS),
            bcrypt.hash(pin,        SALT_ROUNDS)
        ]);

        await connection.query('SET @usuario_id = 0;');
        await connection.query("SET @mensaje = '';");

        await connection.query(
            'CALL sp_registrar_usuario(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?, @usuario_id, @mensaje)',
            [
                nombre, apellido, direccion, telefono, edad,
                correo, contrasenaHash,
                id_rol,
                numero_cuenta, tipo_cuenta, saldo_inicial,
                numero_tarjeta, pinHash, tipo_tarjeta, fecha_vencimiento
            ]
        );

        const [[output]] = await connection.query(
            'SELECT @usuario_id AS usuario_id, @mensaje AS mensaje'
        );

        if (output.usuario_id === -1) {
            return res.status(400).json({ error: output.mensaje });
        }

        // Devolver el PIN en texto plano UNA sola vez para que el usuario lo guarde
        res.json({
            usuarioId:        output.usuario_id,
            mensaje:          output.mensaje,
            numero_cuenta,
            fecha_vencimiento,
            pin               // solo se muestra aquí, nunca más se puede recuperar
        });

    } catch (err) {
        console.error('Error al registrar usuario:', err);
        res.status(500).json({ error: 'Error interno al intentar crear el usuario' });
    }
};

export const DatosUsuario = async (req, res) => {
    const connection = await connect();
    const { nombre_completo } = req.body;

    try {
        const [rows] = await connection.query(
            'CALL sp_datos_usuario_por_nombre(?)',
            [nombre_completo]
        );

        const datosUsuario = rows[0]?.[0];
        if (!datosUsuario) return res.status(404).json({ error: 'Usuario no encontrado' });

        res.json(datosUsuario);
    } catch (err) {
        console.error('Error en login:', err);
        res.status(500).json({ error: 'Error interno en el login' });
    }
};