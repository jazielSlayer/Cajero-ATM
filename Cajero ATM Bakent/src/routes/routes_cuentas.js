import { Router } from "express"; 
import { getCuentasUsuario, getEstadoCuenta } from "../controlers/cuentas";

const router = Router();

// listado de usuarios con información completa
router.post("/cuentas/usuario", getCuentasUsuario);

// obtener estado de cuenta
router.post("/estado/cuenta/usuario", getEstadoCuenta);

export default router;