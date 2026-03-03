import { connect } from "../database.js"; 

export const getCuentasUsuario = async (req, res) => {
    const connection = await connect();
    const { usuario_id } = req.params;

    try {
        const [rows] = await connection.query(
            'CALL sp_cuentas_usuario(?)',
            [usuario_id]
        );

        res.json(rows[0]);
    } catch (err) {
        console.error('Error al obtener cuentas:', err);
        res.status(500).json({ error: 'Error interno al obtener cuentas' });
    }
};

export const getEstadoCuenta = async (req, res) => {
    const connection = await connect();
    const { usuario_id } = req.params;

    try {
        const [results] = await connection.query(
            'CALL sp_estado_cuenta(?)',
            [usuario_id]
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