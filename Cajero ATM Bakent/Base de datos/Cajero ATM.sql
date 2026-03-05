-- phpMyAdmin SQL Dump
-- version 5.2.1
-- https://www.phpmyadmin.net/
--
-- Servidor: 127.0.0.1
-- Tiempo de generación: 05-03-2026 a las 01:10:37
-- Versión del servidor: 10.4.32-MariaDB
-- Versión de PHP: 8.1.25

SET SQL_MODE = "NO_AUTO_VALUE_ON_ZERO";
START TRANSACTION;
SET time_zone = "+00:00";


/*!40101 SET @OLD_CHARACTER_SET_CLIENT=@@CHARACTER_SET_CLIENT */;
/*!40101 SET @OLD_CHARACTER_SET_RESULTS=@@CHARACTER_SET_RESULTS */;
/*!40101 SET @OLD_COLLATION_CONNECTION=@@COLLATION_CONNECTION */;
/*!40101 SET NAMES utf8mb4 */;

--
-- Base de datos: `cajero_atm`
--

DELIMITER $$
--
-- Procedimientos
--
CREATE DEFINER=`root`@`localhost` PROCEDURE `sp_buscar_usuario_login` (IN `p_correo` VARCHAR(150))   BEGIN
    SELECT 
        u.ID AS usuario_id,
        u.Contrasena,
        u.Estado AS estado_usuario,
        u.ID_Rol,
        r.Nombre_rol,
        CONCAT(p.Nombre, ' ', p.Apellido) AS nombre_completo
    FROM Users u
    INNER JOIN Persona p ON u.ID_Persona = p.ID
    INNER JOIN Rol r ON u.ID_Rol = r.ID
    WHERE u.Correo = p_correo
    LIMIT 1;
END$$

CREATE DEFINER=`root`@`localhost` PROCEDURE `sp_cambiar_estado_tarjeta` (IN `p_tarjeta_id` INT, IN `p_usuario_id` INT, IN `p_nuevo_estado` ENUM('activa','bloqueada','cancelada'), OUT `p_mensaje` VARCHAR(255))   BEGIN
    DECLARE v_existe INT;

    SELECT COUNT(*) INTO v_existe 
    FROM Tarjeta 
    WHERE ID = p_tarjeta_id AND ID_Users = p_usuario_id;

    IF v_existe = 0 THEN
        SET p_mensaje = 'Error: Tarjeta no encontrada o no pertenece al usuario.';
    ELSE
        UPDATE Tarjeta SET Estado = p_nuevo_estado WHERE ID = p_tarjeta_id;
        SET p_mensaje = CONCAT('Tarjeta actualizada a estado: ', p_nuevo_estado);
    END IF;
END$$

CREATE DEFINER=`root`@`localhost` PROCEDURE `sp_cuentas_usuario` (IN `p_usuario_id` INT)   BEGIN
    SELECT 
        cuenta_id,
        Numero_cuenta,
        Tipo_cuenta,
        Saldo,
        estado_cuenta,
        fecha_apertura,
        Numero_tarjeta,
        Tipo_tarjeta,
        estado_tarjeta,
        Fecha_vencimiento
    FROM vista_cuentas_resumen
    WHERE usuario_id = p_usuario_id
    ORDER BY fecha_apertura DESC;
END$$

CREATE DEFINER=`root`@`localhost` PROCEDURE `sp_estado_cuenta` (IN `p_usuario_id` INT)   BEGIN
    -- Info del usuario
    SELECT 
        nombre_completo,
        Correo,
        estado_usuario,
        fecha_registro,
        rol
    FROM vista_usuarios_completo
    WHERE usuario_id = p_usuario_id;

    -- Cuentas con saldo y tarjetas
    SELECT 
        cuenta_id,
        Numero_cuenta,
        Tipo_cuenta,
        Saldo,
        estado_cuenta,
        fecha_apertura,
        Numero_tarjeta,
        Tipo_tarjeta,
        estado_tarjeta,
        Fecha_vencimiento
    FROM vista_cuentas_resumen
    WHERE usuario_id = p_usuario_id;

    -- Últimas 5 transacciones
    SELECT 
        transaccion_id,
        tipo_transaccion,
        Monto,
        Saldo_posterior AS saldo_tras_operacion,
        cuenta_origen,
        cuenta_destino,
        Metodo_transaccion,
        estado_transaccion,
        Fecha_transaccion
    FROM vista_transacciones_completo
    WHERE usuario_id = p_usuario_id
    ORDER BY Fecha_transaccion DESC
    LIMIT 5;
END$$

