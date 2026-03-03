import { Router } from "express"; 
import { getSesionesActivas, getEstadisticasSistema } from "../../controlers/vistas/estadistica_y_sesiones";

const router = Router();

router.get("/sesionesactivas", getSesionesActivas);
router.get("/estadisticassistema", getEstadisticasSistema);


export default router;