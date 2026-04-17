import { Router } from "express";
import {
    DatosUsuario,
    getUsuariosCompleto,
    createUser,
    consultarSaldosUsuario,
    solicitarVerificacion,
    confirmarCodigo,
} from "../controlers/users.js";

const router = Router();

router.post("/usuario/solicitar-verificacion", solicitarVerificacion);
router.post("/usuario/confirmar-codigo",       confirmarCodigo);

router.get("/usuarios/completo",               getUsuariosCompleto);
router.post("/crear/usuario",                  createUser);
router.post("/usuario/datos",                  DatosUsuario);
router.get("/usuario/saldo/:nombre_completo",  consultarSaldosUsuario);

export default router;