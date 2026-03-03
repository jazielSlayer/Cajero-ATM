import { Router } from "express"; 
import { cambiarEstadoTarjeta } from "../controlers/tarjeta";

const router = Router();

// cambiar estado de tarjeta
router.put("/cambiar/estado/tarjeta", cambiarEstadoTarjeta);



export default router;