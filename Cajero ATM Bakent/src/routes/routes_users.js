import { Router } from "express"; 
import { getUsuariosCompleto, createUser } from "../controlers/users";

const router = Router();

// listado de usuarios con información completa
router.get("/usuarios/completo", getUsuariosCompleto);

// crear nuevo usuario mediante procedimiento almacenado
router.post("/crear/usuario", createUser);

export default router;