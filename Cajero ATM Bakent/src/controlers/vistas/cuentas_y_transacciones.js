import { connect } from "../../database";



export const getCuentasResumen = async (req, res) => {
    const db = await connect();
    const [rows] = await db.query('SELECT * FROM vista_cuentas_resumen');
    res.json(rows);
};


export const getTransaccionesCompleto = async (req, res) => {
    const db = await connect();
    const [rows] = await db.query('SELECT * FROM vista_transacciones_completo');
    res.json(rows);
};