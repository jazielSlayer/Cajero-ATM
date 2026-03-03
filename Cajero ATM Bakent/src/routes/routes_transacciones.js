import { Router } from "express"; 
import { realizarRetiro, realizarTransferencia, getTransaccionesUsuario } from "../controlers/transacciones";

const router = Router();

// listado de usuarios con información completa
router.get("/retiro", realizarRetiro);

// realizar transferencia
router.post("/transferencia", realizarTransferencia);

// obtener transacciones de un usuario
router.get("/transacciones/usuario", getTransaccionesUsuario);

export default router;