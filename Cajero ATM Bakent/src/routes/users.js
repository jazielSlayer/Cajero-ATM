import { Router } from "express"; 
import { getUsers } from "../controlers/users";

const router = Router();

router.get("/users", getUsers);


export default router;