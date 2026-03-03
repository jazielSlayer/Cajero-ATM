import { Router } from "express"; 
import { loginUser } from "../controlers/login";

const router = Router();

// listado de usuarios con información completa
router.post("/login", loginUser);


export default router;