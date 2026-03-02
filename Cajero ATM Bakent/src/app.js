import express from 'express';
import cors from 'cors';
import morgan from 'morgan';

import swaggerJSDoc from 'swagger-jsdoc';
import swaggerUi from 'swagger-ui-express';
import { options } from './swaggerOptions';

const specs = swaggerJSDoc(options);


import users from './routes/users'

const app = express();




app.use(cors());
app.use(morgan('dev'));
app.use(express.json());

app.use(users);


//app.use('/docs', swaggerUi.serve, swaggerUi.setup(specs));

export default app;