CREATE DEFINER=`root`@`localhost` PROCEDURE `sp_realizar_deposito` (IN `p_correo` VARCHAR(150), IN `p_monto` DECIMAL(15,2), IN `p_metodo` ENUM('ATM','web','app_movil'), IN `p_contrasena` VARCHAR(255), IN `p_pin` VARCHAR(255), OUT `p_transaccion_id` INT, OUT `p_mensaje` VARCHAR(255))   BEGIN
    DECLARE v_cuenta_id     INT;
    DECLARE v_saldo         DECIMAL(15,2);
    DECLARE v_estado_cuenta VARCHAR(20);
    DECLARE v_usuario_id    INT;
    DECLARE v_contrasena_bd VARCHAR(255);
    DECLARE v_pin_bd        VARCHAR(255);
    DECLARE v_estado_usuario VARCHAR(20);
    DECLARE v_estado_tarjeta VARCHAR(20);
    DECLARE v_tipo_deposito INT;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SET p_transaccion_id = -1;
        SET p_mensaje = 'Error interno: Depósito cancelado.';
    END;

    -- Obtener usuario por correo
    SELECT u.ID, u.Contrasena, u.Estado
    INTO v_usuario_id, v_contrasena_bd, v_estado_usuario
    FROM Users u
    WHERE u.Correo = p_correo
    LIMIT 1;

    -- Validar usuario existe
    IF v_usuario_id IS NULL THEN
        SET p_transaccion_id = -1;
        SET p_mensaje = 'Error: Usuario no encontrado.';

    ELSEIF v_estado_usuario != 'activo' THEN
        SET p_transaccion_id = -1;
        SET p_mensaje = 'Error: El usuario no está activo.';

    ELSEIF v_contrasena_bd != p_contrasena THEN
        SET p_transaccion_id = -1;
        SET p_mensaje = 'Error: Contraseña incorrecta.';

    ELSE
        -- Obtener cuenta activa del usuario
        SELECT ID, Saldo, Estado
        INTO v_cuenta_id, v_saldo, v_estado_cuenta
        FROM Cuenta
        WHERE ID_Users = v_usuario_id AND Estado = 'activa'
        LIMIT 1;

        -- Obtener PIN de la tarjeta asociada
        SELECT Pin, Estado
        INTO v_pin_bd, v_estado_tarjeta
        FROM Tarjeta
        WHERE ID_Cuenta = v_cuenta_id AND Estado = 'activa'
        LIMIT 1;

        -- Obtener tipo depósito
        SELECT ID INTO v_tipo_deposito
        FROM Tipo_Transaccion WHERE Nombre = 'Deposito';

        IF v_cuenta_id IS NULL THEN
            SET p_transaccion_id = -1;
            SET p_mensaje = 'Error: No se encontró una cuenta activa.';

        ELSEIF v_pin_bd IS NULL THEN
            SET p_transaccion_id = -1;
            SET p_mensaje = 'Error: No se encontró una tarjeta activa.';

        ELSEIF v_pin_bd != p_pin THEN
            SET p_transaccion_id = -1;
            SET p_mensaje = 'Error: PIN incorrecto.';

        ELSEIF p_monto <= 0 THEN
            SET p_transaccion_id = -1;
            SET p_mensaje = 'Error: El monto debe ser mayor a 0.';

        ELSE
            START TRANSACTION;

            UPDATE Cuenta
            SET Saldo = Saldo + p_monto
            WHERE ID = v_cuenta_id;

            INSERT INTO Transacciones (
                ID_Cuenta_Transfiere, ID_Tipo_Transaccion, Monto,
                Saldo_anterior, Saldo_posterior, Metodo_transaccion, Estado
            ) VALUES (
                v_cuenta_id, v_tipo_deposito, p_monto,
                v_saldo, (v_saldo + p_monto), p_metodo, 'exitosa'
            );

            SET p_transaccion_id = LAST_INSERT_ID();
            COMMIT;
            SET p_mensaje = CONCAT('Depósito exitoso. Nuevo saldo: ', (v_saldo + p_monto));
        END IF;
    END IF;
END$$

CREATE DEFINER=`root`@`localhost` PROCEDURE `sp_realizar_retiro` (IN `p_cuenta_id` INT, IN `p_monto` DECIMAL(15,2), IN `p_metodo` ENUM('ATM','web','app_movil'), OUT `p_transaccion_id` INT, OUT `p_mensaje` VARCHAR(255))   BEGIN
    DECLARE v_saldo DECIMAL(15,2);
    DECLARE v_estado VARCHAR(20);
    DECLARE v_tipo_retiro INT;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SET p_transaccion_id = -1;
        SET p_mensaje = 'Error interno: Retiro cancelado.';
    END;

    SELECT Saldo, Estado INTO v_saldo, v_estado FROM Cuenta WHERE ID = p_cuenta_id;
    SELECT ID INTO v_tipo_retiro FROM Tipo_Transaccion WHERE Nombre = 'Retiro';

    IF v_estado != 'activa' THEN
        SET p_transaccion_id = -1;
        SET p_mensaje = 'Error: La cuenta no está activa.';
    ELSEIF v_saldo < p_monto THEN
        SET p_transaccion_id = -1;
        SET p_mensaje = 'Error: Saldo insuficiente.';
    ELSEIF p_monto <= 0 THEN
        SET p_transaccion_id = -1;
        SET p_mensaje = 'Error: El monto debe ser mayor a 0.';
    ELSE
        START TRANSACTION;

        UPDATE Cuenta SET Saldo = Saldo - p_monto WHERE ID = p_cuenta_id;

        INSERT INTO Transacciones (
            ID_Cuenta_Transfiere, ID_Tipo_Transaccion, Monto,
            Saldo_anterior, Saldo_posterior, Metodo_transaccion, Estado
        ) VALUES (
            p_cuenta_id, v_tipo_retiro, p_monto,
            v_saldo, (v_saldo - p_monto), p_metodo, 'exitosa'
        );

        SET p_transaccion_id = LAST_INSERT_ID();
        COMMIT;
        SET p_mensaje = CONCAT('Retiro exitoso. Saldo disponible: ', (v_saldo - p_monto));
    END IF;
END$$

