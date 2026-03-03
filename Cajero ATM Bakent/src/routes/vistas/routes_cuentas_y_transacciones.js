import { Router } from "express"; 
import { getCuentasResumen, getTransaccionesCompleto } from "../../controlers/vistas/cuentas_y_transacciones";

const router = Router();

router.get("/cuentasresumen", getCuentasResumen);
router.get("/transaccionescompleto", getTransaccionesCompleto);


export default router;