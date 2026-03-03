import { Router } from "express"; 
import { getCuentasUsuario, getEstadoCuenta } from "../controlers/cuentas";

const router = Router();

// listado de usuarios con información completa
router.get("/cuentas/usuario", getCuentasUsuario);

// obtener estado de cuenta
router.get("/estado/cuenta/usuario", getEstadoCuenta);

export default router;