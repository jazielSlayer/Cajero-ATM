import { connect } from "../database.js";
import bcrypt from 'bcrypt';

const SALT_ROUNDS = 10;

export const DatosUsuario = async (req, res) => {
    const connection = await connect();
    const { nombre_completo } = req.body;

    try {
        const [rows] = await connection.query(
            'CALL sp_datos_usuario_por_nombre(?)',
            [nombre_completo]
        );

        const datosUsuario  = rows[0]?.[0];
        const transacciones = rows[1] ?? [];

        if (!datosUsuario) {
            return res.status(404).json({ error: 'Usuario no encontrado' });
        }

        const depositos          = transacciones.filter(t => t.tipo_transaccion === 'Deposito');
        const otrasTransacciones = transacciones.filter(t => t.tipo_transaccion !== 'Deposito');

        return res.json({
            usuario: {
                usuario_id:      datosUsuario.usuario_id,
                correo:          datosUsuario.Correo,
                nombre:          datosUsuario.Nombre,
                apellido:        datosUsuario.Apellido,
                nombre_completo: datosUsuario.nombre_completo,
                direccion:       datosUsuario.Direccion,
                telefono:        datosUsuario.Telefono,
                edad:            datosUsuario.Edad,
                cuenta: {
                    numero_cuenta: datosUsuario.Numero_cuenta,
                    saldo:         datosUsuario.Saldo,
                    estado:        datosUsuario.estado_cuenta,
                },
                tarjeta: {
                    numero_tarjeta:    datosUsuario.Numero_tarjeta,
                    pin:               datosUsuario.Pin,   // hash bcrypt
                    tipo_tarjeta:      datosUsuario.Tipo_tarjeta,
                    fecha_vencimiento: datosUsuario.Fecha_vencimiento,
                },
            },
            transacciones: otrasTransacciones,
            depositos,
        });

    } catch (err) {
        console.error('Error en DatosUsuario:', err);
        return res.status(500).json({ error: 'Error interno al obtener datos del usuario' });
    }
};

export const getUsuariosCompleto = async (req, res) => {
    const db = await connect();
    const [rows] = await db.query('SELECT * FROM vista_usuarios_completo');
    res.json(rows);
};



// Genera un PIN de 4 dígitos aleatorio
// Genera PIN de 4 dígitos
function generarPin() {
    return Math.floor(1000 + Math.random() * 9000).toString();
}

// Genera número de cuenta de 16 dígitos único
function generarNumeroCuenta() {
    const timestamp = Date.now().toString().slice(-8);
    const random    = Math.floor(10000000 + Math.random() * 90000000).toString();
    return timestamp + random; // 16 dígitos
}

// Genera número de tarjeta de 16 dígitos con prefijo 4 (estilo Visa)
function generarNumeroTarjeta() {
    const prefijo  = "4";                // prefijo tipo Visa
    const timestamp = Date.now().toString().slice(-7);
    const random    = Math.floor(100000000 + Math.random() * 900000000).toString();
    return (prefijo + timestamp + random).slice(0, 16); // exactamente 16 dígitos
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
        tipo_tarjeta, tipo_cuenta
    } = req.body;

    try {
        // Valores autogenerados
        const pin               = generarPin();
        const numero_cuenta     = generarNumeroCuenta();
        const numero_tarjeta    = generarNumeroTarjeta();
        const fecha_vencimiento = generarFechaVencimiento();
        const saldo_inicial     = 0.00;
        const id_rol            = 2; // Cliente por defecto

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

        // Devolver datos generados UNA sola vez para que el usuario los guarde
        res.json({
            usuarioId:        output.usuario_id,
            mensaje:          output.mensaje,
            numero_cuenta,
            numero_tarjeta,   // mostrar solo aquí, viene de la generación automática
            fecha_vencimiento,
            pin               // solo se muestra aquí, nunca más se puede recuperar
        });

    } catch (err) {
        console.error('Error al registrar usuario:', err);
        res.status(500).json({ error: 'Error interno al intentar crear el usuario' });
    }
};