CREATE DEFINER=`root`@`localhost` PROCEDURE `sp_realizar_transferencia` (IN `p_cuenta_origen_id` INT, IN `p_cuenta_destino_id` INT, IN `p_monto` DECIMAL(15,2), IN `p_metodo` ENUM('ATM','web','app_movil'), IN `p_descripcion` VARCHAR(255), OUT `p_transaccion_id` INT, OUT `p_mensaje` VARCHAR(255))   BEGIN
    DECLARE v_saldo_origen DECIMAL(15,2);
    DECLARE v_saldo_destino DECIMAL(15,2);
    DECLARE v_estado_origen VARCHAR(20);
    DECLARE v_estado_destino VARCHAR(20);
    DECLARE v_tipo_transferencia INT;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SET p_transaccion_id = -1;
        SET p_mensaje = 'Error interno: Transferencia cancelada.';
    END;

    -- Obtener datos de cuentas
    SELECT Saldo, Estado INTO v_saldo_origen, v_estado_origen FROM Cuenta WHERE ID = p_cuenta_origen_id;
    SELECT Saldo, Estado INTO v_saldo_destino, v_estado_destino FROM Cuenta WHERE ID = p_cuenta_destino_id;
    SELECT ID INTO v_tipo_transferencia FROM Tipo_Transaccion WHERE Nombre = 'Transferencia';

    -- Validaciones
    IF v_estado_origen != 'activa' THEN
        SET p_transaccion_id = -1;
        SET p_mensaje = 'Error: La cuenta origen no está activa.';
    ELSEIF v_estado_destino != 'activa' THEN
        SET p_transaccion_id = -1;
        SET p_mensaje = 'Error: La cuenta destino no está activa.';
    ELSEIF v_saldo_origen < p_monto THEN
        SET p_transaccion_id = -1;
        SET p_mensaje = 'Error: Saldo insuficiente.';
    ELSEIF p_monto <= 0 THEN
        SET p_transaccion_id = -1;
        SET p_mensaje = 'Error: El monto debe ser mayor a 0.';
    ELSE
        START TRANSACTION;

        -- Descontar de origen
        UPDATE Cuenta SET Saldo = Saldo - p_monto WHERE ID = p_cuenta_origen_id;
        -- Acreditar a destino
        UPDATE Cuenta SET Saldo = Saldo + p_monto WHERE ID = p_cuenta_destino_id;

        -- Registrar transacción
        INSERT INTO Transacciones (
            ID_Cuenta_Transfiere, ID_Cuenta_Transferida, ID_Tipo_Transaccion,
            Monto, Saldo_anterior, Saldo_posterior, Metodo_transaccion, Estado, Descripcion
        ) VALUES (
            p_cuenta_origen_id, p_cuenta_destino_id, v_tipo_transferencia,
            p_monto, v_saldo_origen, (v_saldo_origen - p_monto), p_metodo, 'exitosa', p_descripcion
        );

        SET p_transaccion_id = LAST_INSERT_ID();
        COMMIT;
        SET p_mensaje = CONCAT('Transferencia exitosa. Nuevo saldo: ', (v_saldo_origen - p_monto));
    END IF;
END$$

CREATE DEFINER=`root`@`localhost` PROCEDURE `sp_registrar_usuario` (IN `p_nombre` VARCHAR(100), IN `p_apellido` VARCHAR(100), IN `p_direccion` VARCHAR(255), IN `p_telefono` VARCHAR(20), IN `p_edad` INT, IN `p_correo` VARCHAR(150), IN `p_contrasena` VARCHAR(255), IN `p_id_rol` INT, IN `p_numero_cuenta` VARCHAR(20), IN `p_tipo_cuenta` ENUM('ahorro','corriente'), IN `p_saldo_inicial` DECIMAL(15,2), IN `p_numero_tarjeta` VARCHAR(16), IN `p_pin` VARCHAR(255), IN `p_tipo_tarjeta` ENUM('debito','credito'), IN `p_fecha_vencimiento` DATE, OUT `p_usuario_id` INT, OUT `p_mensaje` VARCHAR(255))   BEGIN
    DECLARE v_persona_id INT;
    DECLARE v_cuenta_id INT;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SET p_usuario_id = -1;
        SET p_mensaje = 'Error: No se pudo registrar el usuario. Verifique los datos.';
    END;

    -- Validaciones previas
    IF EXISTS (SELECT 1 FROM Users WHERE Correo = p_correo) THEN
        SET p_usuario_id = -1;
        SET p_mensaje = 'Error: El correo ya está registrado.';
    ELSEIF EXISTS (SELECT 1 FROM Cuenta WHERE Numero_cuenta = p_numero_cuenta) THEN
        SET p_usuario_id = -1;
        SET p_mensaje = 'Error: El número de cuenta ya existe.';
    ELSEIF EXISTS (SELECT 1 FROM Tarjeta WHERE Numero_tarjeta = p_numero_tarjeta) THEN
        SET p_usuario_id = -1;
        SET p_mensaje = 'Error: El número de tarjeta ya existe.';
    ELSE
        START TRANSACTION;

        -- 1. Insertar Persona
        INSERT INTO Persona (Nombre, Apellido, Direccion, Telefono, Edad)
        VALUES (p_nombre, p_apellido, p_direccion, p_telefono, p_edad);
        SET v_persona_id = LAST_INSERT_ID();

        -- 2. Insertar User
        INSERT INTO Users (ID_Persona, ID_Rol, Correo, Contrasena)
        VALUES (v_persona_id, p_id_rol, p_correo, p_contrasena);
        SET p_usuario_id = LAST_INSERT_ID();

        -- 3. Insertar Cuenta
        INSERT INTO Cuenta (Numero_cuenta, ID_Users, Tipo_cuenta, Saldo)
        VALUES (p_numero_cuenta, p_usuario_id, p_tipo_cuenta, p_saldo_inicial);
        SET v_cuenta_id = LAST_INSERT_ID();

        -- 4. Insertar Tarjeta
        INSERT INTO Tarjeta (ID_Users, ID_Cuenta, Numero_tarjeta, Pin, Tipo_tarjeta, Fecha_vencimiento)
        VALUES (p_usuario_id, v_cuenta_id, p_numero_tarjeta, p_pin, p_tipo_tarjeta, p_fecha_vencimiento);

        COMMIT;
        SET p_mensaje = 'Usuario registrado exitosamente.';
    END IF;
END$$

