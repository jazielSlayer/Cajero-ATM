import { connect } from "../../database";



export const getSesionesActivas = async (req, res) => {
    const db = await connect();
    const [rows] = await db.query('SELECT * FROM vista_sesiones_activas');
    res.json(rows);
};


export const getEstadisticasSistema = async (req, res) => {
    const db = await connect();
    const [rows] = await db.query('SELECT * FROM vista_estadisticas_sistema');
    res.json(rows);
};