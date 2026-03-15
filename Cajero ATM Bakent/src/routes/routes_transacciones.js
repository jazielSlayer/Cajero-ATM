import { Router } from "express"; 
import { realizarRetiro, realizarTransferencia, getTransaccionesUsuario, realizarDeposito, consultarSaldos, consultarTasas } from "../controlers/transacciones.js";

const router = Router();

// listado de usuarios con información completa
router.post("/retiro", realizarRetiro);

router.post("/deposito", realizarDeposito);

// realizar transferencia
router.post("/transferencia", realizarTransferencia);

// obtener transacciones de un usuario
router.post("/transacciones/usuario", getTransaccionesUsuario);

router.get("/saldos/:numero_cuenta", consultarSaldos);
 
/**
 * GET /api/transacciones/tasas
 * Devuelve las tasas de cambio actuales cacheadas en BD
 */
router.get("/tasas", consultarTasas);

export default router;