CREATE DEFINER=`root`@`localhost` PROCEDURE `sp_transacciones_usuario` (IN `p_usuario_id` INT, IN `p_fecha_inicio` DATE, IN `p_fecha_fin` DATE, IN `p_tipo_transaccion` INT, IN `p_limite` INT)   BEGIN
    SET p_fecha_inicio = IFNULL(p_fecha_inicio, '2000-01-01');
    SET p_fecha_fin = IFNULL(p_fecha_fin, CURDATE());
    SET p_limite = IFNULL(p_limite, 999999);

    SELECT 
        transaccion_id,
        tipo_transaccion,
        Monto,
        Saldo_anterior,
        Saldo_posterior,
        cuenta_origen,
        cuenta_destino,
        nombre_destinatario,
        Metodo_transaccion,
        estado_transaccion,
        Descripcion,
        Fecha_transaccion
    FROM vista_transacciones_completo
    WHERE usuario_id = p_usuario_id
      AND DATE(Fecha_transaccion) BETWEEN p_fecha_inicio AND p_fecha_fin
      AND (p_tipo_transaccion IS NULL OR ID_Tipo_Transaccion = p_tipo_transaccion)
    ORDER BY Fecha_transaccion DESC
    LIMIT p_limite;
END$$

DELIMITER ;

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `cuenta`
--

