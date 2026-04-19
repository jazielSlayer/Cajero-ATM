import { Router } from "express";
import { getActividadCompleta, exportarTransaccionesCSV } from "../controlers/actividad.js";

const router = Router();

/**
 * POST /api/actividad/completa
 * Body: { nombre_completo, fecha_desde?, fecha_hasta?, tipo_transaccion?, palabra_clave?, numero_cuenta? }
 * Retorna: usuario, cuentas, transacciones filtradas, resumen, gráficos, notificaciones
 */
router.post("/actividad/completa", getActividadCompleta);

/**
 * POST /api/actividad/exportar
 * Body: { nombre_completo, fecha_desde?, fecha_hasta?, tipo_transaccion?, palabra_clave? }
 * Retorna: { csv: string, total: number }
 */
router.post("/actividad/exportar", exportarTransaccionesCSV);

export default router;