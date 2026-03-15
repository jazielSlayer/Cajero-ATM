import { Router } from "express"; 
import { DatosUsuario, getUsuariosCompleto, createUser, consultarSaldosUsuario } from "../controlers/users";

const router = Router();

// listado de usuarios con información completa
router.get("/usuarios/completo", getUsuariosCompleto);

// crear nuevo usuario mediante procedimiento almacenado
router.post("/crear/usuario", createUser);

router.post("/usuario/datos", DatosUsuario)

router.get("/usuario/saldo/:nombre_completo", consultarSaldosUsuario)

export default router;