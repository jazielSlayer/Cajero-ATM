import { connect } from "../database.js"; 

export const getCuentasUsuario = async (req, res) => {
    const connection = await connect();
    const { nombre } = req.body;

    try {
        const [rows] = await connection.query(
            'CALL sp_cuentas_usuario(?)',
            [nombre]
        );

        res.json(rows[0]);
    } catch (err) {
        console.error('Error al obtener cuentas:', err);
        res.status(500).json({ error: 'Error interno al obtener cuentas' });
    }
};

export const getEstadoCuenta = async (req, res) => {
    const connection = await connect();
    const { nombre_completo } = req.body;

    try {
        const [results] = await connection.query(
            'CALL sp_estado_cuenta(?)',
            [nombre_completo]
        );

        // El SP devuelve 3 result sets: info usuario, cuentas, últimas 5 transacciones
        res.json({
            usuario:        results[0][0],
            cuentas:        results[1],
            transacciones:  results[2]
        });
    } catch (err) {
        console.error('Error al obtener estado de cuenta:', err);
        res.status(500).json({ error: 'Error interno al obtener estado de cuenta' });
    }
};