CREATE TABLE `cuenta` (
  `ID` int(11) NOT NULL,
  `Numero_cuenta` varchar(20) NOT NULL,
  `ID_Users` int(11) NOT NULL,
  `Tipo_cuenta` enum('ahorro','corriente') NOT NULL DEFAULT 'ahorro',
  `Saldo` decimal(15,2) NOT NULL DEFAULT 0.00,
  `Estado` enum('activa','bloqueada','cerrada') DEFAULT 'activa',
  `Fecha_creacion` datetime DEFAULT current_timestamp(),
  `Fecha_modificacion` datetime DEFAULT current_timestamp() ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

--
-- Volcado de datos para la tabla `cuenta`
--

INSERT INTO `cuenta` (`ID`, `Numero_cuenta`, `ID_Users`, `Tipo_cuenta`, `Saldo`, `Estado`, `Fecha_creacion`, `Fecha_modificacion`) VALUES
(1, '1000200030004001', 1, 'ahorro', 0.00, 'activa', '2026-03-02 20:28:14', '2026-03-04 19:27:42'),
(2, '3454321234321', 4, 'corriente', 1000050.00, 'activa', '2026-03-02 22:09:52', '2026-03-04 19:27:42'),
(3, '1234567890', 5, 'ahorro', 1000.00, 'activa', '2026-03-03 14:18:40', '2026-03-03 14:18:40'),
(4, '01872812992', 6, 'ahorro', 9999999999999.99, 'activa', '2026-03-04 19:02:28', '2026-03-04 20:04:24');

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `persona`
--

CREATE TABLE `persona` (
  `ID` int(11) NOT NULL,
  `Nombre` varchar(100) NOT NULL,
  `Apellido` varchar(100) NOT NULL,
  `Direccion` varchar(255) DEFAULT NULL,
  `Telefono` varchar(20) DEFAULT NULL,
  `Edad` int(11) DEFAULT NULL CHECK (`Edad` >= 18),
  `Fecha_creacion` datetime DEFAULT current_timestamp(),
  `Fecha_modificacion` datetime DEFAULT current_timestamp() ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

--
-- Volcado de datos para la tabla `persona`
--

INSERT INTO `persona` (`ID`, `Nombre`, `Apellido`, `Direccion`, `Telefono`, `Edad`, `Fecha_creacion`, `Fecha_modificacion`) VALUES
(1, 'Juan', 'Pérez', 'Av. Siempre Viva 123', '70012345', 28, '2026-03-02 20:28:14', '2026-03-02 20:28:14'),
(4, 'Jaziel', 'Vargas', 'limanipata', '34414', 1441, '2026-03-02 22:09:52', '2026-03-02 22:09:52'),
(5, 'Juan Perez', 'Garcia', 'Calle Falsa 123', '555-1234', 30, '2026-03-03 14:18:40', '2026-03-03 14:18:40'),
(6, 'Jaziel Armando', 'Vargas cHoque', 'Calle Falsa 123', '8929202', 21, '2026-03-04 19:02:28', '2026-03-04 19:02:28');

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `rol`
--

CREATE TABLE `rol` (
  `ID` int(11) NOT NULL,
  `Nombre_rol` varchar(50) NOT NULL,
  `Fecha_creacion` datetime DEFAULT current_timestamp(),
  `Fecha_modificacion` datetime DEFAULT current_timestamp() ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

--
-- Volcado de datos para la tabla `rol`
--

INSERT INTO `rol` (`ID`, `Nombre_rol`, `Fecha_creacion`, `Fecha_modificacion`) VALUES
(1, 'Administrador', '2026-03-02 20:13:25', '2026-03-02 20:13:25'),
(2, 'Cliente', '2026-03-02 20:13:25', '2026-03-02 20:13:25'),
(3, 'Operador', '2026-03-02 20:13:25', '2026-03-02 20:13:25');

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `sesion_atm`
--

CREATE TABLE `sesion_atm` (
  `ID` int(11) NOT NULL,
  `ID_Tarjeta` int(11) NOT NULL,
  `ID_Users` int(11) NOT NULL,
  `Intentos_pin` int(11) DEFAULT 0,
  `Estado` enum('activa','cerrada','bloqueada_por_intentos') DEFAULT 'activa',
  `IP_acceso` varchar(45) DEFAULT NULL,
  `Fecha_inicio` datetime DEFAULT current_timestamp(),
  `Fecha_fin` datetime DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `tarjeta`
--

CREATE TABLE `tarjeta` (
  `ID` int(11) NOT NULL,
  `ID_Users` int(11) NOT NULL,
  `ID_Cuenta` int(11) NOT NULL,
  `Numero_tarjeta` varchar(16) NOT NULL,
  `Pin` varchar(255) NOT NULL,
  `Tipo_tarjeta` enum('debito','credito') NOT NULL DEFAULT 'debito',
  `Estado` enum('activa','bloqueada','vencida','cancelada') DEFAULT 'activa',
  `Fecha_vencimiento` date NOT NULL,
  `Fecha_creacion` datetime DEFAULT current_timestamp(),
  `Fecha_modificacion` datetime DEFAULT current_timestamp() ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

--
-- Volcado de datos para la tabla `tarjeta`
--

INSERT INTO `tarjeta` (`ID`, `ID_Users`, `ID_Cuenta`, `Numero_tarjeta`, `Pin`, `Tipo_tarjeta`, `Estado`, `Fecha_vencimiento`, `Fecha_creacion`, `Fecha_modificacion`) VALUES
(1, 1, 1, '4111111111111111', '$2b$10$hashpindelbackend', 'debito', 'activa', '2028-12-31', '2026-03-02 20:28:14', '2026-03-02 20:28:14'),
(2, 4, 2, '123454321|12354', '1221', 'credito', 'activa', '0000-00-00', '2026-03-02 22:09:52', '2026-03-02 22:09:52'),
(3, 5, 3, '9876543210', '1234', 'debito', 'activa', '2025-12-31', '2026-03-03 14:18:40', '2026-03-03 14:18:40'),
(4, 6, 4, '1000282973', '777', 'debito', 'activa', '2025-12-31', '2026-03-04 19:02:28', '2026-03-04 20:00:54');

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `tipo_transaccion`
--

CREATE TABLE `tipo_transaccion` (
  `ID` int(11) NOT NULL,
  `Nombre` varchar(50) NOT NULL,
  `Descripcion` varchar(255) DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

--
-- Volcado de datos para la tabla `tipo_transaccion`
--

INSERT INTO `tipo_transaccion` (`ID`, `Nombre`, `Descripcion`) VALUES
(1, 'Retiro', 'Extracción de efectivo'),
(2, 'Deposito', 'Ingreso de efectivo'),
(3, 'Transferencia', 'Transferencia entre cuentas'),
(4, 'Consulta_saldo', 'Consulta de saldo'),
(5, 'Pago_servicio', 'Pago de servicios');

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `transacciones`
--

CREATE TABLE `transacciones` (
  `ID` int(11) NOT NULL,
  `ID_Cuenta_Transfiere` int(11) NOT NULL,
  `ID_Cuenta_Transferida` int(11) DEFAULT NULL,
  `ID_Tipo_Transaccion` int(11) NOT NULL,
  `Monto` decimal(15,2) NOT NULL CHECK (`Monto` > 0),
  `Saldo_anterior` decimal(15,2) DEFAULT NULL,
  `Saldo_posterior` decimal(15,2) DEFAULT NULL,
  `Metodo_transaccion` enum('ATM','web','app_movil') NOT NULL DEFAULT 'ATM',
  `Estado` enum('exitosa','fallida','pendiente','revertida') DEFAULT 'exitosa',
  `Descripcion` varchar(255) DEFAULT NULL,
  `Fecha_transaccion` datetime DEFAULT current_timestamp(),
  `Fecha_creacion` datetime DEFAULT current_timestamp(),
  `Fecha_modificacion` datetime DEFAULT current_timestamp() ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

--
-- Volcado de datos para la tabla `transacciones`
--

INSERT INTO `transacciones` (`ID`, `ID_Cuenta_Transfiere`, `ID_Cuenta_Transferida`, `ID_Tipo_Transaccion`, `Monto`, `Saldo_anterior`, `Saldo_posterior`, `Metodo_transaccion`, `Estado`, `Descripcion`, `Fecha_transaccion`, `Fecha_creacion`, `Fecha_modificacion`) VALUES
(1, 1, NULL, 1, 300.00, 500.00, 200.00, 'web', 'exitosa', NULL, '2026-03-02 21:25:40', '2026-03-02 21:25:40', '2026-03-02 21:25:40'),
(2, 1, NULL, 1, 100.00, 200.00, 100.00, 'ATM', 'exitosa', NULL, '2026-03-04 19:20:42', '2026-03-04 19:20:42', '2026-03-04 19:20:42'),
(3, 1, NULL, 1, 50.00, 100.00, 50.00, 'ATM', 'exitosa', NULL, '2026-03-04 19:26:55', '2026-03-04 19:26:55', '2026-03-04 19:26:55'),
(4, 1, 2, 3, 50.00, 50.00, 0.00, 'web', 'exitosa', 'Pago de deuda', '2026-03-04 19:27:42', '2026-03-04 19:27:42', '2026-03-04 19:27:42'),
(6, 4, NULL, 2, 50000000000.00, 1000.00, 50000001000.00, 'web', 'exitosa', NULL, '2026-03-04 20:01:22', '2026-03-04 20:01:22', '2026-03-04 20:01:22'),
(7, 4, NULL, 2, 9999999999999.99, 50000001000.00, 9999999999999.99, 'ATM', 'exitosa', NULL, '2026-03-04 20:04:24', '2026-03-04 20:04:24', '2026-03-04 20:04:24');

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `users`
--

CREATE TABLE `users` (
  `ID` int(11) NOT NULL,
  `ID_Persona` int(11) NOT NULL,
  `ID_Rol` int(11) NOT NULL DEFAULT 2,
  `Correo` varchar(150) NOT NULL,
  `Contrasena` varchar(255) NOT NULL,
  `Estado` enum('activo','bloqueado','inactivo') DEFAULT 'activo',
  `Fecha_creacion` datetime DEFAULT current_timestamp(),
  `Fecha_modificacion` datetime DEFAULT current_timestamp() ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

--
-- Volcado de datos para la tabla `users`
--

INSERT INTO `users` (`ID`, `ID_Persona`, `ID_Rol`, `Correo`, `Contrasena`, `Estado`, `Fecha_creacion`, `Fecha_modificacion`) VALUES
(1, 1, 2, 'juan.perez@mail.com', '$2b$10$hashbcryptdelbackend', 'activo', '2026-03-02 20:28:14', '2026-03-02 20:28:14'),
(4, 4, 1, 'qkoqjsioqijs@gamsmma', '1234', 'activo', '2026-03-02 22:09:52', '2026-03-02 22:09:52'),
(5, 5, 1, 'juan.perez@example.com', 'contrasena123', 'activo', '2026-03-03 14:18:40', '2026-03-03 14:18:40'),
(6, 6, 1, 'jazielarmandovargaschoque@gmail.com', 'DrXeno79TESLA', 'activo', '2026-03-04 19:02:28', '2026-03-04 19:02:28');

-- --------------------------------------------------------

--
-- Estructura Stand-in para la vista `vista_cuentas_resumen`
-- (Véase abajo para la vista actual)
--
CREATE TABLE `vista_cuentas_resumen` (
`cuenta_id` int(11)
,`Numero_cuenta` varchar(20)
,`Tipo_cuenta` enum('ahorro','corriente')
,`Saldo` decimal(15,2)
,`estado_cuenta` enum('activa','bloqueada','cerrada')
,`fecha_apertura` datetime
,`usuario_id` int(11)
,`nombre_titular` varchar(201)
,`Correo` varchar(150)
,`Numero_tarjeta` varchar(16)
,`Tipo_tarjeta` enum('debito','credito')
,`estado_tarjeta` enum('activa','bloqueada','vencida','cancelada')
,`Fecha_vencimiento` date
);

-- --------------------------------------------------------

--
-- Estructura Stand-in para la vista `vista_estadisticas_sistema`
-- (Véase abajo para la vista actual)
--
CREATE TABLE `vista_estadisticas_sistema` (
`usuarios_activos` bigint(21)
,`cuentas_activas` bigint(21)
,`saldo_total_sistema` decimal(37,2)
,`transacciones_hoy` bigint(21)
,`monto_movido_hoy` decimal(37,2)
,`tarjetas_bloqueadas` bigint(21)
,`sesiones_en_curso` bigint(21)
);

-- --------------------------------------------------------

--
-- Estructura Stand-in para la vista `vista_sesiones_activas`
-- (Véase abajo para la vista actual)
--
CREATE TABLE `vista_sesiones_activas` (
`sesion_id` int(11)
,`Fecha_inicio` datetime
,`Intentos_pin` int(11)
,`estado_sesion` enum('activa','cerrada','bloqueada_por_intentos')
,`IP_acceso` varchar(45)
,`Correo` varchar(150)
,`nombre_usuario` varchar(201)
,`Numero_tarjeta` varchar(16)
,`minutos_activa` bigint(21)
);

-- --------------------------------------------------------

--
-- Estructura Stand-in para la vista `vista_transacciones_completo`
-- (Véase abajo para la vista actual)
--
CREATE TABLE `vista_transacciones_completo` (
`transaccion_id` int(11)
,`ID_Tipo_Transaccion` int(11)
,`Fecha_transaccion` datetime
,`Monto` decimal(15,2)
,`Saldo_anterior` decimal(15,2)
,`Saldo_posterior` decimal(15,2)
,`Metodo_transaccion` enum('ATM','web','app_movil')
,`estado_transaccion` enum('exitosa','fallida','pendiente','revertida')
,`Descripcion` varchar(255)
,`tipo_transaccion` varchar(50)
,`cuenta_origen` varchar(20)
,`tipo_cuenta_origen` enum('ahorro','corriente')
,`usuario_id` int(11)
,`nombre_remitente` varchar(201)
,`correo_remitente` varchar(150)
,`cuenta_destino` varchar(20)
,`nombre_destinatario` varchar(201)
,`correo_destinatario` varchar(150)
);

-- --------------------------------------------------------

--
-- Estructura Stand-in para la vista `vista_usuarios_completo`
-- (Véase abajo para la vista actual)
--
CREATE TABLE `vista_usuarios_completo` (
`usuario_id` int(11)
,`Correo` varchar(150)
,`estado_usuario` enum('activo','bloqueado','inactivo')
,`fecha_registro` datetime
,`persona_id` int(11)
,`Nombre` varchar(100)
,`Apellido` varchar(100)
,`nombre_completo` varchar(201)
,`Direccion` varchar(255)
,`Telefono` varchar(20)
,`Edad` int(11)
,`rol` varchar(50)
);

-- --------------------------------------------------------

--
-- Estructura para la vista `vista_cuentas_resumen`
--
DROP TABLE IF EXISTS `vista_cuentas_resumen`;

CREATE ALGORITHM=UNDEFINED DEFINER=`root`@`localhost` SQL SECURITY DEFINER VIEW `vista_cuentas_resumen`  AS SELECT `c`.`ID` AS `cuenta_id`, `c`.`Numero_cuenta` AS `Numero_cuenta`, `c`.`Tipo_cuenta` AS `Tipo_cuenta`, `c`.`Saldo` AS `Saldo`, `c`.`Estado` AS `estado_cuenta`, `c`.`Fecha_creacion` AS `fecha_apertura`, `u`.`ID` AS `usuario_id`, concat(`p`.`Nombre`,' ',`p`.`Apellido`) AS `nombre_titular`, `u`.`Correo` AS `Correo`, `tar`.`Numero_tarjeta` AS `Numero_tarjeta`, `tar`.`Tipo_tarjeta` AS `Tipo_tarjeta`, `tar`.`Estado` AS `estado_tarjeta`, `tar`.`Fecha_vencimiento` AS `Fecha_vencimiento` FROM (((`cuenta` `c` join `users` `u` on(`c`.`ID_Users` = `u`.`ID`)) join `persona` `p` on(`u`.`ID_Persona` = `p`.`ID`)) left join `tarjeta` `tar` on(`tar`.`ID_Cuenta` = `c`.`ID`)) ;

-- --------------------------------------------------------

--
-- Estructura para la vista `vista_estadisticas_sistema`
--
DROP TABLE IF EXISTS `vista_estadisticas_sistema`;

CREATE ALGORITHM=UNDEFINED DEFINER=`root`@`localhost` SQL SECURITY DEFINER VIEW `vista_estadisticas_sistema`  AS SELECT (select count(0) from `users` where `users`.`Estado` = 'activo') AS `usuarios_activos`, (select count(0) from `cuenta` where `cuenta`.`Estado` = 'activa') AS `cuentas_activas`, (select sum(`cuenta`.`Saldo`) from `cuenta` where `cuenta`.`Estado` = 'activa') AS `saldo_total_sistema`, (select count(0) from `transacciones` where cast(`transacciones`.`Fecha_transaccion` as date) = curdate()) AS `transacciones_hoy`, (select sum(`transacciones`.`Monto`) from `transacciones` where cast(`transacciones`.`Fecha_transaccion` as date) = curdate() and `transacciones`.`Estado` = 'exitosa') AS `monto_movido_hoy`, (select count(0) from `tarjeta` where `tarjeta`.`Estado` = 'bloqueada') AS `tarjetas_bloqueadas`, (select count(0) from `sesion_atm` where `sesion_atm`.`Estado` = 'activa') AS `sesiones_en_curso` ;

-- --------------------------------------------------------

--
-- Estructura para la vista `vista_sesiones_activas`
--
DROP TABLE IF EXISTS `vista_sesiones_activas`;

CREATE ALGORITHM=UNDEFINED DEFINER=`root`@`localhost` SQL SECURITY DEFINER VIEW `vista_sesiones_activas`  AS SELECT `s`.`ID` AS `sesion_id`, `s`.`Fecha_inicio` AS `Fecha_inicio`, `s`.`Intentos_pin` AS `Intentos_pin`, `s`.`Estado` AS `estado_sesion`, `s`.`IP_acceso` AS `IP_acceso`, `u`.`Correo` AS `Correo`, concat(`p`.`Nombre`,' ',`p`.`Apellido`) AS `nombre_usuario`, `tar`.`Numero_tarjeta` AS `Numero_tarjeta`, timestampdiff(MINUTE,`s`.`Fecha_inicio`,current_timestamp()) AS `minutos_activa` FROM (((`sesion_atm` `s` join `users` `u` on(`s`.`ID_Users` = `u`.`ID`)) join `persona` `p` on(`u`.`ID_Persona` = `p`.`ID`)) join `tarjeta` `tar` on(`s`.`ID_Tarjeta` = `tar`.`ID`)) WHERE `s`.`Estado` = 'activa' ;

-- --------------------------------------------------------

--
-- Estructura para la vista `vista_transacciones_completo`
--
DROP TABLE IF EXISTS `vista_transacciones_completo`;

CREATE ALGORITHM=UNDEFINED DEFINER=`root`@`localhost` SQL SECURITY DEFINER VIEW `vista_transacciones_completo`  AS SELECT `t`.`ID` AS `transaccion_id`, `t`.`ID_Tipo_Transaccion` AS `ID_Tipo_Transaccion`, `t`.`Fecha_transaccion` AS `Fecha_transaccion`, `t`.`Monto` AS `Monto`, `t`.`Saldo_anterior` AS `Saldo_anterior`, `t`.`Saldo_posterior` AS `Saldo_posterior`, `t`.`Metodo_transaccion` AS `Metodo_transaccion`, `t`.`Estado` AS `estado_transaccion`, `t`.`Descripcion` AS `Descripcion`, `tt`.`Nombre` AS `tipo_transaccion`, `co`.`Numero_cuenta` AS `cuenta_origen`, `co`.`Tipo_cuenta` AS `tipo_cuenta_origen`, `uo`.`ID` AS `usuario_id`, concat(`po`.`Nombre`,' ',`po`.`Apellido`) AS `nombre_remitente`, `uo`.`Correo` AS `correo_remitente`, `cd`.`Numero_cuenta` AS `cuenta_destino`, concat(`pd`.`Nombre`,' ',`pd`.`Apellido`) AS `nombre_destinatario`, `ud`.`Correo` AS `correo_destinatario` FROM (((((((`transacciones` `t` join `tipo_transaccion` `tt` on(`t`.`ID_Tipo_Transaccion` = `tt`.`ID`)) join `cuenta` `co` on(`t`.`ID_Cuenta_Transfiere` = `co`.`ID`)) join `users` `uo` on(`co`.`ID_Users` = `uo`.`ID`)) join `persona` `po` on(`uo`.`ID_Persona` = `po`.`ID`)) left join `cuenta` `cd` on(`t`.`ID_Cuenta_Transferida` = `cd`.`ID`)) left join `users` `ud` on(`cd`.`ID_Users` = `ud`.`ID`)) left join `persona` `pd` on(`ud`.`ID_Persona` = `pd`.`ID`)) ;

-- --------------------------------------------------------

--
-- Estructura para la vista `vista_usuarios_completo`
--
DROP TABLE IF EXISTS `vista_usuarios_completo`;

CREATE ALGORITHM=UNDEFINED DEFINER=`root`@`localhost` SQL SECURITY DEFINER VIEW `vista_usuarios_completo`  AS SELECT `u`.`ID` AS `usuario_id`, `u`.`Correo` AS `Correo`, `u`.`Estado` AS `estado_usuario`, `u`.`Fecha_creacion` AS `fecha_registro`, `p`.`ID` AS `persona_id`, `p`.`Nombre` AS `Nombre`, `p`.`Apellido` AS `Apellido`, concat(`p`.`Nombre`,' ',`p`.`Apellido`) AS `nombre_completo`, `p`.`Direccion` AS `Direccion`, `p`.`Telefono` AS `Telefono`, `p`.`Edad` AS `Edad`, `r`.`Nombre_rol` AS `rol` FROM ((`users` `u` join `persona` `p` on(`u`.`ID_Persona` = `p`.`ID`)) join `rol` `r` on(`u`.`ID_Rol` = `r`.`ID`)) ;

--
-- Índices para tablas volcadas
--

--
-- Indices de la tabla `cuenta`
--
ALTER TABLE `cuenta`
  ADD PRIMARY KEY (`ID`),
  ADD UNIQUE KEY `Numero_cuenta` (`Numero_cuenta`),
  ADD KEY `fk_cuenta_users` (`ID_Users`),
  ADD KEY `idx_cuenta_numero` (`Numero_cuenta`);

--
-- Indices de la tabla `persona`
--
ALTER TABLE `persona`
  ADD PRIMARY KEY (`ID`);

--
-- Indices de la tabla `rol`
--
ALTER TABLE `rol`
  ADD PRIMARY KEY (`ID`),
  ADD UNIQUE KEY `Nombre_rol` (`Nombre_rol`);

--
-- Indices de la tabla `sesion_atm`
--
ALTER TABLE `sesion_atm`
  ADD PRIMARY KEY (`ID`),
  ADD KEY `fk_sesion_tarjeta` (`ID_Tarjeta`),
  ADD KEY `fk_sesion_users` (`ID_Users`);

--
-- Indices de la tabla `tarjeta`
--
ALTER TABLE `tarjeta`
  ADD PRIMARY KEY (`ID`),
  ADD UNIQUE KEY `Numero_tarjeta` (`Numero_tarjeta`),
  ADD KEY `fk_tarjeta_users` (`ID_Users`),
  ADD KEY `fk_tarjeta_cuenta` (`ID_Cuenta`),
  ADD KEY `idx_tarjeta_numero` (`Numero_tarjeta`);

--
-- Indices de la tabla `tipo_transaccion`
--
ALTER TABLE `tipo_transaccion`
  ADD PRIMARY KEY (`ID`),
  ADD UNIQUE KEY `Nombre` (`Nombre`);

--
-- Indices de la tabla `transacciones`
--
ALTER TABLE `transacciones`
  ADD PRIMARY KEY (`ID`),
  ADD KEY `fk_trans_cuenta_origen` (`ID_Cuenta_Transfiere`),
  ADD KEY `fk_trans_cuenta_destino` (`ID_Cuenta_Transferida`),
  ADD KEY `fk_trans_tipo` (`ID_Tipo_Transaccion`),
  ADD KEY `idx_transacciones_fecha` (`Fecha_transaccion`);

--
-- Indices de la tabla `users`
--
ALTER TABLE `users`
  ADD PRIMARY KEY (`ID`),
  ADD UNIQUE KEY `Correo` (`Correo`),
  ADD KEY `fk_users_persona` (`ID_Persona`),
  ADD KEY `fk_users_rol` (`ID_Rol`),
  ADD KEY `idx_users_correo` (`Correo`);

--
-- AUTO_INCREMENT de las tablas volcadas
--

--
-- AUTO_INCREMENT de la tabla `cuenta`
--
ALTER TABLE `cuenta`
  MODIFY `ID` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=5;

--
-- AUTO_INCREMENT de la tabla `persona`
--
ALTER TABLE `persona`
  MODIFY `ID` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=7;

--
-- AUTO_INCREMENT de la tabla `rol`
--
ALTER TABLE `rol`
  MODIFY `ID` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=4;

--
-- AUTO_INCREMENT de la tabla `sesion_atm`
--
ALTER TABLE `sesion_atm`
  MODIFY `ID` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT de la tabla `tarjeta`
--
ALTER TABLE `tarjeta`
  MODIFY `ID` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=5;

--
-- AUTO_INCREMENT de la tabla `tipo_transaccion`
--
ALTER TABLE `tipo_transaccion`
  MODIFY `ID` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=6;

--
-- AUTO_INCREMENT de la tabla `transacciones`
--
ALTER TABLE `transacciones`
  MODIFY `ID` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=8;

--
-- AUTO_INCREMENT de la tabla `users`
--
ALTER TABLE `users`
  MODIFY `ID` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=7;

--
-- Restricciones para tablas volcadas
--

--
-- Filtros para la tabla `cuenta`
--
ALTER TABLE `cuenta`
  ADD CONSTRAINT `fk_cuenta_users` FOREIGN KEY (`ID_Users`) REFERENCES `users` (`ID`);

--
-- Filtros para la tabla `sesion_atm`
--
ALTER TABLE `sesion_atm`
  ADD CONSTRAINT `fk_sesion_tarjeta` FOREIGN KEY (`ID_Tarjeta`) REFERENCES `tarjeta` (`ID`),
  ADD CONSTRAINT `fk_sesion_users` FOREIGN KEY (`ID_Users`) REFERENCES `users` (`ID`);

--
-- Filtros para la tabla `tarjeta`
--
ALTER TABLE `tarjeta`
  ADD CONSTRAINT `fk_tarjeta_cuenta` FOREIGN KEY (`ID_Cuenta`) REFERENCES `cuenta` (`ID`),
  ADD CONSTRAINT `fk_tarjeta_users` FOREIGN KEY (`ID_Users`) REFERENCES `users` (`ID`);

--
-- Filtros para la tabla `transacciones`
--
ALTER TABLE `transacciones`
  ADD CONSTRAINT `fk_trans_cuenta_destino` FOREIGN KEY (`ID_Cuenta_Transferida`) REFERENCES `cuenta` (`ID`),
  ADD CONSTRAINT `fk_trans_cuenta_origen` FOREIGN KEY (`ID_Cuenta_Transfiere`) REFERENCES `cuenta` (`ID`),
  ADD CONSTRAINT `fk_trans_tipo` FOREIGN KEY (`ID_Tipo_Transaccion`) REFERENCES `tipo_transaccion` (`ID`);

--
-- Filtros para la tabla `users`
--
ALTER TABLE `users`
  ADD CONSTRAINT `fk_users_persona` FOREIGN KEY (`ID_Persona`) REFERENCES `persona` (`ID`),
  ADD CONSTRAINT `fk_users_rol` FOREIGN KEY (`ID_Rol`) REFERENCES `rol` (`ID`);
COMMIT;

/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;
