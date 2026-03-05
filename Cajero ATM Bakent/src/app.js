import express from 'express';
import cors from 'cors';
import morgan from 'morgan';

import swaggerJSDoc from 'swagger-jsdoc';
import swaggerUi from 'swagger-ui-express';
import { options } from './swaggerOptions';

const specs = swaggerJSDoc(options);


import users from './routes/routes_users'
import cuentasYTransacciones from './routes/vistas/routes_cuentas_y_transacciones';
import estadisticaYSesiones from './routes/vistas/routes_estadistica_y_seciones';
import tarjeta from './routes/routes_tarjeta';
import  transacciones from './routes/routes_transacciones';
import login from './routes/routes_login';
import cuentas from './routes/routes_cuentas';

const app = express();




app.use(cors());
app.use(morgan('dev'));
app.use(express.json());
app.use(express.urlencoded({ extended: true }));

app.use(users);
app.use(cuentasYTransacciones);
app.use(estadisticaYSesiones);
app.use(tarjeta);
app.use(transacciones);
app.use(login);
app.use(cuentas);

app.use('/docs', swaggerUi.serve, swaggerUi.setup(specs));

export default app;