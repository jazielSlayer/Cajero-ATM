import { Router } from "express"; 
import { realizarRetiro, realizarTransferencia, getTransaccionesUsuario, realizarDeposito } from "../controlers/transacciones";

const router = Router();

// listado de usuarios con información completa
router.post("/retiro", realizarRetiro);

router.post("/deposito", realizarDeposito);

// realizar transferencia
router.post("/transferencia", realizarTransferencia);

// obtener transacciones de un usuario
router.post("/transacciones/usuario", getTransaccionesUsuario);

export default router;