-- phpMyAdmin SQL Dump
-- version 5.2.1
-- https://www.phpmyadmin.net/
--
-- Servidor: 127.0.0.1
-- Tiempo de generación: 24-04-2026 a las 03:06:08
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
CREATE DEFINER=`root`@`localhost` PROCEDURE `sp_buscar_usuario_login` (IN `p_correo` VARCHAR(150) COLLATE utf8mb4_unicode_ci)   BEGIN
    SELECT
        u.Contrasena        AS contrasena_hash,
        r.Nombre_rol,
        u.Estado            AS estado_usuario,
        CONCAT(p.Nombre, ' ', p.Apellido) AS nombre_completo
    FROM Users u
    INNER JOIN Persona  p ON u.ID_Persona = p.ID
    INNER JOIN Rol      r ON u.ID_Rol     = r.ID
    WHERE u.Correo  = p_correo
      AND u.Estado  = 'activo'
    LIMIT 1;
END$$

CREATE DEFINER=`root`@`localhost` PROCEDURE `sp_cambiar_cuenta_principal` (IN `p_numero_tarjeta` VARCHAR(16) COLLATE utf8mb4_unicode_ci, IN `p_numero_cuenta` VARCHAR(20) COLLATE utf8mb4_unicode_ci, OUT `p_mensaje` VARCHAR(255))   BEGIN
    DECLARE v_tarjeta_id INT;
    DECLARE v_cuenta_id  INT;
    DECLARE v_vinculo_id INT;

    SELECT ID INTO v_tarjeta_id FROM Tarjeta WHERE Numero_tarjeta = p_numero_tarjeta LIMIT 1;
    SELECT ID INTO v_cuenta_id  FROM Cuenta  WHERE Numero_cuenta  = p_numero_cuenta  LIMIT 1;

    SELECT ID INTO v_vinculo_id
    FROM   tarjeta_cuenta
    WHERE  ID_Tarjeta = v_tarjeta_id AND ID_Cuenta = v_cuenta_id LIMIT 1;

    IF v_tarjeta_id IS NULL THEN
        SET p_mensaje = 'Error: Tarjeta no encontrada.';
    ELSEIF v_cuenta_id IS NULL THEN
        SET p_mensaje = 'Error: Cuenta no encontrada.';
    ELSEIF v_vinculo_id IS NULL THEN
        SET p_mensaje = 'Error: La cuenta no esta vinculada a esta tarjeta.';
    ELSE
        UPDATE tarjeta_cuenta SET Es_principal = 0 WHERE ID_Tarjeta = v_tarjeta_id;
        UPDATE tarjeta_cuenta SET Es_principal = 1 WHERE ID = v_vinculo_id;
        SET p_mensaje = CONCAT('Cuenta ', p_numero_cuenta, ' ahora es la cuenta principal.');
    END IF;
END$$

CREATE DEFINER=`root`@`localhost` PROCEDURE `sp_cambiar_estado_tarjeta` (IN `p_pin` VARCHAR(255) COLLATE utf8mb4_unicode_ci, IN `p_nombre_completo` VARCHAR(201) COLLATE utf8mb4_unicode_ci, IN `p_nuevo_estado` ENUM('activa','bloqueada','cancelada'), OUT `p_mensaje` VARCHAR(255))   BEGIN
    DECLARE v_tarjeta_id INT;
    DECLARE v_usuario_id INT;

    SELECT vuc.usuario_id
    INTO   v_usuario_id
    FROM   vista_usuarios_completo vuc
    WHERE  vuc.nombre_completo = p_nombre_completo
    LIMIT 1;

    SELECT tar.ID
    INTO   v_tarjeta_id
    FROM   Tarjeta          tar
    INNER JOIN tarjeta_cuenta tc ON tc.ID_Tarjeta = tar.ID
    INNER JOIN Cuenta         c  ON c.ID          = tc.ID_Cuenta
    WHERE  tar.Pin    = p_pin
      AND  c.ID_Users = v_usuario_id
    LIMIT 1;

    IF v_usuario_id IS NULL THEN
        SET p_mensaje = 'Error: Usuario no encontrado.';
    ELSEIF v_tarjeta_id IS NULL THEN
        SET p_mensaje = 'Error: Tarjeta no encontrada o no pertenece al usuario.';
    ELSE
        UPDATE Tarjeta SET Estado = p_nuevo_estado WHERE ID = v_tarjeta_id;
        SET p_mensaje = CONCAT('Tarjeta actualizada a estado: ', p_nuevo_estado);
    END IF;
END$$

CREATE DEFINER=`root`@`localhost` PROCEDURE `sp_cuentas_por_tarjeta` (IN `p_numero_tarjeta` VARCHAR(16) COLLATE utf8mb4_unicode_ci)   BEGIN
    SELECT
        tc.Orden,
        tc.Es_principal,
        c.Numero_cuenta,
        c.Tipo_cuenta,
        c.Estado            AS estado_cuenta,
        IFNULL(sm.Saldo, 0) AS saldo_bob,
        tc.Fecha_vinculacion
    FROM   tarjeta_cuenta tc
    INNER JOIN Tarjeta tar ON tar.ID        = tc.ID_Tarjeta
    INNER JOIN Cuenta  c   ON c.ID          = tc.ID_Cuenta
    LEFT JOIN moneda  m   ON m.Codigo      = 'BOB'
    LEFT JOIN saldo_moneda sm ON sm.ID_Cuenta = c.ID AND sm.ID_Moneda = m.ID
    WHERE  tar.Numero_tarjeta = p_numero_tarjeta
    ORDER BY tc.Orden ASC;
END$$

CREATE DEFINER=`root`@`localhost` PROCEDURE `sp_cuentas_usuario` (IN `p_nombre_completo` VARCHAR(201) COLLATE utf8mb4_unicode_ci)   BEGIN
    SELECT 
        cr.Numero_cuenta,
        cr.Tipo_cuenta,
        cr.estado_cuenta,
        cr.saldo_bob,
        cr.Es_principal,
        cr.orden_cuenta,
        cr.Numero_tarjeta,
        cr.Tipo_tarjeta,
        cr.estado_tarjeta,
        cr.Fecha_vencimiento,
        cr.fecha_apertura
    FROM vista_cuentas_resumen cr
    WHERE cr.nombre_titular = p_nombre_completo
    ORDER BY cr.orden_cuenta ASC;
END$$

CREATE DEFINER=`root`@`localhost` PROCEDURE `sp_datos_usuario_por_nombre` (IN `p_nombre_completo` VARCHAR(201) COLLATE utf8mb4_unicode_ci)   BEGIN
    -- Datos del usuario con cuenta, tarjeta y Pin (hash bcrypt)
    SELECT
        vuc.usuario_id,
        vuc.Correo,
        vuc.Nombre,
        vuc.Apellido,
        vuc.nombre_completo,
        vuc.Direccion,
        vuc.Telefono,
        vuc.Edad,
        vcr.Numero_cuenta,
        vcr.saldo_bob          AS Saldo,
        vcr.estado_cuenta,
        vcr.Numero_tarjeta,
        tar.Pin,
        vcr.Tipo_tarjeta,
        vcr.Fecha_vencimiento
    FROM vista_usuarios_completo vuc
    INNER JOIN vista_cuentas_resumen vcr ON vcr.usuario_id = vuc.usuario_id
    INNER JOIN Tarjeta tar ON tar.Numero_tarjeta = vcr.Numero_tarjeta
    WHERE vuc.nombre_completo = p_nombre_completo
    LIMIT 1;

    -- Transacciones
    SELECT
        vtc.transaccion_id,
        vtc.tipo_transaccion,
        vtc.Monto,
        vtc.Saldo_anterior,
        vtc.Saldo_posterior,
        vtc.cuenta_origen,
        vtc.cuenta_destino,
        vtc.nombre_destinatario,
        vtc.correo_destinatario,
        vtc.Metodo_transaccion,
        vtc.estado_transaccion,
        vtc.Descripcion,
        vtc.Fecha_transaccion
    FROM vista_transacciones_completo vtc
    INNER JOIN vista_usuarios_completo vuc ON vtc.usuario_id = vuc.usuario_id
    WHERE vuc.nombre_completo = p_nombre_completo
    ORDER BY vtc.Fecha_transaccion DESC;
END$$

CREATE DEFINER=`root`@`localhost` PROCEDURE `sp_desvincular_cuenta_tarjeta` (IN `p_numero_tarjeta` VARCHAR(16) COLLATE utf8mb4_unicode_ci, IN `p_numero_cuenta` VARCHAR(20) COLLATE utf8mb4_unicode_ci, OUT `p_mensaje` VARCHAR(255))   BEGIN
    DECLARE v_tarjeta_id   INT;
    DECLARE v_cuenta_id    INT;
    DECLARE v_es_principal TINYINT(1);
    DECLARE v_count        INT;

    SELECT ID INTO v_tarjeta_id FROM Tarjeta WHERE Numero_tarjeta = p_numero_tarjeta LIMIT 1;
    SELECT ID INTO v_cuenta_id  FROM Cuenta  WHERE Numero_cuenta  = p_numero_cuenta  LIMIT 1;

    IF v_tarjeta_id IS NULL OR v_cuenta_id IS NULL THEN
        SET p_mensaje = 'Error: Tarjeta o cuenta no encontrada.';
    ELSE
        SELECT Es_principal INTO v_es_principal
        FROM   tarjeta_cuenta
        WHERE  ID_Tarjeta = v_tarjeta_id AND ID_Cuenta = v_cuenta_id LIMIT 1;

        SELECT COUNT(*) INTO v_count
        FROM   tarjeta_cuenta WHERE ID_Tarjeta = v_tarjeta_id;

        IF v_es_principal IS NULL THEN
            SET p_mensaje = 'Error: La cuenta no esta vinculada a esta tarjeta.';
        ELSEIF v_es_principal = 1 AND v_count = 1 THEN
            SET p_mensaje = 'Error: No puedes desvincular la unica cuenta de la tarjeta.';
        ELSE
            DELETE FROM tarjeta_cuenta
            WHERE  ID_Tarjeta = v_tarjeta_id AND ID_Cuenta = v_cuenta_id;

            -- Si era la principal, promover la siguiente
            IF v_es_principal = 1 THEN
                UPDATE tarjeta_cuenta
                SET    Es_principal = 1
                WHERE  ID_Tarjeta   = v_tarjeta_id
                ORDER BY Orden ASC
                LIMIT 1;
            END IF;

            SET p_mensaje = 'Cuenta desvinculada exitosamente.';
        END IF;
    END IF;
END$$

CREATE DEFINER=`root`@`localhost` PROCEDURE `sp_estado_cuenta` (IN `p_nombre_completo` VARCHAR(201) COLLATE utf8mb4_unicode_ci)   BEGIN

    -- Resultado 1: Datos básicos del usuario
    SELECT 
        vuc.usuario_id,
        vuc.Correo,
        vuc.estado_usuario,
        vuc.fecha_registro,
        vuc.Nombre,
        vuc.Apellido,
        vuc.nombre_completo,
        vuc.Direccion,
        vuc.Telefono,
        vuc.Edad,
        vuc.rol
    FROM vista_usuarios_completo vuc
    WHERE vuc.nombre_completo = p_nombre_completo
    LIMIT 1;

    -- Resultado 2: Todas las cuentas del usuario
    SELECT 
        cr.Numero_cuenta,
        cr.Tipo_cuenta,
        cr.estado_cuenta,
        cr.saldo_bob,
        cr.Es_principal,
        cr.orden_cuenta,
        cr.Numero_tarjeta,
        cr.Tipo_tarjeta,
        cr.estado_tarjeta,
        cr.Fecha_vencimiento,
        cr.fecha_apertura
    FROM vista_cuentas_resumen cr
    WHERE cr.nombre_titular = p_nombre_completo
    ORDER BY cr.orden_cuenta ASC;

    -- Resultado 3: Últimas 20 transacciones (puedes cambiar el LIMIT si quieres más/menos)
    SELECT 
        vtc.transaccion_id,
        vtc.tipo_transaccion,
        vtc.Monto,
        vtc.Saldo_anterior,
        vtc.Saldo_posterior,
        vtc.cuenta_origen,
        vtc.cuenta_destino,
        vtc.nombre_destinatario,
        vtc.correo_destinatario,
        vtc.Metodo_transaccion,
        vtc.estado_transaccion,
        vtc.Descripcion,
        vtc.Fecha_transaccion
    FROM vista_transacciones_completo vtc
    INNER JOIN vista_usuarios_completo vuc 
        ON vtc.usuario_id = vuc.usuario_id
    WHERE vuc.nombre_completo = p_nombre_completo
    ORDER BY vtc.Fecha_transaccion DESC
    LIMIT 20;

END$$

CREATE DEFINER=`root`@`localhost` PROCEDURE `sp_realizar_deposito` (IN `p_correo` VARCHAR(150) COLLATE utf8mb4_unicode_ci, IN `p_monto` DECIMAL(20,6), IN `p_id_moneda` INT, IN `p_metodo` ENUM('ATM','web','app_movil'), IN `p_contrasena` VARCHAR(255), IN `p_pin` VARCHAR(255), IN `p_tasa` DECIMAL(20,8), IN `p_tipo_tasa` ENUM('oficial','binance','manual'), OUT `p_transaccion_id` INT, OUT `p_mensaje` VARCHAR(255))   BEGIN
    DECLARE v_cuenta_id      INT;
    DECLARE v_saldo_bob      DECIMAL(20,6) DEFAULT 0;
    DECLARE v_estado_cuenta  VARCHAR(20);
    DECLARE v_usuario_id     INT;
    DECLARE v_contrasena_bd  VARCHAR(255);
    DECLARE v_estado_usuario VARCHAR(20);
    DECLARE v_pin_bd         VARCHAR(255);
    DECLARE v_tipo_deposito  INT;
    DECLARE v_monto_bob      DECIMAL(20,6);
    DECLARE v_saldo_mon_id   INT;
    DECLARE v_saldo_bob_id   INT;
    DECLARE v_id_bob         INT;
    DECLARE v_codigo_moneda  VARCHAR(10);
    -- Saldo actual en la moneda del depósito (antes de operar)
    DECLARE v_saldo_moneda_actual DECIMAL(20,6) DEFAULT 0;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SET p_transaccion_id = -1;
        SET p_mensaje = 'Error interno: Deposito cancelado.';
    END;

    SELECT ID     INTO v_id_bob        FROM moneda WHERE Codigo = 'BOB' LIMIT 1;
    SELECT Codigo INTO v_codigo_moneda FROM moneda WHERE ID = p_id_moneda LIMIT 1;

    SELECT u.ID, u.Contrasena, u.Estado
    INTO   v_usuario_id, v_contrasena_bd, v_estado_usuario
    FROM   Users u WHERE u.Correo = p_correo LIMIT 1;

    IF v_usuario_id IS NULL THEN
        SET p_transaccion_id = -1; SET p_mensaje = 'Error: Usuario no encontrado.';
    ELSEIF v_estado_usuario != 'activo' THEN
        SET p_transaccion_id = -1; SET p_mensaje = 'Error: El usuario no esta activo.';
    ELSEIF v_contrasena_bd != p_contrasena THEN
        SET p_transaccion_id = -1; SET p_mensaje = 'Error: Contrasena incorrecta.';
    ELSE
        SELECT c.ID, c.Estado INTO v_cuenta_id, v_estado_cuenta
        FROM   Cuenta c
        WHERE  c.ID_Users = v_usuario_id AND c.Estado = 'activa' LIMIT 1;

        SELECT ID, Saldo INTO v_saldo_bob_id, v_saldo_bob
        FROM   saldo_moneda
        WHERE  ID_Cuenta = v_cuenta_id AND ID_Moneda = v_id_bob LIMIT 1;

        SELECT tar.Pin INTO v_pin_bd
        FROM   Tarjeta tar
        INNER JOIN tarjeta_cuenta tc ON tc.ID_Tarjeta = tar.ID
        WHERE  tc.ID_Cuenta = v_cuenta_id AND tar.Estado = 'activa' LIMIT 1;

        SELECT ID INTO v_tipo_deposito FROM Tipo_Transaccion WHERE Nombre = 'Deposito';

        IF p_id_moneda = v_id_bob THEN
            SET v_monto_bob = p_monto;
        ELSE
            SET v_monto_bob = p_monto * p_tasa;
        END IF;

        -- Saldo actual en la moneda real del depósito
        SELECT IFNULL(Saldo, 0) INTO v_saldo_moneda_actual
        FROM   saldo_moneda
        WHERE  ID_Cuenta = v_cuenta_id AND ID_Moneda = p_id_moneda LIMIT 1;

        IF v_cuenta_id IS NULL THEN
            SET p_transaccion_id = -1; SET p_mensaje = 'Error: No se encontro una cuenta activa.';
        ELSEIF v_pin_bd IS NULL THEN
            SET p_transaccion_id = -1; SET p_mensaje = 'Error: No se encontro una tarjeta activa.';
        ELSEIF v_pin_bd != p_pin THEN
            SET p_transaccion_id = -1; SET p_mensaje = 'Error: PIN incorrecto.';
        ELSEIF p_monto <= 0 THEN
            SET p_transaccion_id = -1; SET p_mensaje = 'Error: El monto debe ser mayor a 0.';
        ELSE
            START TRANSACTION;

            SELECT ID INTO v_saldo_mon_id
            FROM   saldo_moneda
            WHERE  ID_Cuenta = v_cuenta_id AND ID_Moneda = p_id_moneda LIMIT 1;

            IF v_saldo_mon_id IS NULL THEN
                INSERT INTO saldo_moneda (ID_Cuenta, ID_Moneda, Saldo)
                VALUES (v_cuenta_id, p_id_moneda, p_monto);
            ELSE
                UPDATE saldo_moneda SET Saldo = Saldo + p_monto WHERE ID = v_saldo_mon_id;
            END IF;

            IF p_id_moneda != v_id_bob THEN
                IF v_saldo_bob_id IS NULL THEN
                    INSERT INTO saldo_moneda (ID_Cuenta, ID_Moneda, Saldo)
                    VALUES (v_cuenta_id, v_id_bob, v_monto_bob);
                ELSE
                    UPDATE saldo_moneda SET Saldo = Saldo + v_monto_bob WHERE ID = v_saldo_bob_id;
                END IF;
            END IF;

            INSERT INTO Transacciones (
                ID_Cuenta_Transfiere, ID_Tipo_Transaccion,
                Monto,
                Monto_original,  Moneda_origen,
                Saldo_anterior,  Saldo_posterior,
                Saldo_anterior_original,  Saldo_posterior_original,
                Metodo_transaccion, Estado, Descripcion
            ) VALUES (
                v_cuenta_id, v_tipo_deposito,
                v_monto_bob,
                p_monto,         v_codigo_moneda,
                IFNULL(v_saldo_bob, 0),
                IFNULL(v_saldo_bob, 0) + v_monto_bob,
                -- Saldo en la moneda real antes y después
                v_saldo_moneda_actual,
                v_saldo_moneda_actual + p_monto,
                p_metodo, 'exitosa',
                CONCAT('Deposito en ', v_codigo_moneda, ' | Tasa ', p_tipo_tasa, ': ', p_tasa)
            );

            SET p_transaccion_id = LAST_INSERT_ID();
            COMMIT;
            SET p_mensaje = CONCAT(
                'Deposito exitoso. Monto: ', p_monto, ' ', v_codigo_moneda,
                ' | Equivalente BOB: ', ROUND(v_monto_bob, 2),
                ' | Nuevo saldo BOB: ', ROUND(IFNULL(v_saldo_bob, 0) + v_monto_bob, 2)
            );
        END IF;
    END IF;
END$$

CREATE DEFINER=`root`@`localhost` PROCEDURE `sp_realizar_deposito_multimoneda` (IN `p_correo` VARCHAR(150) COLLATE utf8mb4_unicode_ci, IN `p_monto_origen` DECIMAL(20,6), IN `p_id_moneda_origen` INT, IN `p_monto_destino` DECIMAL(20,6), IN `p_id_moneda_destino` INT, IN `p_metodo` ENUM('ATM','web','app_movil'), IN `p_contrasena` VARCHAR(255), IN `p_pin` VARCHAR(255), IN `p_tasa` DECIMAL(20,8), IN `p_tipo_tasa` ENUM('oficial','binance','manual'), OUT `p_transaccion_id` INT, OUT `p_mensaje` VARCHAR(255))   BEGIN
    DECLARE v_cuenta_id          INT;
    DECLARE v_saldo_bob          DECIMAL(20,6) DEFAULT 0;
    DECLARE v_usuario_id         INT;
    DECLARE v_contrasena_bd      VARCHAR(255);
    DECLARE v_estado_usuario     VARCHAR(20);
    DECLARE v_pin_bd             VARCHAR(255);
    DECLARE v_tipo_deposito      INT;
    DECLARE v_monto_bob          DECIMAL(20,6);
    DECLARE v_saldo_dest_id      INT;
    DECLARE v_saldo_bob_id       INT;
    DECLARE v_saldo_dest_actual  DECIMAL(20,6) DEFAULT 0;
    DECLARE v_codigo_origen      VARCHAR(10);
    DECLARE v_codigo_destino     VARCHAR(10);
    DECLARE v_id_bob             INT;
    DECLARE v_hay_conversion     TINYINT(1) DEFAULT 0;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SET p_transaccion_id = -1;
        SET p_mensaje = 'Error interno: Deposito cancelado.';
    END;

    SELECT ID     INTO v_id_bob         FROM moneda WHERE Codigo = 'BOB' LIMIT 1;
    SELECT Codigo INTO v_codigo_origen  FROM moneda WHERE ID = p_id_moneda_origen  LIMIT 1;
    SELECT Codigo INTO v_codigo_destino FROM moneda WHERE ID = p_id_moneda_destino LIMIT 1;

    SET v_hay_conversion = IF(p_id_moneda_origen != p_id_moneda_destino, 1, 0);

    SELECT u.ID, u.Contrasena, u.Estado
    INTO   v_usuario_id, v_contrasena_bd, v_estado_usuario
    FROM   Users u WHERE u.Correo = p_correo LIMIT 1;

    IF v_usuario_id IS NULL THEN
        SET p_transaccion_id = -1; SET p_mensaje = 'Error: Usuario no encontrado.';
    ELSEIF v_estado_usuario != 'activo' THEN
        SET p_transaccion_id = -1; SET p_mensaje = 'Error: El usuario no esta activo.';
    ELSEIF v_contrasena_bd != p_contrasena THEN
        SET p_transaccion_id = -1; SET p_mensaje = 'Error: Contrasena incorrecta.';
    ELSE
        SELECT c.ID INTO v_cuenta_id
        FROM   Cuenta c WHERE c.ID_Users = v_usuario_id AND c.Estado = 'activa' LIMIT 1;

        SELECT ID, Saldo INTO v_saldo_bob_id, v_saldo_bob
        FROM   saldo_moneda
        WHERE  ID_Cuenta = v_cuenta_id AND ID_Moneda = v_id_bob LIMIT 1;

        SELECT tar.Pin INTO v_pin_bd
        FROM   Tarjeta tar
        INNER JOIN tarjeta_cuenta tc ON tc.ID_Tarjeta = tar.ID
        WHERE  tc.ID_Cuenta = v_cuenta_id AND tar.Estado = 'activa' LIMIT 1;

        SELECT ID INTO v_tipo_deposito FROM Tipo_Transaccion WHERE Nombre = 'Deposito';

        IF p_id_moneda_origen = v_id_bob THEN
            SET v_monto_bob = p_monto_origen;
        ELSE
            SET v_monto_bob = p_monto_origen * p_tasa;
        END IF;

        -- Saldo actual en la moneda destino (antes de operar)
        SELECT ID, Saldo INTO v_saldo_dest_id, v_saldo_dest_actual
        FROM   saldo_moneda
        WHERE  ID_Cuenta = v_cuenta_id AND ID_Moneda = p_id_moneda_destino LIMIT 1;

        IF v_cuenta_id IS NULL THEN
            SET p_transaccion_id = -1; SET p_mensaje = 'Error: No se encontro cuenta activa.';
        ELSEIF v_pin_bd IS NULL THEN
            SET p_transaccion_id = -1; SET p_mensaje = 'Error: No se encontro tarjeta activa.';
        ELSEIF v_pin_bd != p_pin THEN
            SET p_transaccion_id = -1; SET p_mensaje = 'Error: PIN incorrecto.';
        ELSEIF p_monto_origen <= 0 THEN
            SET p_transaccion_id = -1; SET p_mensaje = 'Error: El monto debe ser mayor a 0.';
        ELSE
            START TRANSACTION;

            IF v_saldo_dest_id IS NULL THEN
                INSERT INTO saldo_moneda (ID_Cuenta, ID_Moneda, Saldo)
                VALUES (v_cuenta_id, p_id_moneda_destino, p_monto_destino);
            ELSE
                UPDATE saldo_moneda SET Saldo = Saldo + p_monto_destino WHERE ID = v_saldo_dest_id;
            END IF;

            IF v_hay_conversion = 1 AND p_id_moneda_destino != v_id_bob THEN
                IF v_saldo_bob_id IS NULL THEN
                    INSERT INTO saldo_moneda (ID_Cuenta, ID_Moneda, Saldo)
                    VALUES (v_cuenta_id, v_id_bob, v_monto_bob);
                ELSE
                    UPDATE saldo_moneda SET Saldo = Saldo + v_monto_bob WHERE ID = v_saldo_bob_id;
                END IF;
            END IF;

            INSERT INTO Transacciones (
                ID_Cuenta_Transfiere, ID_Tipo_Transaccion,
                Monto,
                Monto_original,  Moneda_origen,
                Monto_destino,   Moneda_destino,
                Saldo_anterior,  Saldo_posterior,
                Saldo_anterior_original,          Saldo_posterior_original,
                Metodo_transaccion, Estado, Descripcion
            ) VALUES (
                v_cuenta_id, v_tipo_deposito,
                IF(v_hay_conversion = 1, v_monto_bob, p_monto_destino),
                p_monto_origen,  v_codigo_origen,
                p_monto_destino, v_codigo_destino,
                -- Saldo_anterior / Saldo_posterior en BOB (referencia)
                IFNULL(v_saldo_bob, 0),
                IFNULL(v_saldo_bob, 0) + IF(v_hay_conversion = 1, v_monto_bob, p_monto_destino),
                -- Saldo_anterior_original / Saldo_posterior_original en la moneda destino
                IFNULL(v_saldo_dest_actual, 0),
                IFNULL(v_saldo_dest_actual, 0) + p_monto_destino,
                p_metodo, 'exitosa',
                'Deposito'
            );

            SET p_transaccion_id = LAST_INSERT_ID();
            COMMIT;
            SET p_mensaje = IF(v_hay_conversion = 1,
                CONCAT('Deposito exitoso. ', p_monto_origen, ' ', v_codigo_origen,
                       ' -> acreditado: ', p_monto_destino, ' ', v_codigo_destino,
                       ' | Equiv. BOB sumado: ', ROUND(v_monto_bob, 2),
                       ' | Nuevo saldo BOB: ', ROUND(IFNULL(v_saldo_bob, 0) + v_monto_bob, 2)),
                CONCAT('Deposito exitoso. ', p_monto_destino, ' ', v_codigo_destino,
                       ' | Nuevo saldo ', v_codigo_destino, ': ',
                       ROUND(IFNULL(v_saldo_dest_actual, 0) + p_monto_destino, 6))
            );
        END IF;
    END IF;
END$$

CREATE DEFINER=`root`@`localhost` PROCEDURE `sp_realizar_retiro` (IN `p_pin` VARCHAR(255) COLLATE utf8mb4_unicode_ci, IN `p_monto` DECIMAL(20,6), IN `p_id_moneda` INT, IN `p_metodo` ENUM('ATM','web','app_movil'), IN `p_tasa` DECIMAL(20,8), IN `p_tipo_tasa` ENUM('oficial','binance','manual'), OUT `p_transaccion_id` INT, OUT `p_mensaje` VARCHAR(255))   BEGIN
    DECLARE v_cuenta_id         INT;
    DECLARE v_saldo_bob         DECIMAL(20,6) DEFAULT 0;
    DECLARE v_tipo_retiro       INT;
    DECLARE v_monto_bob         DECIMAL(20,6);
    DECLARE v_saldo_mon_id      INT;
    DECLARE v_saldo_moneda      DECIMAL(20,6) DEFAULT 0;
    DECLARE v_saldo_bob_id      INT;
    DECLARE v_codigo_moneda     VARCHAR(10);
    DECLARE v_id_bob            INT;
    DECLARE v_es_retiro_directo TINYINT(1) DEFAULT 1;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SET p_transaccion_id = -1;
        SET p_mensaje = 'Error interno: Retiro cancelado.';
    END;

    SELECT ID     INTO v_id_bob        FROM moneda WHERE Codigo = 'BOB' LIMIT 1;
    SELECT Codigo INTO v_codigo_moneda FROM moneda WHERE ID = p_id_moneda LIMIT 1;

    SELECT tc.ID_Cuenta INTO v_cuenta_id
    FROM   Tarjeta tar
    INNER JOIN tarjeta_cuenta tc ON tc.ID_Tarjeta = tar.ID
    INNER JOIN Cuenta         c  ON c.ID          = tc.ID_Cuenta
    WHERE  tar.Pin = p_pin AND tar.Estado = 'activa'
      AND  c.Estado = 'activa' AND tc.Es_principal = 1
    LIMIT 1;

    SELECT ID INTO v_tipo_retiro FROM Tipo_Transaccion WHERE Nombre = 'Retiro';

    SELECT ID, Saldo INTO v_saldo_mon_id, v_saldo_moneda
    FROM   saldo_moneda
    WHERE  ID_Cuenta = v_cuenta_id AND ID_Moneda = p_id_moneda LIMIT 1;

    SELECT ID, Saldo INTO v_saldo_bob_id, v_saldo_bob
    FROM   saldo_moneda
    WHERE  ID_Cuenta = v_cuenta_id AND ID_Moneda = v_id_bob LIMIT 1;

    IF p_id_moneda = v_id_bob THEN
        SET v_monto_bob = p_monto;
    ELSE
        SET v_monto_bob = p_monto * p_tasa;
    END IF;

    IF p_id_moneda != v_id_bob AND (v_saldo_mon_id IS NULL OR v_saldo_moneda < p_monto) THEN
        SET v_es_retiro_directo = 0;
    END IF;

    IF v_cuenta_id IS NULL THEN
        SET p_transaccion_id = -1;
        SET p_mensaje = 'Error: No se encontro cuenta activa para ese PIN.';
    ELSEIF p_monto <= 0 THEN
        SET p_transaccion_id = -1;
        SET p_mensaje = 'Error: El monto debe ser mayor a 0.';

    ELSEIF v_es_retiro_directo = 1 THEN
        IF v_saldo_mon_id IS NULL THEN
            SET p_transaccion_id = -1;
            SET p_mensaje = CONCAT('Error: No tiene saldo registrado en ', v_codigo_moneda, '.');
        ELSEIF v_saldo_moneda < p_monto THEN
            SET p_transaccion_id = -1;
            SET p_mensaje = CONCAT('Error: Saldo insuficiente en ', v_codigo_moneda,
                                   '. Disponible: ', v_saldo_moneda);
        ELSE
            START TRANSACTION;
            UPDATE saldo_moneda SET Saldo = Saldo - p_monto WHERE ID = v_saldo_mon_id;
            IF p_id_moneda != v_id_bob AND v_saldo_bob_id IS NOT NULL AND v_saldo_bob >= v_monto_bob THEN
                UPDATE saldo_moneda SET Saldo = Saldo - v_monto_bob WHERE ID = v_saldo_bob_id;
            END IF;

            INSERT INTO Transacciones (
                ID_Cuenta_Transfiere, ID_Tipo_Transaccion,
                Monto,
                Monto_original,  Moneda_origen,
                Saldo_anterior,  Saldo_posterior,
                -- Saldo antes/después en la moneda real del retiro
                Saldo_anterior_original,  Saldo_posterior_original,
                Metodo_transaccion, Estado, Descripcion
            ) VALUES (
                v_cuenta_id, v_tipo_retiro,
                v_monto_bob,
                p_monto,         v_codigo_moneda,
                IFNULL(v_saldo_bob, v_saldo_moneda),
                IFNULL(v_saldo_bob, v_saldo_moneda) - v_monto_bob,
                v_saldo_moneda,             -- antes en moneda real
                v_saldo_moneda - p_monto,   -- después en moneda real
                p_metodo, 'exitosa',
                'Retiro'
            );
            SET p_transaccion_id = LAST_INSERT_ID();
            COMMIT;
            SET p_mensaje = CONCAT(
                'Retiro exitoso. Monto: ', p_monto, ' ', v_codigo_moneda,
                ' | Equivalente BOB: ', ROUND(v_monto_bob, 2),
                ' | Saldo restante en ', v_codigo_moneda, ': ',
                ROUND(v_saldo_moneda - p_monto, 6)
            );
        END IF;

    ELSE
        IF v_saldo_bob_id IS NULL OR v_saldo_bob < v_monto_bob THEN
            SET p_transaccion_id = -1;
            SET p_mensaje = CONCAT('Error: Saldo BOB insuficiente. Necesita ',
                                   ROUND(v_monto_bob, 2), ' BOB. Disponible: ',
                                   IFNULL(v_saldo_bob, 0));
        ELSE
            START TRANSACTION;
            UPDATE saldo_moneda SET Saldo = Saldo - v_monto_bob WHERE ID = v_saldo_bob_id;

            INSERT INTO Transacciones (
                ID_Cuenta_Transfiere, ID_Tipo_Transaccion,
                Monto,
                Monto_original,  Moneda_origen,
                Saldo_anterior,  Saldo_posterior,
                Saldo_anterior_original,  Saldo_posterior_original,
                Metodo_transaccion, Estado, Descripcion
            ) VALUES (
                v_cuenta_id, v_tipo_retiro,
                v_monto_bob,
                p_monto,         v_codigo_moneda,
                v_saldo_bob, v_saldo_bob - v_monto_bob,
                -- En este caso se retiró desde BOB, saldo original = BOB
                v_saldo_bob, v_saldo_bob - v_monto_bob,
                p_metodo, 'exitosa',
                'Retiro'
            );
            SET p_transaccion_id = LAST_INSERT_ID();
            COMMIT;
            SET p_mensaje = CONCAT(
                'Retiro exitoso. ', p_monto, ' ', v_codigo_moneda,
                ' | BOB descontados: ', ROUND(v_monto_bob, 2),
                ' | Saldo BOB restante: ', ROUND(v_saldo_bob - v_monto_bob, 2)
            );
        END IF;
    END IF;
END$$

CREATE DEFINER=`root`@`localhost` PROCEDURE `sp_realizar_retiro_conversion` (IN `p_pin` VARCHAR(255) COLLATE utf8mb4_unicode_ci, IN `p_monto` DECIMAL(20,6), IN `p_id_moneda` INT, IN `p_metodo` ENUM('ATM','web','app_movil'), IN `p_tasa_bob` DECIMAL(20,8), IN `p_tipo_tasa` ENUM('oficial','binance','manual'), OUT `p_transaccion_id` INT, OUT `p_mensaje` VARCHAR(255))   BEGIN
    DECLARE v_cuenta_id     INT;
    DECLARE v_saldo_bob     DECIMAL(20,6) DEFAULT 0;
    DECLARE v_tipo_retiro   INT;
    DECLARE v_monto_bob     DECIMAL(20,6);
    DECLARE v_saldo_bob_id  INT;
    DECLARE v_codigo_moneda VARCHAR(10);
    DECLARE v_id_bob        INT;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SET p_transaccion_id = -1;
        SET p_mensaje = 'Error interno: Retiro con conversion cancelado.';
    END;

    SELECT ID     INTO v_id_bob         FROM moneda WHERE Codigo = 'BOB' LIMIT 1;
    SELECT Codigo INTO v_codigo_moneda  FROM moneda WHERE ID = p_id_moneda LIMIT 1;

    SET v_monto_bob = p_monto * p_tasa_bob;

    SELECT tc.ID_Cuenta INTO v_cuenta_id
    FROM   Tarjeta tar
    INNER JOIN tarjeta_cuenta tc ON tc.ID_Tarjeta = tar.ID
    INNER JOIN Cuenta         c  ON c.ID          = tc.ID_Cuenta
    WHERE  tar.Pin = p_pin AND tar.Estado = 'activa'
      AND  c.Estado = 'activa' AND tc.Es_principal = 1
    LIMIT 1;

    SELECT ID INTO v_tipo_retiro FROM Tipo_Transaccion WHERE Nombre = 'Retiro';

    SELECT ID, Saldo INTO v_saldo_bob_id, v_saldo_bob
    FROM   saldo_moneda
    WHERE  ID_Cuenta = v_cuenta_id AND ID_Moneda = v_id_bob LIMIT 1;

    IF v_cuenta_id IS NULL THEN
        SET p_transaccion_id = -1;
        SET p_mensaje = 'Error: No se encontro cuenta activa para ese PIN.';
    ELSEIF v_saldo_bob_id IS NULL OR v_saldo_bob < v_monto_bob THEN
        SET p_transaccion_id = -1;
        SET p_mensaje = CONCAT('Error: Saldo BOB insuficiente. Necesita ',
                               ROUND(v_monto_bob, 2), ' BOB. Disponible: ',
                               IFNULL(v_saldo_bob, 0));
    ELSEIF p_monto <= 0 THEN
        SET p_transaccion_id = -1;
        SET p_mensaje = 'Error: El monto debe ser mayor a 0.';
    ELSE
        START TRANSACTION;
        UPDATE saldo_moneda SET Saldo = Saldo - v_monto_bob WHERE ID = v_saldo_bob_id;

        INSERT INTO Transacciones (
            ID_Cuenta_Transfiere, ID_Tipo_Transaccion,
            Monto,
            Monto_original,  Moneda_origen,
            Saldo_anterior,  Saldo_posterior,
            -- Saldo en moneda solicitada: se convirtió desde BOB, no había saldo directo
            -- Se registra en BOB ya que ese fue el saldo real descontado
            Saldo_anterior_original,  Saldo_posterior_original,
            Metodo_transaccion, Estado, Descripcion
        ) VALUES (
            v_cuenta_id, v_tipo_retiro,
            v_monto_bob,
            p_monto,         v_codigo_moneda,
            v_saldo_bob, v_saldo_bob - v_monto_bob,
            -- Saldo BOB antes/después (fue la fuente real del dinero)
            v_saldo_bob, v_saldo_bob - v_monto_bob,
            p_metodo, 'exitosa',
            'Retiro'
        );
        SET p_transaccion_id = LAST_INSERT_ID();
        COMMIT;
        SET p_mensaje = CONCAT(
            'Retiro exitoso (conversion). ',
            p_monto, ' ', v_codigo_moneda,
            ' | BOB descontados: ', ROUND(v_monto_bob, 2),
            ' | Saldo BOB restante: ', ROUND(v_saldo_bob - v_monto_bob, 2)
        );
    END IF;
END$$

CREATE DEFINER=`root`@`localhost` PROCEDURE `sp_realizar_transferencia` (IN `p_numero_cuenta_origen` VARCHAR(20) COLLATE utf8mb4_unicode_ci, IN `p_numero_cuenta_destino` VARCHAR(20), IN `p_monto` DECIMAL(15,2), IN `p_metodo` ENUM('ATM','web','app_movil'), IN `p_descripcion` VARCHAR(255), OUT `p_transaccion_id` INT, OUT `p_mensaje` VARCHAR(255))   BEGIN
    DECLARE v_cuenta_origen_id     INT;
    DECLARE v_cuenta_destino_id    INT;
    DECLARE v_saldo_origen         DECIMAL(20,6) DEFAULT 0;
    DECLARE v_saldo_bob_origen_id  INT;
    DECLARE v_saldo_bob_destino_id INT;
    DECLARE v_estado_origen        VARCHAR(20);
    DECLARE v_estado_destino       VARCHAR(20);
    DECLARE v_tipo_transferencia   INT;
    DECLARE v_id_bob               INT;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SET p_transaccion_id = -1;
        SET p_mensaje = 'Error interno: Transferencia cancelada.';
    END;

    SELECT ID INTO v_id_bob FROM moneda WHERE Codigo = 'BOB' LIMIT 1;

    SELECT ID, Estado INTO v_cuenta_origen_id,  v_estado_origen
    FROM   Cuenta WHERE Numero_cuenta = p_numero_cuenta_origen  LIMIT 1;
    SELECT ID, Estado INTO v_cuenta_destino_id, v_estado_destino
    FROM   Cuenta WHERE Numero_cuenta = p_numero_cuenta_destino LIMIT 1;

    SELECT ID, Saldo INTO v_saldo_bob_origen_id, v_saldo_origen
    FROM   saldo_moneda
    WHERE  ID_Cuenta = v_cuenta_origen_id AND ID_Moneda = v_id_bob LIMIT 1;

    SELECT ID INTO v_saldo_bob_destino_id
    FROM   saldo_moneda
    WHERE  ID_Cuenta = v_cuenta_destino_id AND ID_Moneda = v_id_bob LIMIT 1;

    SELECT ID INTO v_tipo_transferencia FROM Tipo_Transaccion WHERE Nombre = 'Transferencia';

    IF v_cuenta_origen_id IS NULL THEN
        SET p_transaccion_id = -1; SET p_mensaje = 'Error: Cuenta origen no encontrada.';
    ELSEIF v_cuenta_destino_id IS NULL THEN
        SET p_transaccion_id = -1; SET p_mensaje = 'Error: Cuenta destino no encontrada.';
    ELSEIF v_cuenta_origen_id = v_cuenta_destino_id THEN
        SET p_transaccion_id = -1; SET p_mensaje = 'Error: La cuenta origen y destino no pueden ser la misma.';
    ELSEIF v_estado_origen != 'activa' THEN
        SET p_transaccion_id = -1; SET p_mensaje = 'Error: La cuenta origen no está activa.';
    ELSEIF v_estado_destino != 'activa' THEN
        SET p_transaccion_id = -1; SET p_mensaje = 'Error: La cuenta destino no está activa.';
    ELSEIF p_monto <= 0 THEN
        SET p_transaccion_id = -1; SET p_mensaje = 'Error: El monto debe ser mayor a 0.';
    ELSEIF v_saldo_bob_origen_id IS NULL OR v_saldo_origen < p_monto THEN
        SET p_transaccion_id = -1; SET p_mensaje = 'Error: Saldo insuficiente.';
    ELSE
        START TRANSACTION;

        UPDATE saldo_moneda SET Saldo = Saldo - p_monto WHERE ID = v_saldo_bob_origen_id;

        IF v_saldo_bob_destino_id IS NULL THEN
            INSERT INTO saldo_moneda (ID_Cuenta, ID_Moneda, Saldo)
            VALUES (v_cuenta_destino_id, v_id_bob, p_monto);
        ELSE
            UPDATE saldo_moneda SET Saldo = Saldo + p_monto WHERE ID = v_saldo_bob_destino_id;
        END IF;

        INSERT INTO Transacciones (
            ID_Cuenta_Transfiere, ID_Cuenta_Transferida, ID_Tipo_Transaccion,
            Monto,
            Monto_original, Moneda_origen,
            Monto_destino,  Moneda_destino,
            Saldo_anterior,  Saldo_posterior,
            -- BOB → BOB: saldo original coincide con BOB
            Saldo_anterior_original,  Saldo_posterior_original,
            Metodo_transaccion, Estado, Descripcion
        ) VALUES (
            v_cuenta_origen_id, v_cuenta_destino_id, v_tipo_transferencia,
            p_monto,
            p_monto, 'BOB',
            p_monto, 'BOB',
            v_saldo_origen, v_saldo_origen - p_monto,
            v_saldo_origen, v_saldo_origen - p_monto,
            p_metodo, 'exitosa', p_descripcion
        );

        SET p_transaccion_id = LAST_INSERT_ID();
        COMMIT;
        SET p_mensaje = CONCAT('Transferencia exitosa. Nuevo saldo: ', v_saldo_origen - p_monto);
    END IF;
END$$

CREATE DEFINER=`root`@`localhost` PROCEDURE `sp_realizar_transferencia_multimoneda` (IN `p_numero_cuenta_origen` VARCHAR(20) COLLATE utf8mb4_unicode_ci, IN `p_numero_cuenta_destino` VARCHAR(20) COLLATE utf8mb4_unicode_ci, IN `p_monto_origen` DECIMAL(20,6), IN `p_id_moneda_origen` INT, IN `p_monto_destino` DECIMAL(20,6), IN `p_id_moneda_destino` INT, IN `p_metodo` ENUM('ATM','web','app_movil'), IN `p_descripcion` VARCHAR(255) COLLATE utf8mb4_unicode_ci, IN `p_tasa_origen_bob` DECIMAL(20,8), IN `p_tasa_destino_bob` DECIMAL(20,8), IN `p_tipo_tasa` ENUM('oficial','binance','manual'), OUT `p_transaccion_id` INT, OUT `p_mensaje` VARCHAR(255) COLLATE utf8mb4_unicode_ci)   BEGIN
    DECLARE v_cuenta_origen_id     INT;
    DECLARE v_cuenta_destino_id    INT;
    DECLARE v_saldo_origen_bob     DECIMAL(20,6) DEFAULT 0;
    DECLARE v_estado_origen        VARCHAR(20) COLLATE utf8mb4_unicode_ci;
    DECLARE v_estado_destino       VARCHAR(20) COLLATE utf8mb4_unicode_ci;
    DECLARE v_saldo_mon_origen_id  INT;
    DECLARE v_saldo_mon_origen     DECIMAL(20,6) DEFAULT 0;
    DECLARE v_saldo_mon_destino_id INT;
    DECLARE v_saldo_bob_origen_id  INT;
    DECLARE v_saldo_bob_destino_id INT;
    DECLARE v_tipo_transferencia   INT;
    DECLARE v_monto_bob            DECIMAL(20,6);
    DECLARE v_monto_bob_destino    DECIMAL(20,6);
    DECLARE v_codigo_origen        VARCHAR(10) COLLATE utf8mb4_unicode_ci;
    DECLARE v_codigo_destino       VARCHAR(10) COLLATE utf8mb4_unicode_ci;
    DECLARE v_id_bob               INT;
    DECLARE v_hay_conversion       TINYINT(1) DEFAULT 0;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1
            @err_code = MYSQL_ERRNO,
            @err_msg  = MESSAGE_TEXT;
        ROLLBACK;
        SET p_transaccion_id = -1;
        SET p_mensaje = CONCAT('Error SQL #', @err_code, ': ', @err_msg);
    END;

    SELECT ID     INTO v_id_bob         FROM moneda WHERE Codigo = 'BOB' LIMIT 1;
    SELECT Codigo INTO v_codigo_origen  FROM moneda WHERE ID = p_id_moneda_origen  LIMIT 1;
    SELECT Codigo INTO v_codigo_destino FROM moneda WHERE ID = p_id_moneda_destino LIMIT 1;

    SET v_hay_conversion = IF(p_id_moneda_origen != p_id_moneda_destino, 1, 0);

    SELECT ID, Estado INTO v_cuenta_origen_id,  v_estado_origen
    FROM   Cuenta WHERE Numero_cuenta = p_numero_cuenta_origen  LIMIT 1;
    SELECT ID, Estado INTO v_cuenta_destino_id, v_estado_destino
    FROM   Cuenta WHERE Numero_cuenta = p_numero_cuenta_destino LIMIT 1;

    SELECT ID INTO v_tipo_transferencia FROM Tipo_Transaccion WHERE Nombre = 'Transferencia';

    SELECT ID, Saldo INTO v_saldo_mon_origen_id, v_saldo_mon_origen
    FROM   saldo_moneda
    WHERE  ID_Cuenta = v_cuenta_origen_id AND ID_Moneda = p_id_moneda_origen LIMIT 1;

    SELECT ID, Saldo INTO v_saldo_bob_origen_id, v_saldo_origen_bob
    FROM   saldo_moneda
    WHERE  ID_Cuenta = v_cuenta_origen_id AND ID_Moneda = v_id_bob LIMIT 1;

    SELECT ID INTO v_saldo_mon_destino_id
    FROM   saldo_moneda
    WHERE  ID_Cuenta = v_cuenta_destino_id AND ID_Moneda = p_id_moneda_destino LIMIT 1;

    SELECT ID INTO v_saldo_bob_destino_id
    FROM   saldo_moneda
    WHERE  ID_Cuenta = v_cuenta_destino_id AND ID_Moneda = v_id_bob LIMIT 1;

    IF p_id_moneda_origen = v_id_bob THEN
        SET v_monto_bob = p_monto_origen;
    ELSE
        SET v_monto_bob = p_monto_origen * p_tasa_origen_bob;
    END IF;

    IF p_id_moneda_destino = v_id_bob THEN
        SET v_monto_bob_destino = p_monto_destino;
    ELSE
        SET v_monto_bob_destino = p_monto_destino * p_tasa_destino_bob;
    END IF;

    IF v_cuenta_origen_id IS NULL THEN
        SET p_transaccion_id = -1; SET p_mensaje = 'Error: Cuenta origen no encontrada.';
    ELSEIF v_cuenta_destino_id IS NULL THEN
        SET p_transaccion_id = -1; SET p_mensaje = 'Error: Cuenta destino no encontrada.';
    ELSEIF v_cuenta_origen_id = v_cuenta_destino_id THEN
        SET p_transaccion_id = -1; SET p_mensaje = 'Error: Origen y destino no pueden ser la misma cuenta.';
    ELSEIF v_estado_origen != 'activa' THEN
        SET p_transaccion_id = -1; SET p_mensaje = 'Error: La cuenta origen no está activa.';
    ELSEIF v_estado_destino != 'activa' THEN
        SET p_transaccion_id = -1; SET p_mensaje = 'Error: La cuenta destino no está activa.';
    ELSEIF p_monto_origen <= 0 THEN
        SET p_transaccion_id = -1; SET p_mensaje = 'Error: El monto debe ser mayor a 0.';
    ELSEIF v_saldo_mon_origen_id IS NULL OR v_saldo_mon_origen < p_monto_origen THEN
        SET p_transaccion_id = -1;
        SET p_mensaje = CONCAT('Error: Saldo insuficiente en ', v_codigo_origen,
                               '. Disponible: ', IFNULL(v_saldo_mon_origen, 0));
    ELSEIF v_hay_conversion = 1
        AND p_id_moneda_origen != v_id_bob
        AND (v_saldo_bob_origen_id IS NULL OR v_saldo_origen_bob < v_monto_bob) THEN
        SET p_transaccion_id = -1;
        SET p_mensaje = 'Error: Saldo BOB insuficiente en la cuenta origen.';
    ELSE
        START TRANSACTION;

        UPDATE saldo_moneda SET Saldo = Saldo - p_monto_origen WHERE ID = v_saldo_mon_origen_id;

        IF v_hay_conversion = 1 AND p_id_moneda_origen != v_id_bob THEN
            UPDATE saldo_moneda SET Saldo = Saldo - v_monto_bob WHERE ID = v_saldo_bob_origen_id;
        END IF;

        IF v_saldo_mon_destino_id IS NULL THEN
            INSERT INTO saldo_moneda (ID_Cuenta, ID_Moneda, Saldo)
            VALUES (v_cuenta_destino_id, p_id_moneda_destino, p_monto_destino);
        ELSE
            UPDATE saldo_moneda SET Saldo = Saldo + p_monto_destino WHERE ID = v_saldo_mon_destino_id;
        END IF;

        IF v_hay_conversion = 1 AND p_id_moneda_destino != v_id_bob THEN
            IF v_saldo_bob_destino_id IS NULL THEN
                INSERT INTO saldo_moneda (ID_Cuenta, ID_Moneda, Saldo)
                VALUES (v_cuenta_destino_id, v_id_bob, v_monto_bob_destino);
            ELSE
                UPDATE saldo_moneda SET Saldo = Saldo + v_monto_bob_destino WHERE ID = v_saldo_bob_destino_id;
            END IF;
        END IF;

        INSERT INTO Transacciones (
            ID_Cuenta_Transfiere, ID_Cuenta_Transferida, ID_Tipo_Transaccion,
            Monto,
            Monto_original,  Moneda_origen,
            Monto_destino,   Moneda_destino,
            Saldo_anterior,  Saldo_posterior,
            -- Saldo en la moneda real de origen antes y después
            Saldo_anterior_original,           Saldo_posterior_original,
            Metodo_transaccion, Estado, Descripcion
        ) VALUES (
            v_cuenta_origen_id, v_cuenta_destino_id, v_tipo_transferencia,
            v_monto_bob,
            p_monto_origen,  v_codigo_origen,
            p_monto_destino, v_codigo_destino,
            IFNULL(v_saldo_origen_bob, v_saldo_mon_origen),
            IFNULL(v_saldo_origen_bob, v_saldo_mon_origen) - v_monto_bob,
            -- Saldo en moneda real de origen antes/después
            v_saldo_mon_origen,
            v_saldo_mon_origen - p_monto_origen,
            p_metodo, 'exitosa',
            IFNULL(p_descripcion, 'Transferencia')
        );

        SET p_transaccion_id = LAST_INSERT_ID();
        COMMIT;

        SET p_mensaje = CONCAT(
            'Transferencia exitosa. ',
            p_monto_origen, ' ', v_codigo_origen,
            ' → ', p_monto_destino, ' ', v_codigo_destino,
            IF(v_hay_conversion = 1,
               CONCAT(' | Nuevo saldo BOB origen: ',
                      ROUND(IFNULL(v_saldo_origen_bob, 0) - v_monto_bob, 2)),
               CONCAT(' | Nuevo saldo ', v_codigo_origen, ': ',
                      ROUND(v_saldo_mon_origen - p_monto_origen, 6))
            )
        );
    END IF;
END$$

CREATE DEFINER=`root`@`localhost` PROCEDURE `sp_registrar_usuario` (IN `p_nombre` VARCHAR(100) COLLATE utf8mb4_unicode_ci, IN `p_apellido` VARCHAR(100) COLLATE utf8mb4_unicode_ci, IN `p_direccion` VARCHAR(255) COLLATE utf8mb4_unicode_ci, IN `p_telefono` VARCHAR(20) COLLATE utf8mb4_unicode_ci, IN `p_edad` INT, IN `p_correo` VARCHAR(150) COLLATE utf8mb4_unicode_ci, IN `p_contrasena` VARCHAR(255) COLLATE utf8mb4_unicode_ci, IN `p_id_rol` INT, IN `p_numero_cuenta` VARCHAR(20) COLLATE utf8mb4_unicode_ci, IN `p_tipo_cuenta` ENUM('ahorro','corriente'), IN `p_saldo_inicial` DECIMAL(15,2), IN `p_numero_tarjeta` VARCHAR(16) COLLATE utf8mb4_unicode_ci, IN `p_pin` VARCHAR(255) COLLATE utf8mb4_unicode_ci, IN `p_tipo_tarjeta` ENUM('debito','credito'), IN `p_fecha_vencimiento` VARCHAR(20) COLLATE utf8mb4_unicode_ci, OUT `p_usuario_id` INT, OUT `p_mensaje` VARCHAR(255) COLLATE utf8mb4_unicode_ci)   BEGIN
    DECLARE v_persona_id   INT;
    DECLARE v_cuenta_id    INT;
    DECLARE v_tarjeta_id   INT;
    DECLARE v_fecha_parsed DATE;
    DECLARE v_id_bob       INT;
    DECLARE v_error_msg    VARCHAR(500) DEFAULT '';
    DECLARE v_error_code   INT          DEFAULT 0;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1
            v_error_code = MYSQL_ERRNO,
            v_error_msg  = MESSAGE_TEXT;
        ROLLBACK;
        SET p_usuario_id = -1;
        SET p_mensaje = CONCAT('Error SQL #', v_error_code, ': ', v_error_msg);
    END;

    SET v_fecha_parsed = COALESCE(
        STR_TO_DATE(p_fecha_vencimiento, '%Y-%m-%d'),
        STR_TO_DATE(p_fecha_vencimiento, '%d-%m-%Y'),
        STR_TO_DATE(p_fecha_vencimiento, '%d/%m/%Y'),
        STR_TO_DATE(p_fecha_vencimiento, '%m/%d/%Y'),
        STR_TO_DATE(p_fecha_vencimiento, '%d/%m/%y'),
        STR_TO_DATE(p_fecha_vencimiento, '%m/%d/%y'),
        STR_TO_DATE(p_fecha_vencimiento, '%d-%m-%y')
    );

    IF v_fecha_parsed IS NULL THEN
        SET p_usuario_id = -1;
        SET p_mensaje = CONCAT('Error: Fecha invalida: [', p_fecha_vencimiento, ']');

    ELSEIF v_fecha_parsed < CURDATE() THEN
        SET p_usuario_id = -1;
        SET p_mensaje = CONCAT('Error: La fecha de vencimiento ya expiro: ', v_fecha_parsed);

    ELSEIF EXISTS (SELECT 1 FROM Users WHERE Correo = p_correo) THEN
        SET p_usuario_id = -1;
        SET p_mensaje = 'Error: El correo ya esta registrado.';

    ELSEIF EXISTS (SELECT 1 FROM Cuenta WHERE Numero_cuenta = p_numero_cuenta) THEN
        SET p_usuario_id = -1;
        SET p_mensaje = 'Error: El numero de cuenta ya existe.';

    ELSEIF EXISTS (SELECT 1 FROM Tarjeta WHERE Numero_tarjeta = p_numero_tarjeta) THEN
        SET p_usuario_id = -1;
        SET p_mensaje = 'Error: El numero de tarjeta ya existe.';

    ELSE
        SELECT ID INTO v_id_bob FROM moneda WHERE Codigo = 'BOB' LIMIT 1;

        IF v_id_bob IS NULL THEN
            SET p_usuario_id = -1;
            SET p_mensaje = 'Error: No se encontro la moneda BOB.';
        ELSE
            START TRANSACTION;

            -- 1. Persona
            INSERT INTO Persona (Nombre, Apellido, Direccion, Telefono, Edad)
            VALUES (p_nombre, p_apellido, p_direccion, p_telefono, p_edad);
            SET v_persona_id = LAST_INSERT_ID();

            -- 2. Usuario
            INSERT INTO Users (ID_Persona, ID_Rol, Correo, Contrasena)
            VALUES (v_persona_id, p_id_rol, p_correo, p_contrasena);
            SET p_usuario_id = LAST_INSERT_ID();

            -- 3. Cuenta
            INSERT INTO Cuenta (Numero_cuenta, ID_Users, Tipo_cuenta)
            VALUES (p_numero_cuenta, p_usuario_id, p_tipo_cuenta);
            SET v_cuenta_id = LAST_INSERT_ID();

            -- 4. Tarjeta (ya SIN columna ID_Cuenta)
            INSERT INTO Tarjeta (ID_Users, Numero_tarjeta, Pin, Tipo_tarjeta, Fecha_vencimiento)
            VALUES (p_usuario_id, p_numero_tarjeta, p_pin, p_tipo_tarjeta, v_fecha_parsed);
            SET v_tarjeta_id = LAST_INSERT_ID();

            -- 5. Vincular cuenta a tarjeta como principal (orden 1)
            INSERT INTO tarjeta_cuenta (ID_Tarjeta, ID_Cuenta, Es_principal, Orden)
            VALUES (v_tarjeta_id, v_cuenta_id, 1, 1);

            -- 6. Saldo inicial en BOB
            INSERT INTO saldo_moneda (ID_Cuenta, ID_Moneda, Saldo)
            VALUES (v_cuenta_id, v_id_bob, p_saldo_inicial);

            COMMIT;
            SET p_mensaje = CONCAT('Usuario registrado exitosamente. ID: ', p_usuario_id,
                                   ' | Cuenta: ', p_numero_cuenta);
        END IF;
    END IF;
END$$

CREATE DEFINER=`root`@`localhost` PROCEDURE `sp_saldos_cuenta` (IN `p_numero_cuenta` VARCHAR(20))   BEGIN
    SELECT
        m.Codigo              AS Codigo_moneda,
        m.Nombre              AS nombre_moneda,
        m.Simbolo,
        sm.Saldo,
        sm.Fecha_modificacion AS ultima_actualizacion
    FROM   saldo_moneda sm
    INNER JOIN moneda m ON sm.ID_Moneda  = m.ID
    INNER JOIN cuenta  c ON sm.ID_Cuenta = c.ID
    WHERE  c.Numero_cuenta = p_numero_cuenta
    ORDER BY sm.Saldo DESC;
END$$

CREATE DEFINER=`root`@`localhost` PROCEDURE `sp_transacciones_usuario` (IN `p_nombre_completo` VARCHAR(201) COLLATE utf8mb4_unicode_ci, IN `p_tipo_transaccion` VARCHAR(50) COLLATE utf8mb4_unicode_ci)   BEGIN
    SELECT
        vtc.transaccion_id,
        vtc.tipo_transaccion,
        vtc.Monto,
        vtc.Saldo_anterior,
        vtc.Saldo_posterior,
        vtc.cuenta_origen,
        vtc.cuenta_destino,
        vtc.nombre_destinatario,
        vtc.Metodo_transaccion,
        vtc.estado_transaccion,
        vtc.Descripcion,
        vtc.Fecha_transaccion
    FROM vista_transacciones_completo vtc
    INNER JOIN vista_usuarios_completo vuc ON vtc.usuario_id = vuc.usuario_id
    WHERE vuc.nombre_completo = p_nombre_completo
      AND (
          p_tipo_transaccion IS NULL
          OR vtc.ID_Tipo_Transaccion = (
              SELECT ID FROM Tipo_Transaccion WHERE Nombre = p_tipo_transaccion LIMIT 1
          )
      )
    ORDER BY vtc.Fecha_transaccion DESC;
END$$

CREATE DEFINER=`root`@`localhost` PROCEDURE `sp_vincular_cuenta_tarjeta` (IN `p_numero_tarjeta` VARCHAR(16) COLLATE utf8mb4_unicode_ci, IN `p_numero_cuenta` VARCHAR(20) COLLATE utf8mb4_unicode_ci, IN `p_es_principal` TINYINT(1), OUT `p_mensaje` VARCHAR(255))   BEGIN
    DECLARE v_tarjeta_id      INT;
    DECLARE v_cuenta_id       INT;
    DECLARE v_count           INT;
    DECLARE v_siguiente_orden TINYINT;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SET p_mensaje = 'Error interno al vincular cuenta.';
    END;

    SELECT ID INTO v_tarjeta_id
    FROM   Tarjeta WHERE Numero_tarjeta = p_numero_tarjeta AND Estado = 'activa' LIMIT 1;

    SELECT ID INTO v_cuenta_id
    FROM   Cuenta  WHERE Numero_cuenta  = p_numero_cuenta  AND Estado = 'activa' LIMIT 1;

    IF v_tarjeta_id IS NULL THEN
        SET p_mensaje = 'Error: Tarjeta no encontrada o inactiva.';

    ELSEIF v_cuenta_id IS NULL THEN
        SET p_mensaje = 'Error: Cuenta no encontrada o inactiva.';

    ELSE
        SELECT COUNT(*) INTO v_count FROM tarjeta_cuenta WHERE ID_Tarjeta = v_tarjeta_id;

        IF v_count >= 4 THEN
            SET p_mensaje = 'Error: La tarjeta ya tiene el maximo de 4 cuentas vinculadas.';

        ELSEIF EXISTS (
            SELECT 1 FROM tarjeta_cuenta
            WHERE  ID_Tarjeta = v_tarjeta_id AND ID_Cuenta = v_cuenta_id
        ) THEN
            SET p_mensaje = 'Error: Esta cuenta ya esta vinculada a la tarjeta.';

        ELSE
            SET v_siguiente_orden = v_count + 1;
            START TRANSACTION;

            IF p_es_principal = 1 THEN
                UPDATE tarjeta_cuenta SET Es_principal = 0 WHERE ID_Tarjeta = v_tarjeta_id;
            END IF;

            INSERT INTO tarjeta_cuenta (ID_Tarjeta, ID_Cuenta, Es_principal, Orden)
            VALUES (v_tarjeta_id, v_cuenta_id, p_es_principal, v_siguiente_orden);

            COMMIT;
            SET p_mensaje = CONCAT('Cuenta vinculada. Posicion: ', v_siguiente_orden,
                                   ' | Principal: ', IF(p_es_principal = 1, 'Si', 'No'));
        END IF;
    END IF;
END$$

DELIMITER ;

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `cambio`
--

CREATE TABLE `cambio` (
  `ID` int(11) NOT NULL,
  `ID_Cuenta` int(11) NOT NULL,
  `Monto_origen` decimal(15,2) NOT NULL,
  `Moneda_origen` varchar(10) NOT NULL,
  `Monto_destino` decimal(15,2) NOT NULL,
  `Moneda_destino` varchar(10) NOT NULL,
  `Tasa_usada` decimal(15,2) NOT NULL,
  `Tipo_tasa` enum('mercado','oficial','paralelo') NOT NULL DEFAULT 'mercado',
  `Estado` enum('completado','revertido') DEFAULT 'completado',
  `Fecha_cambio` datetime DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `cuenta`
--

CREATE TABLE `cuenta` (
  `ID` int(11) NOT NULL,
  `Numero_cuenta` varchar(20) NOT NULL,
  `ID_Users` int(11) NOT NULL,
  `Tipo_cuenta` enum('ahorro','corriente') NOT NULL DEFAULT 'ahorro',
  `Estado` enum('activa','bloqueada','cerrada') DEFAULT 'activa',
  `Fecha_creacion` datetime DEFAULT current_timestamp(),
  `Fecha_modificacion` datetime DEFAULT current_timestamp() ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

--
-- Volcado de datos para la tabla `cuenta`
--

INSERT INTO `cuenta` (`ID`, `Numero_cuenta`, `ID_Users`, `Tipo_cuenta`, `Estado`, `Fecha_creacion`, `Fecha_modificacion`) VALUES
(6, '63788349202', 8, 'ahorro', 'activa', '2026-03-14 13:59:22', '2026-03-14 13:59:22'),
(7, '1175271858800644', 9, 'ahorro', 'activa', '2026-03-14 14:09:12', '2026-03-14 14:09:12'),
(8, '2141978225320079', 10, 'ahorro', 'activa', '2026-03-14 16:50:19', '2026-03-14 16:50:19'),
(12, '5704213255142001', 14, 'corriente', 'activa', '2026-04-17 16:17:22', '2026-04-17 16:17:22'),
(14, '5851617743407592', 16, 'corriente', 'activa', '2026-04-17 16:41:56', '2026-04-17 16:41:56'),
(15, '3805247119402034', 17, 'ahorro', 'activa', '2026-04-18 14:47:32', '2026-04-18 14:47:32');

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `moneda`
--

CREATE TABLE `moneda` (
  `ID` int(11) NOT NULL,
  `Codigo` varchar(10) NOT NULL,
  `Nombre` varchar(50) NOT NULL,
  `Simbolo` varchar(5) NOT NULL,
  `Activa` tinyint(1) DEFAULT 1
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

--
-- Volcado de datos para la tabla `moneda`
--

INSERT INTO `moneda` (`ID`, `Codigo`, `Nombre`, `Simbolo`, `Activa`) VALUES
(1, 'BOB', 'Boliviano', 'Bs.', 1),
(2, 'USD', 'Dólar estadounidense', '$', 1),
(3, 'EUR', 'Euro', '€', 1),
(4, 'BRL', 'Real brasileño', 'R$', 1),
(5, 'ARS', 'Peso argentino', '$', 1),
(6, 'CLP', 'Peso chileno', '$', 1),
(7, 'PEN', 'Sol peruano', 'S/', 1),
(8, 'COP', 'Peso colombiano', '$', 1);

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
(5, 'Juan Perez', 'Garcia', 'Calle Falsa 123', '555-1234', 30, '2026-03-03 14:18:40', '2026-03-03 14:18:40'),
(8, 'Rafael Ignacion', 'Lovera Arancibia', 'Calle Falsa 123', '6207302', 21, '2026-03-14 13:59:22', '2026-03-14 13:59:22'),
(9, 'Carlos', 'Mamani', 'Calle 21 de Enero 456', '76543210', 25, '2026-03-14 14:09:12', '2026-03-14 14:09:12'),
(10, 'Carlos', 'Mamani Choque', 'Calle 21 de Enero 456', '76543210', 25, '2026-03-14 16:50:19', '2026-03-14 16:50:19'),
(14, 'Rafael Ignacio', 'Lovera Arancivia', 'Av. Falsa', '45782983', 22, '2026-04-17 16:17:22', '2026-04-17 16:17:22'),
(16, 'Jaziel Armando', 'Vargas Choque', 'Av. Falsa', '79532646', 21, '2026-04-17 16:41:56', '2026-04-17 16:41:56'),
(17, 'Jaziel ', 'Vargas Choque', 'Calle 21 de Enero 456', '76543210', 25, '2026-04-18 14:47:32', '2026-04-18 14:47:32');

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
-- Estructura de tabla para la tabla `saldo_moneda`
--

CREATE TABLE `saldo_moneda` (
  `ID` int(11) NOT NULL,
  `ID_Cuenta` int(11) NOT NULL,
  `ID_Moneda` int(11) NOT NULL DEFAULT 0,
  `Saldo` decimal(20,2) NOT NULL DEFAULT 0.00,
  `Fecha_creacion` datetime DEFAULT current_timestamp(),
  `Fecha_modificacion` datetime DEFAULT current_timestamp() ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

--
-- Volcado de datos para la tabla `saldo_moneda`
--

INSERT INTO `saldo_moneda` (`ID`, `ID_Cuenta`, `ID_Moneda`, `Saldo`, `Fecha_creacion`, `Fecha_modificacion`) VALUES
(2, 6, 1, 299.00, '2026-03-14 18:22:57', '2026-03-15 13:40:23'),
(3, 7, 1, 0.00, '2026-03-14 18:22:57', '2026-03-14 21:05:09'),
(4, 8, 1, 0.00, '2026-03-14 18:22:57', '2026-03-14 21:05:09'),
(12, 6, 2, 13.00, '2026-03-15 09:43:29', '2026-03-15 09:43:29'),
(16, 12, 1, 947.26, '2026-04-17 16:17:22', '2026-04-23 21:05:07'),
(18, 14, 1, 9647.08, '2026-04-17 16:41:56', '2026-04-23 21:05:07'),
(19, 12, 2, 54.74, '2026-04-18 14:39:11', '2026-04-18 20:35:55'),
(20, 15, 1, 0.00, '2026-04-18 14:47:32', '2026-04-18 14:47:32'),
(21, 14, 7, 5359.20, '2026-04-18 20:59:56', '2026-04-18 20:59:56'),
(22, 14, 2, 7.90, '2026-04-23 20:02:47', '2026-04-23 21:02:19');

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `saldo_moneda_backup`
--

CREATE TABLE `saldo_moneda_backup` (
  `ID` int(11) NOT NULL DEFAULT 0,
  `ID_Cuenta` int(11) NOT NULL,
  `ID_Moneda` int(11) NOT NULL DEFAULT 0,
  `Saldo` decimal(20,6) NOT NULL DEFAULT 0.000000,
  `Fecha_creacion` datetime DEFAULT current_timestamp(),
  `Fecha_modificacion` datetime DEFAULT current_timestamp() ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

--
-- Volcado de datos para la tabla `saldo_moneda_backup`
--

INSERT INTO `saldo_moneda_backup` (`ID`, `ID_Cuenta`, `ID_Moneda`, `Saldo`, `Fecha_creacion`, `Fecha_modificacion`) VALUES
(2, 6, 1, 499.000000, '2026-03-14 18:22:57', '2026-03-15 10:08:29'),
(3, 7, 1, 0.000000, '2026-03-14 18:22:57', '2026-03-14 21:05:09'),
(4, 8, 1, 0.000000, '2026-03-14 18:22:57', '2026-03-14 21:05:09'),
(10, 9, 1, 0.000000, '2026-03-14 20:49:17', '2026-03-15 13:22:25'),
(11, 9, 2, 1562.446372, '2026-03-14 23:00:43', '2026-03-15 13:11:21'),
(12, 6, 2, 13.000000, '2026-03-15 09:43:29', '2026-03-15 09:43:29'),
(13, 9, 3, 13.790747, '2026-03-15 12:27:36', '2026-03-15 12:27:36');

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

INSERT INTO `tarjeta` (`ID`, `ID_Users`, `Numero_tarjeta`, `Pin`, `Tipo_tarjeta`, `Estado`, `Fecha_vencimiento`, `Fecha_creacion`, `Fecha_modificacion`) VALUES
(6, 8, '10000277192', '$2b$10$NuwfhS9hN6OH2TT8Kpnkk.bxMxqBdILSynacw7clvWk0wRwLw31gi', 'debito', 'activa', '2025-12-31', '2026-03-14 13:59:22', '2026-03-14 13:59:22'),
(7, 9, '5500112233445566', '$2b$10$c3wUTXatKxoc8qDXsoJ5kutoMAXt5qhPlNVbLpbb1s511jEQrJYg.', 'debito', 'activa', '2031-03-14', '2026-03-14 14:09:12', '2026-03-14 14:09:12'),
(8, 10, '4141978347973558', '$2b$10$CjnIb.GEQ6sZvXWWuHiXyePSJobI.rlt5ufjDr5CedHJAJ/cpKHr6', 'debito', 'activa', '2031-03-14', '2026-03-14 16:50:19', '2026-03-14 16:50:19'),
(12, 14, '4704213222089218', '$2b$10$z9yrQw6n4AES5wqcLtpiI.7h6QYakhMifGyQtB1u4B84j4ZaOLw1O', 'debito', 'activa', '2031-04-17', '2026-04-17 16:17:22', '2026-04-17 16:17:22'),
(14, 16, '4851617793844965', '$2b$10$p1sV2OKc8td/b2gXIFq8A.njo3.tVVsPCa5fxzryQeZz2OzSfb6n6', 'debito', 'activa', '2031-04-17', '2026-04-17 16:41:56', '2026-04-17 16:41:56'),
(15, 17, '4805247176922664', '$2b$10$qtWIZb7ePajzOcZ24a2ebuxPkoCaw9U0AWgWOg3/jb2ye3zYVBwny', 'credito', 'activa', '2031-04-18', '2026-04-18 14:47:32', '2026-04-18 14:47:32');

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `tarjeta_cuenta`
--

CREATE TABLE `tarjeta_cuenta` (
  `ID` int(11) NOT NULL,
  `ID_Tarjeta` int(11) NOT NULL,
  `ID_Cuenta` int(11) NOT NULL,
  `Es_principal` tinyint(1) NOT NULL DEFAULT 1 COMMENT '1 = cuenta principal de la tarjeta',
  `Orden` tinyint(4) NOT NULL DEFAULT 1 COMMENT 'Posicion visible al usuario (1 a 4)',
  `Fecha_vinculacion` datetime DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='Relacion N:M entre Tarjeta y Cuenta (maximo 4 cuentas por tarjeta)';

--
-- Volcado de datos para la tabla `tarjeta_cuenta`
--

INSERT INTO `tarjeta_cuenta` (`ID`, `ID_Tarjeta`, `ID_Cuenta`, `Es_principal`, `Orden`, `Fecha_vinculacion`) VALUES
(1, 6, 6, 1, 1, '2026-04-18 11:04:00'),
(2, 7, 7, 1, 1, '2026-04-18 11:04:00'),
(3, 8, 8, 1, 1, '2026-04-18 11:04:00'),
(4, 12, 12, 1, 1, '2026-04-18 11:04:00'),
(5, 14, 14, 1, 1, '2026-04-18 11:04:00'),
(6, 15, 15, 1, 1, '2026-04-18 14:47:32');

--
-- Disparadores `tarjeta_cuenta`
--
DELIMITER $$
CREATE TRIGGER `trg_max_cuentas_por_tarjeta` BEFORE INSERT ON `tarjeta_cuenta` FOR EACH ROW BEGIN
    DECLARE v_count INT;
    SELECT COUNT(*) INTO v_count
    FROM   `tarjeta_cuenta`
    WHERE  `ID_Tarjeta` = NEW.ID_Tarjeta;

    IF v_count >= 4 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Error: Una tarjeta no puede tener mas de 4 cuentas vinculadas.';
    END IF;
END
$$
DELIMITER ;
DELIMITER $$
CREATE TRIGGER `trg_principal_unica_insert` BEFORE INSERT ON `tarjeta_cuenta` FOR EACH ROW BEGIN
    IF NEW.Es_principal = 1 THEN
        IF EXISTS (
            SELECT 1 
            FROM `tarjeta_cuenta` 
            WHERE `ID_Tarjeta` = NEW.ID_Tarjeta 
              AND `Es_principal` = 1
        ) THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'Error: Ya existe una cuenta principal para esta tarjeta.';
        END IF;
    END IF;
END
$$
DELIMITER ;
DELIMITER $$
CREATE TRIGGER `trg_principal_unica_update` BEFORE UPDATE ON `tarjeta_cuenta` FOR EACH ROW BEGIN
    IF NEW.Es_principal = 1 AND OLD.Es_principal = 0 THEN
        IF EXISTS (
            SELECT 1 
            FROM `tarjeta_cuenta` 
            WHERE `ID_Tarjeta` = NEW.ID_Tarjeta 
              AND `Es_principal` = 1 
              AND `ID` != NEW.ID
        ) THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'Error: Ya existe una cuenta principal para esta tarjeta.';
        END IF;
    END IF;
END
$$
DELIMITER ;

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `tasa_cambio`
--

CREATE TABLE `tasa_cambio` (
  `ID` int(11) NOT NULL,
  `Moneda_origen` varchar(10) NOT NULL,
  `Moneda_destino` varchar(10) NOT NULL,
  `Tasa_oficial` decimal(15,2) DEFAULT NULL,
  `Tasa_paralelo` decimal(15,2) DEFAULT NULL,
  `Fecha_actualizacion` datetime DEFAULT current_timestamp() ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

--
-- Volcado de datos para la tabla `tasa_cambio`
--

INSERT INTO `tasa_cambio` (`ID`, `Moneda_origen`, `Moneda_destino`, `Tasa_oficial`, `Tasa_paralelo`, `Fecha_actualizacion`) VALUES
(1, 'BOB', 'USD', 0.14, 0.12, '2026-03-14 17:44:10');

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `tasa_cambio_cache`
--

CREATE TABLE `tasa_cambio_cache` (
  `ID` int(11) NOT NULL,
  `Moneda_origen` varchar(10) NOT NULL,
  `Moneda_destino` varchar(10) NOT NULL,
  `Tasa` decimal(20,2) NOT NULL,
  `Tipo_tasa` enum('oficial','binance','manual') NOT NULL DEFAULT 'oficial',
  `Fecha_actualizacion` datetime DEFAULT current_timestamp() ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

--
-- Volcado de datos para la tabla `tasa_cambio_cache`
--

INSERT INTO `tasa_cambio_cache` (`ID`, `Moneda_origen`, `Moneda_destino`, `Tasa`, `Tipo_tasa`, `Fecha_actualizacion`) VALUES
(1, 'BOB', 'USD', 0.14, 'oficial', '2026-04-23 21:02:19'),
(2, 'USD', 'BOB', 6.96, 'oficial', '2026-04-23 21:02:19'),
(3, 'BOB', 'USD', 0.10, 'binance', '2026-04-23 21:02:19'),
(4, 'USD', 'BOB', 9.66, 'binance', '2026-04-23 21:02:19');

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `tasa_cambio_cache_backup`
--

CREATE TABLE `tasa_cambio_cache_backup` (
  `ID` int(11) NOT NULL DEFAULT 0,
  `Moneda_origen` varchar(10) NOT NULL,
  `Moneda_destino` varchar(10) NOT NULL,
  `Tasa` decimal(20,8) NOT NULL,
  `Tipo_tasa` enum('oficial','binance','manual') NOT NULL DEFAULT 'oficial',
  `Fecha_actualizacion` datetime DEFAULT current_timestamp() ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

--
-- Volcado de datos para la tabla `tasa_cambio_cache_backup`
--

INSERT INTO `tasa_cambio_cache_backup` (`ID`, `Moneda_origen`, `Moneda_destino`, `Tasa`, `Tipo_tasa`, `Fecha_actualizacion`) VALUES
(1, 'BOB', 'USD', 0.14367816, 'oficial', '2026-03-15 13:11:21'),
(2, 'USD', 'BOB', 6.96000000, 'oficial', '2026-03-15 13:11:21'),
(3, 'BOB', 'USD', 0.10615711, 'binance', '2026-03-15 13:11:21'),
(4, 'USD', 'BOB', 9.42000000, 'binance', '2026-03-15 13:11:21');

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
  `Monto_original` decimal(20,6) DEFAULT NULL COMMENT 'Monto en la moneda original de la operación',
  `Moneda_origen` varchar(10) DEFAULT NULL COMMENT 'Código ISO de la moneda origen (BOB, USD, EUR…)',
  `Monto_destino` decimal(20,6) DEFAULT NULL COMMENT 'Monto acreditado en cuenta destino (transferencias)',
  `Moneda_destino` varchar(10) DEFAULT NULL COMMENT 'Código ISO de la moneda destino (transferencias)',
  `Saldo_anterior` decimal(15,2) DEFAULT NULL,
  `Saldo_anterior_original` decimal(20,6) DEFAULT NULL COMMENT 'Saldo antes de la operación en la moneda original (no BOB)',
  `Saldo_posterior` decimal(15,2) DEFAULT NULL,
  `Saldo_posterior_original` decimal(20,6) DEFAULT NULL COMMENT 'Saldo después de la operación en la moneda original (no BOB)',
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

INSERT INTO `transacciones` (`ID`, `ID_Cuenta_Transfiere`, `ID_Cuenta_Transferida`, `ID_Tipo_Transaccion`, `Monto`, `Monto_original`, `Moneda_origen`, `Monto_destino`, `Moneda_destino`, `Saldo_anterior`, `Saldo_anterior_original`, `Saldo_posterior`, `Saldo_posterior_original`, `Metodo_transaccion`, `Estado`, `Descripcion`, `Fecha_transaccion`, `Fecha_creacion`, `Fecha_modificacion`) VALUES
(21, 6, NULL, 3, 200.00, 200.000000, 'BOB', NULL, NULL, 1000.00, 1000.000000, 800.00, 800.000000, 'ATM', 'exitosa', 'Pago de deuda', '2026-03-14 23:00:22', '2026-03-14 23:00:22', '2026-04-23 20:50:50'),
(22, 6, NULL, 3, 100.00, 100.000000, 'BOB', NULL, NULL, 800.00, 800.000000, 700.00, 700.000000, 'web', 'exitosa', 'Transferencia internacional', '2026-03-14 23:00:43', '2026-03-14 23:00:43', '2026-04-23 20:50:50'),
(23, 6, NULL, 3, 472.00, 472.000000, 'BOB', NULL, NULL, 700.00, 700.000000, 228.00, 228.000000, 'ATM', 'exitosa', 'Conversión confirmada', '2026-03-14 23:01:17', '2026-03-14 23:01:17', '2026-04-23 20:50:50'),
(31, 6, NULL, 3, 200.00, 200.000000, 'BOB', NULL, NULL, 699.00, 699.000000, 499.00, 499.000000, 'ATM', 'exitosa', 'Pago de deuda', '2026-03-15 10:08:29', '2026-03-15 10:08:29', '2026-04-23 20:50:50'),
(43, 6, NULL, 3, 200.00, 200.000000, 'BOB', NULL, NULL, 499.00, 499.000000, 299.00, 299.000000, 'ATM', 'exitosa', 'Pago de deuda', '2026-03-15 13:40:23', '2026-03-15 13:40:23', '2026-04-23 20:50:50'),
(46, 14, NULL, 2, 500.00, 500.000000, 'BOB', NULL, NULL, 0.00, 0.000000, 500.00, 500.000000, 'ATM', 'exitosa', 'Deposito directo 500.000000 BOB', '2026-04-18 11:42:20', '2026-04-18 11:42:20', '2026-04-23 20:50:50'),
(47, 14, NULL, 2, 951.00, 951.000000, 'BOB', NULL, NULL, 500.00, 500.000000, 1451.00, 1451.000000, 'ATM', 'exitosa', 'Deposito 100.000000 USD -> 951.000000 BOB', '2026-04-18 11:42:53', '2026-04-18 11:42:53', '2026-04-23 20:50:50'),
(48, 14, NULL, 1, 500.00, 500.000000, 'BOB', NULL, NULL, 1451.00, 1451.000000, 951.00, 951.000000, 'ATM', 'exitosa', 'Retiro directo en BOB', '2026-04-18 11:43:58', '2026-04-18 11:43:58', '2026-04-23 20:50:50'),
(49, 14, NULL, 1, 9.51, 9.510000, 'BOB', NULL, NULL, 951.00, 951.000000, 941.49, 941.490000, 'ATM', 'exitosa', 'Retiro (conv.) 1.000000 USD desde BOB', '2026-04-18 11:44:35', '2026-04-18 11:44:35', '2026-04-23 20:50:50'),
(50, 14, NULL, 2, 500.00, 500.000000, 'BOB', NULL, NULL, 941.49, 941.490000, 1441.49, 1441.490000, 'ATM', 'exitosa', 'Deposito directo 500.000000 BOB', '2026-04-18 11:44:53', '2026-04-18 11:44:53', '2026-04-23 20:50:50'),
(51, 14, NULL, 2, 951.00, 951.000000, 'BOB', NULL, NULL, 1441.49, 1441.490000, 2392.49, 2392.490000, 'ATM', 'exitosa', 'Deposito 100.000000 USD -> 951.000000 BOB', '2026-04-18 11:44:57', '2026-04-18 11:44:57', '2026-04-23 20:50:50'),
(52, 14, NULL, 2, 950.00, 950.000000, 'BOB', NULL, NULL, 2392.49, 2392.490000, 3342.49, 3342.490000, 'ATM', 'exitosa', 'Deposito 100.000000 USD -> 950.000000 BOB', '2026-04-18 14:07:55', '2026-04-18 14:07:55', '2026-04-23 20:50:50'),
(53, 14, NULL, 2, 500.00, 500.000000, 'BOB', NULL, NULL, 3342.49, 3342.490000, 3842.49, 3842.490000, 'ATM', 'exitosa', 'Deposito directo 500.000000 BOB', '2026-04-18 14:19:19', '2026-04-18 14:19:19', '2026-04-23 20:50:50'),
(54, 14, NULL, 2, 500.00, 500.000000, 'BOB', NULL, NULL, 3842.49, 3842.490000, 4342.49, 4342.490000, 'ATM', 'exitosa', 'Deposito directo 500.000000 BOB', '2026-04-18 14:19:28', '2026-04-18 14:19:28', '2026-04-23 20:50:50'),
(55, 14, NULL, 2, 500.00, 500.000000, 'BOB', NULL, NULL, 4342.49, 4342.490000, 4842.49, 4842.490000, 'ATM', 'exitosa', 'Deposito directo 500.000000 BOB', '2026-04-18 14:19:29', '2026-04-18 14:19:29', '2026-04-23 20:50:50'),
(56, 14, NULL, 2, 500.00, 500.000000, 'BOB', NULL, NULL, 4842.49, 4842.490000, 5342.49, 5342.490000, 'ATM', 'exitosa', 'Deposito directo 500.000000 BOB', '2026-04-18 14:19:30', '2026-04-18 14:19:30', '2026-04-23 20:50:50'),
(57, 14, NULL, 2, 500.00, 500.000000, 'BOB', NULL, NULL, 5342.49, 5342.490000, 5842.49, 5842.490000, 'ATM', 'exitosa', 'Deposito directo 500.000000 BOB', '2026-04-18 14:19:30', '2026-04-18 14:19:30', '2026-04-23 20:50:50'),
(58, 14, NULL, 2, 500.00, 500.000000, 'BOB', NULL, NULL, 5842.49, 5842.490000, 6342.49, 6342.490000, 'ATM', 'exitosa', 'Deposito directo 500.000000 BOB', '2026-04-18 14:19:30', '2026-04-18 14:19:30', '2026-04-23 20:50:50'),
(59, 14, NULL, 2, 500.00, 500.000000, 'BOB', NULL, NULL, 6342.49, 6342.490000, 6842.49, 6842.490000, 'ATM', 'exitosa', 'Deposito directo 500.000000 BOB', '2026-04-18 14:19:31', '2026-04-18 14:19:31', '2026-04-23 20:50:50'),
(60, 14, NULL, 2, 500.00, 500.000000, 'BOB', NULL, NULL, 6842.49, 6842.490000, 7342.49, 7342.490000, 'ATM', 'exitosa', 'Deposito directo 500.000000 BOB', '2026-04-18 14:19:31', '2026-04-18 14:19:31', '2026-04-23 20:50:50'),
(61, 14, NULL, 2, 500.00, 500.000000, 'BOB', NULL, NULL, 7342.49, 7342.490000, 7842.49, 7842.490000, 'ATM', 'exitosa', 'Deposito directo 500.000000 BOB', '2026-04-18 14:19:31', '2026-04-18 14:19:31', '2026-04-23 20:50:50'),
(62, 14, NULL, 2, 500.00, 500.000000, 'BOB', NULL, NULL, 7842.49, 7842.490000, 8342.49, 8342.490000, 'ATM', 'exitosa', 'Deposito directo 500.000000 BOB', '2026-04-18 14:19:31', '2026-04-18 14:19:31', '2026-04-23 20:50:50'),
(63, 14, 12, 3, 200.00, 200.000000, 'BOB', NULL, NULL, 8342.49, 8342.490000, 8142.49, 8142.490000, 'ATM', 'exitosa', 'Pago de deuda', '2026-04-18 14:38:41', '2026-04-18 14:38:41', '2026-04-23 20:50:50'),
(64, 14, 12, 3, 100.00, 100.000000, 'BOB', NULL, NULL, 8142.49, 8142.490000, 8042.49, 8042.490000, 'web', 'exitosa', 'Transferencia internacional', '2026-04-18 14:39:11', '2026-04-18 14:39:11', '2026-04-23 20:50:50'),
(65, 14, 12, 3, 123.50, 123.500000, 'BOB', NULL, NULL, 8042.49, 8042.490000, 7918.99, 7918.990000, 'ATM', 'exitosa', 'Conversión confirmada', '2026-04-18 14:39:36', '2026-04-18 14:39:36', '2026-04-23 20:50:50'),
(66, 14, 12, 3, 123.76, 123.760000, 'BOB', NULL, NULL, 7918.99, 7918.990000, 7795.23, 7795.230000, 'ATM', 'exitosa', 'Conversión confirmada', '2026-04-18 20:35:31', '2026-04-18 20:35:31', '2026-04-23 20:50:50'),
(67, 14, 12, 3, 100.00, 100.000000, 'BOB', NULL, NULL, 7795.23, 7795.230000, 7695.23, 7695.230000, 'web', 'exitosa', 'Transferencia internacional', '2026-04-18 20:35:55', '2026-04-18 20:35:55', '2026-04-23 20:50:50'),
(68, 14, 12, 3, 200.00, 200.000000, 'BOB', NULL, NULL, 7695.23, 7695.230000, 7495.23, 7495.230000, 'ATM', 'exitosa', 'Pago de deuda', '2026-04-18 20:36:03', '2026-04-18 20:36:03', '2026-04-23 20:50:50'),
(69, 14, NULL, 2, 952.00, 952.000000, 'BOB', NULL, NULL, 7495.23, 7495.230000, 8447.23, 8447.230000, 'ATM', 'exitosa', 'Deposito', '2026-04-18 20:36:10', '2026-04-18 20:36:10', '2026-04-23 20:50:50'),
(70, 14, NULL, 2, 952.00, 952.000000, 'BOB', NULL, NULL, 8447.23, 8447.230000, 9399.23, 9399.230000, 'ATM', 'exitosa', 'Deposito', '2026-04-18 20:36:14', '2026-04-18 20:36:14', '2026-04-23 20:50:50'),
(71, 14, NULL, 2, 10000.00, 10000.000000, 'BOB', NULL, NULL, 0.00, 0.000000, 5359.20, 5359.200000, 'ATM', 'exitosa', 'Deposito', '2026-04-18 20:59:56', '2026-04-18 20:59:56', '2026-04-23 20:50:50'),
(72, 14, NULL, 2, 10000.00, 10000.000000, 'BOB', NULL, NULL, 19399.23, 19399.230000, 29399.23, 29399.230000, '', 'exitosa', 'Deposito', '2026-04-19 12:39:12', '2026-04-19 12:39:12', '2026-04-23 20:50:50'),
(73, 14, NULL, 2, 950.00, 950.000000, 'BOB', NULL, NULL, 29399.23, 29399.230000, 30349.23, 30349.230000, 'web', 'exitosa', 'Deposito', '2026-04-19 15:55:27', '2026-04-19 15:55:27', '2026-04-23 20:50:50'),
(74, 14, NULL, 2, 950.00, 950.000000, 'BOB', NULL, NULL, 30349.23, 30349.230000, 31299.23, 31299.230000, 'web', 'exitosa', 'Deposito', '2026-04-19 15:58:26', '2026-04-19 15:58:26', '2026-04-23 20:50:50'),
(75, 14, NULL, 1, 9.51, 9.510000, 'BOB', NULL, NULL, 31299.23, 31299.230000, 31289.72, 31289.720000, 'ATM', 'exitosa', 'Retiro', '2026-04-19 17:30:35', '2026-04-19 17:30:35', '2026-04-23 20:50:50'),
(76, 14, NULL, 1, 500.00, 500.000000, 'BOB', NULL, NULL, 31289.72, 31289.720000, 30789.72, 30789.720000, 'ATM', 'exitosa', 'Retiro', '2026-04-19 17:31:15', '2026-04-19 17:31:15', '2026-04-23 20:50:50'),
(77, 14, NULL, 1, 500.00, 500.000000, 'BOB', NULL, NULL, 30789.72, 30789.720000, 30289.72, 30289.720000, 'ATM', 'exitosa', 'Retiro', '2026-04-19 17:31:19', '2026-04-19 17:31:19', '2026-04-23 20:50:50'),
(78, 14, NULL, 1, 500.00, 500.000000, 'BOB', NULL, NULL, 30289.72, 30289.720000, 29789.72, 29789.720000, 'ATM', 'exitosa', 'Retiro', '2026-04-19 17:31:20', '2026-04-19 17:31:20', '2026-04-23 20:50:50'),
(79, 14, NULL, 1, 500.00, 500.000000, 'BOB', NULL, NULL, 29789.72, 29789.720000, 29289.72, 29289.720000, 'ATM', 'exitosa', 'Retiro', '2026-04-19 17:31:20', '2026-04-19 17:31:20', '2026-04-23 20:50:50'),
(80, 14, NULL, 1, 500.00, 500.000000, 'BOB', NULL, NULL, 29289.72, 29289.720000, 28789.72, 28789.720000, 'ATM', 'exitosa', 'Retiro', '2026-04-19 17:31:21', '2026-04-19 17:31:21', '2026-04-23 20:50:50'),
(81, 14, NULL, 1, 500.00, 500.000000, 'BOB', NULL, NULL, 28789.72, 28789.720000, 28289.72, 28289.720000, 'ATM', 'exitosa', 'Retiro', '2026-04-19 17:31:21', '2026-04-19 17:31:21', '2026-04-23 20:50:50'),
(82, 14, NULL, 1, 500.00, 500.000000, 'BOB', NULL, NULL, 28289.72, 28289.720000, 27789.72, 27789.720000, 'ATM', 'exitosa', 'Retiro', '2026-04-19 17:31:21', '2026-04-19 17:31:21', '2026-04-23 20:50:50'),
(83, 14, NULL, 1, 500.00, 500.000000, 'BOB', NULL, NULL, 27789.72, 27789.720000, 27289.72, 27289.720000, 'ATM', 'exitosa', 'Retiro', '2026-04-19 17:31:21', '2026-04-19 17:31:21', '2026-04-23 20:50:50'),
(84, 14, NULL, 1, 500.00, 500.000000, 'BOB', NULL, NULL, 27289.72, 27289.720000, 26789.72, 26789.720000, 'ATM', 'exitosa', 'Retiro', '2026-04-19 17:31:21', '2026-04-19 17:31:21', '2026-04-23 20:50:50'),
(85, 14, NULL, 1, 500.00, 500.000000, 'BOB', NULL, NULL, 26789.72, 26789.720000, 26289.72, 26289.720000, 'ATM', 'exitosa', 'Retiro', '2026-04-19 17:31:22', '2026-04-19 17:31:22', '2026-04-23 20:50:50'),
(86, 14, NULL, 1, 500.00, 500.000000, 'BOB', NULL, NULL, 26289.72, 26289.720000, 25789.72, 25789.720000, 'ATM', 'exitosa', 'Retiro', '2026-04-19 17:31:22', '2026-04-19 17:31:22', '2026-04-23 20:50:50'),
(87, 14, NULL, 1, 500.00, 500.000000, 'BOB', NULL, NULL, 25789.72, 25789.720000, 25289.72, 25289.720000, 'ATM', 'exitosa', 'Retiro', '2026-04-19 17:31:22', '2026-04-19 17:31:22', '2026-04-23 20:50:50'),
(88, 14, NULL, 1, 500.00, 500.000000, 'BOB', NULL, NULL, 25289.72, 25289.720000, 24789.72, 24789.720000, 'ATM', 'exitosa', 'Retiro', '2026-04-19 17:31:22', '2026-04-19 17:31:22', '2026-04-23 20:50:50'),
(89, 14, NULL, 1, 500.00, 500.000000, 'BOB', NULL, NULL, 24789.72, 24789.720000, 24289.72, 24289.720000, 'ATM', 'exitosa', 'Retiro', '2026-04-19 17:31:22', '2026-04-19 17:31:22', '2026-04-23 20:50:50'),
(90, 14, NULL, 1, 500.00, 500.000000, 'BOB', NULL, NULL, 24289.72, 24289.720000, 23789.72, 23789.720000, 'ATM', 'exitosa', 'Retiro', '2026-04-19 17:31:23', '2026-04-19 17:31:23', '2026-04-23 20:50:50'),
(91, 14, NULL, 1, 500.00, 500.000000, 'BOB', NULL, NULL, 23789.72, 23789.720000, 23289.72, 23289.720000, 'ATM', 'exitosa', 'Retiro', '2026-04-19 17:31:23', '2026-04-19 17:31:23', '2026-04-23 20:50:50'),
(92, 14, NULL, 1, 500.00, 500.000000, 'BOB', NULL, NULL, 23289.72, 23289.720000, 22789.72, 22789.720000, 'ATM', 'exitosa', 'Retiro', '2026-04-19 17:31:23', '2026-04-19 17:31:23', '2026-04-23 20:50:50'),
(93, 14, NULL, 1, 500.00, 500.000000, 'BOB', NULL, NULL, 22789.72, 22789.720000, 22289.72, 22289.720000, 'ATM', 'exitosa', 'Retiro', '2026-04-19 17:31:23', '2026-04-19 17:31:23', '2026-04-23 20:50:50'),
(94, 14, NULL, 1, 500.00, 500.000000, 'BOB', NULL, NULL, 22289.72, 22289.720000, 21789.72, 21789.720000, 'ATM', 'exitosa', 'Retiro', '2026-04-19 17:31:23', '2026-04-19 17:31:23', '2026-04-23 20:50:50'),
(95, 14, NULL, 1, 500.00, 500.000000, 'BOB', NULL, NULL, 21789.72, 21789.720000, 21289.72, 21289.720000, 'ATM', 'exitosa', 'Retiro', '2026-04-19 17:31:24', '2026-04-19 17:31:24', '2026-04-23 20:50:50'),
(96, 14, NULL, 1, 500.00, 500.000000, 'BOB', NULL, NULL, 21289.72, 21289.720000, 20789.72, 20789.720000, 'ATM', 'exitosa', 'Retiro', '2026-04-19 17:31:24', '2026-04-19 17:31:24', '2026-04-23 20:50:50'),
(97, 14, NULL, 1, 500.00, 500.000000, 'BOB', NULL, NULL, 20789.72, 20789.720000, 20289.72, 20289.720000, 'ATM', 'exitosa', 'Retiro', '2026-04-19 17:31:24', '2026-04-19 17:31:24', '2026-04-23 20:50:50'),
(98, 14, NULL, 1, 500.00, 500.000000, 'BOB', NULL, NULL, 20289.72, 20289.720000, 19789.72, 19789.720000, 'ATM', 'exitosa', 'Retiro', '2026-04-19 17:31:24', '2026-04-19 17:31:24', '2026-04-23 20:50:50'),
(99, 14, NULL, 1, 500.00, 500.000000, 'BOB', NULL, NULL, 19789.72, 19789.720000, 19289.72, 19289.720000, 'ATM', 'exitosa', 'Retiro', '2026-04-19 17:31:25', '2026-04-19 17:31:25', '2026-04-23 20:50:50'),
(100, 14, NULL, 1, 500.00, 500.000000, 'BOB', NULL, NULL, 19289.72, 19289.720000, 18789.72, 18789.720000, 'ATM', 'exitosa', 'Retiro', '2026-04-19 17:31:25', '2026-04-19 17:31:25', '2026-04-23 20:50:50'),
(101, 14, NULL, 1, 500.00, 500.000000, 'BOB', NULL, NULL, 18789.72, 18789.720000, 18289.72, 18289.720000, 'ATM', 'exitosa', 'Retiro', '2026-04-19 17:31:25', '2026-04-19 17:31:25', '2026-04-23 20:50:50'),
(102, 14, NULL, 1, 500.00, 500.000000, 'BOB', NULL, NULL, 18289.72, 18289.720000, 17789.72, 17789.720000, 'ATM', 'exitosa', 'Retiro', '2026-04-19 17:31:25', '2026-04-19 17:31:25', '2026-04-23 20:50:50'),
(103, 14, NULL, 1, 500.00, 500.000000, 'BOB', NULL, NULL, 17789.72, 17789.720000, 17289.72, 17289.720000, 'ATM', 'exitosa', 'Retiro', '2026-04-19 17:31:25', '2026-04-19 17:31:25', '2026-04-23 20:50:50'),
(104, 14, NULL, 1, 500.00, 500.000000, 'BOB', NULL, NULL, 17289.72, 17289.720000, 16789.72, 16789.720000, 'ATM', 'exitosa', 'Retiro', '2026-04-19 17:31:26', '2026-04-19 17:31:26', '2026-04-23 20:50:50'),
(105, 14, NULL, 1, 500.00, 500.000000, 'BOB', NULL, NULL, 16789.72, 16789.720000, 16289.72, 16289.720000, 'ATM', 'exitosa', 'Retiro', '2026-04-19 17:31:26', '2026-04-19 17:31:26', '2026-04-23 20:50:50'),
(106, 14, NULL, 1, 500.00, 500.000000, 'BOB', NULL, NULL, 16289.72, 16289.720000, 15789.72, 15789.720000, 'ATM', 'exitosa', 'Retiro', '2026-04-19 17:31:27', '2026-04-19 17:31:27', '2026-04-23 20:50:50'),
(107, 14, NULL, 1, 500.00, 500.000000, 'BOB', NULL, NULL, 15789.72, 15789.720000, 15289.72, 15289.720000, 'ATM', 'exitosa', 'Retiro', '2026-04-19 17:31:27', '2026-04-19 17:31:27', '2026-04-23 20:50:50'),
(108, 14, NULL, 1, 500.00, 500.000000, 'BOB', NULL, NULL, 15289.72, 15289.720000, 14789.72, 14789.720000, 'ATM', 'exitosa', 'Retiro', '2026-04-19 17:31:27', '2026-04-19 17:31:27', '2026-04-23 20:50:50'),
(109, 14, NULL, 1, 500.00, 500.000000, 'BOB', NULL, NULL, 14789.72, 14789.720000, 14289.72, 14289.720000, 'ATM', 'exitosa', 'Retiro', '2026-04-19 17:31:27', '2026-04-19 17:31:27', '2026-04-23 20:50:50'),
(110, 14, NULL, 1, 500.00, 500.000000, 'BOB', NULL, NULL, 14289.72, 14289.720000, 13789.72, 13789.720000, 'ATM', 'exitosa', 'Retiro', '2026-04-19 17:31:27', '2026-04-19 17:31:27', '2026-04-23 20:50:50'),
(111, 14, NULL, 1, 500.00, 500.000000, 'BOB', NULL, NULL, 13789.72, 13789.720000, 13289.72, 13289.720000, 'ATM', 'exitosa', 'Retiro', '2026-04-19 17:31:27', '2026-04-19 17:31:27', '2026-04-23 20:50:50'),
(112, 14, NULL, 1, 500.00, 500.000000, 'BOB', NULL, NULL, 13289.72, 13289.720000, 12789.72, 12789.720000, 'ATM', 'exitosa', 'Retiro', '2026-04-19 17:31:28', '2026-04-19 17:31:28', '2026-04-23 20:50:50'),
(113, 14, NULL, 1, 500.00, 500.000000, 'BOB', NULL, NULL, 12789.72, 12789.720000, 12289.72, 12289.720000, 'ATM', 'exitosa', 'Retiro', '2026-04-19 17:31:28', '2026-04-19 17:31:28', '2026-04-23 20:50:50'),
(114, 14, NULL, 1, 500.00, 500.000000, 'BOB', NULL, NULL, 12289.72, 12289.720000, 11789.72, 11789.720000, 'ATM', 'exitosa', 'Retiro', '2026-04-19 17:31:28', '2026-04-19 17:31:28', '2026-04-23 20:50:50'),
(115, 14, NULL, 1, 500.00, 500.000000, 'BOB', NULL, NULL, 11789.72, 11789.720000, 11289.72, 11289.720000, 'ATM', 'exitosa', 'Retiro', '2026-04-19 17:31:28', '2026-04-19 17:31:28', '2026-04-23 20:50:50'),
(116, 14, NULL, 1, 500.00, 500.000000, 'BOB', NULL, NULL, 11289.72, 11289.720000, 10789.72, 10789.720000, 'ATM', 'exitosa', 'Retiro', '2026-04-19 17:31:28', '2026-04-19 17:31:28', '2026-04-23 20:50:50'),
(117, 14, NULL, 1, 500.00, 500.000000, 'BOB', NULL, NULL, 10789.72, 10789.720000, 10289.72, 10289.720000, 'ATM', 'exitosa', 'Retiro', '2026-04-19 17:31:28', '2026-04-19 17:31:28', '2026-04-23 20:50:50'),
(118, 14, NULL, 1, 500.00, 500.000000, 'BOB', NULL, NULL, 10289.72, 10289.720000, 9789.72, 9789.720000, 'ATM', 'exitosa', 'Retiro', '2026-04-19 17:31:29', '2026-04-19 17:31:29', '2026-04-23 20:50:50'),
(119, 14, NULL, 1, 500.00, 500.000000, 'BOB', NULL, NULL, 9789.72, 9789.720000, 9289.72, 9289.720000, 'ATM', 'exitosa', 'Retiro', '2026-04-19 17:31:29', '2026-04-19 17:31:29', '2026-04-23 20:50:50'),
(120, 14, NULL, 1, 1.00, 1.000000, 'BOB', NULL, NULL, 9289.72, 9289.720000, 9288.72, 9288.720000, 'ATM', 'exitosa', 'Retiro', '2026-04-23 19:25:48', '2026-04-23 19:25:48', '2026-04-23 20:50:50'),
(121, 14, NULL, 1, 1.00, 1.000000, 'BOB', NULL, NULL, 9289.72, 9289.720000, 9288.72, 9288.720000, 'ATM', 'exitosa', 'Retiro', '2026-04-23 19:25:48', '2026-04-23 19:25:48', '2026-04-23 20:50:50'),
(122, 14, NULL, 1, 1.00, 1.000000, 'BOB', NULL, NULL, 9287.72, 9287.720000, 9286.72, 9286.720000, 'ATM', 'exitosa', 'Retiro', '2026-04-23 19:25:48', '2026-04-23 19:25:48', '2026-04-23 20:50:50'),
(123, 14, NULL, 2, 12.00, 12.000000, 'BOB', NULL, NULL, 0.00, 0.000000, 12.00, 12.000000, 'ATM', 'exitosa', 'Deposito', '2026-04-23 20:02:47', '2026-04-23 20:02:47', '2026-04-23 20:50:50'),
(124, 14, NULL, 1, 9.66, 1.000000, 'USD', NULL, NULL, 9286.72, 9286.720000, 9277.06, 9277.060000, 'ATM', 'exitosa', 'Retiro', '2026-04-23 20:40:45', '2026-04-23 20:40:45', '2026-04-23 20:50:50'),
(125, 14, NULL, 1, 9.66, 1.000000, 'USD', NULL, NULL, 9277.06, 9277.060000, 9267.40, 9267.400000, 'ATM', 'exitosa', 'Retiro', '2026-04-23 20:41:34', '2026-04-23 20:41:34', '2026-04-23 20:50:50'),
(126, 14, NULL, 1, 9.66, 1.000000, 'USD', NULL, NULL, 9267.40, 9267.400000, 9257.74, 9257.740000, 'ATM', 'exitosa', 'Retiro', '2026-04-23 20:45:02', '2026-04-23 20:45:02', '2026-04-23 20:50:50'),
(127, 14, NULL, 1, 9.66, 1.000000, 'USD', NULL, NULL, 9257.74, 9257.740000, 9248.08, 9248.080000, 'ATM', 'exitosa', 'Retiro', '2026-04-23 20:46:39', '2026-04-23 20:46:39', '2026-04-23 20:50:50'),
(128, 14, NULL, 2, 500.00, 500.000000, 'BOB', 500.000000, 'BOB', 9248.08, 9248.080000, 9748.08, 9748.080000, 'ATM', 'exitosa', 'Deposito', '2026-04-23 21:02:12', '2026-04-23 21:02:12', '2026-04-23 21:02:12'),
(129, 14, NULL, 1, 1.00, 0.103520, 'USD', NULL, NULL, 9748.08, 8.000000, 9747.08, 7.896480, 'ATM', 'exitosa', 'Retiro', '2026-04-23 21:02:19', '2026-04-23 21:02:19', '2026-04-23 21:02:19'),
(130, 14, 12, 3, 100.00, 100.000000, 'BOB', 100.000000, 'BOB', 9747.08, 9747.080000, 9647.08, 9647.080000, 'ATM', 'exitosa', 'jajajja', '2026-04-23 21:05:07', '2026-04-23 21:05:07', '2026-04-23 21:05:07');

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
(8, 8, 2, 'rafaellovera@gmail.com', '$2b$10$uEQ4kNKnARDGGNQXgNdDGOi6sf6NO6n7v2M1/Dwmp7Z9TvGF1Nb3O', 'activo', '2026-03-14 13:59:22', '2026-03-14 13:59:22'),
(9, 9, 2, 'carlos.mamani@gmail.com', '$2b$10$g5hYOglaDDtiKgnEh2mJPOYaE.pd5Mn7TjFp6vsVFKlFDX0pe6E6C', 'activo', '2026-03-14 14:09:12', '2026-03-14 14:09:12'),
(10, 10, 2, 'carlos.prueba@gmail.com', '$2b$10$hT6oV3LKueQWw6VeiLy90u1hH1YEYzS47qGKLM8M1Tc1OAGw60fHq', 'activo', '2026-03-14 16:50:19', '2026-03-14 16:50:19'),
(14, 14, 2, 'rafaelignaciolovera@gmail.com', '$2b$10$Q.G6z1DefpKy/.saJVounO5r7dWe9KU5JUCybA8swy5U58pH8u/pu', 'activo', '2026-04-17 16:17:22', '2026-04-17 16:17:22'),
(16, 16, 2, 'jazielarmandovargaschoque@gmail.com', '$2b$10$C3tjo1KOV8J9KOp7/g7q6O5VrSfIhz2SZX3iIigVjZ.tajGJ6fEcS', 'activo', '2026-04-17 16:41:56', '2026-04-17 16:41:56'),
(17, 17, 2, 'j.v.36977714@gmail.com', '$2b$10$mWhx/M3tyhPJXP.DU9ODmuk7jye9BL3FAfvheau7y.idZzH.KdNWO', 'activo', '2026-04-18 14:47:32', '2026-04-18 14:47:32');

-- --------------------------------------------------------

--
-- Estructura Stand-in para la vista `vista_cuentas_resumen`
-- (Véase abajo para la vista actual)
--
CREATE TABLE `vista_cuentas_resumen` (
`cuenta_id` int(11)
,`Numero_cuenta` varchar(20)
,`Tipo_cuenta` enum('ahorro','corriente')
,`saldo_bob` decimal(20,2)
,`estado_cuenta` enum('activa','bloqueada','cerrada')
,`fecha_apertura` datetime
,`usuario_id` int(11)
,`nombre_titular` varchar(201)
,`Correo` varchar(150)
,`Numero_tarjeta` varchar(16)
,`Tipo_tarjeta` enum('debito','credito')
,`estado_tarjeta` enum('activa','bloqueada','vencida','cancelada')
,`Fecha_vencimiento` date
,`Codigo_moneda` varchar(10)
,`saldo_moneda` decimal(20,2)
,`Es_principal` tinyint(1)
,`orden_cuenta` tinyint(4)
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
,`Monto_original` decimal(20,6)
,`Moneda_origen` varchar(10)
,`Monto_destino` decimal(20,6)
,`Moneda_destino` varchar(10)
,`Saldo_anterior` decimal(15,2)
,`Saldo_posterior` decimal(15,2)
,`Saldo_anterior_original` decimal(20,6)
,`Saldo_posterior_original` decimal(20,6)
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

CREATE ALGORITHM=UNDEFINED DEFINER=`root`@`localhost` SQL SECURITY DEFINER VIEW `vista_cuentas_resumen`  AS SELECT `c`.`ID` AS `cuenta_id`, `c`.`Numero_cuenta` AS `Numero_cuenta`, `c`.`Tipo_cuenta` AS `Tipo_cuenta`, ifnull(`sm`.`Saldo`,0) AS `saldo_bob`, `c`.`Estado` AS `estado_cuenta`, `c`.`Fecha_creacion` AS `fecha_apertura`, `u`.`ID` AS `usuario_id`, concat(`p`.`Nombre`,' ',`p`.`Apellido`) AS `nombre_titular`, `u`.`Correo` AS `Correo`, `tar`.`Numero_tarjeta` AS `Numero_tarjeta`, `tar`.`Tipo_tarjeta` AS `Tipo_tarjeta`, `tar`.`Estado` AS `estado_tarjeta`, `tar`.`Fecha_vencimiento` AS `Fecha_vencimiento`, `m`.`Codigo` AS `Codigo_moneda`, ifnull(`sm`.`Saldo`,0) AS `saldo_moneda`, `tc`.`Es_principal` AS `Es_principal`, `tc`.`Orden` AS `orden_cuenta` FROM ((((((`cuenta` `c` join `users` `u` on(`c`.`ID_Users` = `u`.`ID`)) join `persona` `p` on(`u`.`ID_Persona` = `p`.`ID`)) left join `tarjeta_cuenta` `tc` on(`tc`.`ID_Cuenta` = `c`.`ID`)) left join `tarjeta` `tar` on(`tar`.`ID` = `tc`.`ID_Tarjeta`)) left join `saldo_moneda` `sm` on(`sm`.`ID_Cuenta` = `c`.`ID`)) left join `moneda` `m` on(`sm`.`ID_Moneda` = `m`.`ID`)) ;

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

CREATE ALGORITHM=UNDEFINED DEFINER=`root`@`localhost` SQL SECURITY DEFINER VIEW `vista_transacciones_completo`  AS SELECT `t`.`ID` AS `transaccion_id`, `t`.`ID_Tipo_Transaccion` AS `ID_Tipo_Transaccion`, `t`.`Fecha_transaccion` AS `Fecha_transaccion`, `t`.`Monto` AS `Monto`, `t`.`Monto_original` AS `Monto_original`, `t`.`Moneda_origen` AS `Moneda_origen`, `t`.`Monto_destino` AS `Monto_destino`, `t`.`Moneda_destino` AS `Moneda_destino`, `t`.`Saldo_anterior` AS `Saldo_anterior`, `t`.`Saldo_posterior` AS `Saldo_posterior`, `t`.`Saldo_anterior_original` AS `Saldo_anterior_original`, `t`.`Saldo_posterior_original` AS `Saldo_posterior_original`, `t`.`Metodo_transaccion` AS `Metodo_transaccion`, `t`.`Estado` AS `estado_transaccion`, `t`.`Descripcion` AS `Descripcion`, `tt`.`Nombre` AS `tipo_transaccion`, `co`.`Numero_cuenta` AS `cuenta_origen`, `co`.`Tipo_cuenta` AS `tipo_cuenta_origen`, `uo`.`ID` AS `usuario_id`, concat(`po`.`Nombre`,' ',`po`.`Apellido`) AS `nombre_remitente`, `uo`.`Correo` AS `correo_remitente`, `cd`.`Numero_cuenta` AS `cuenta_destino`, concat(`pd`.`Nombre`,' ',`pd`.`Apellido`) AS `nombre_destinatario`, `ud`.`Correo` AS `correo_destinatario` FROM (((((((`transacciones` `t` join `tipo_transaccion` `tt` on(`t`.`ID_Tipo_Transaccion` = `tt`.`ID`)) join `cuenta` `co` on(`t`.`ID_Cuenta_Transfiere` = `co`.`ID`)) join `users` `uo` on(`co`.`ID_Users` = `uo`.`ID`)) join `persona` `po` on(`uo`.`ID_Persona` = `po`.`ID`)) left join `cuenta` `cd` on(`t`.`ID_Cuenta_Transferida` = `cd`.`ID`)) left join `users` `ud` on(`cd`.`ID_Users` = `ud`.`ID`)) left join `persona` `pd` on(`ud`.`ID_Persona` = `pd`.`ID`)) ;

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
-- Indices de la tabla `cambio`
--
ALTER TABLE `cambio`
  ADD PRIMARY KEY (`ID`),
  ADD KEY `fk_cambio_cuenta` (`ID_Cuenta`),
  ADD KEY `fk_cambio_moneda_origen` (`Moneda_origen`),
  ADD KEY `fk_cambio_moneda_destino` (`Moneda_destino`);

--
-- Indices de la tabla `cuenta`
--
ALTER TABLE `cuenta`
  ADD PRIMARY KEY (`ID`),
  ADD UNIQUE KEY `Numero_cuenta` (`Numero_cuenta`),
  ADD KEY `idx_cuenta_numero` (`Numero_cuenta`),
  ADD KEY `fk_cuenta_users_casc` (`ID_Users`);

--
-- Indices de la tabla `moneda`
--
ALTER TABLE `moneda`
  ADD PRIMARY KEY (`ID`),
  ADD UNIQUE KEY `uk_codigo` (`Codigo`);

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
-- Indices de la tabla `saldo_moneda`
--
ALTER TABLE `saldo_moneda`
  ADD PRIMARY KEY (`ID`),
  ADD UNIQUE KEY `uk_cuenta_moneda` (`ID_Cuenta`,`ID_Moneda`),
  ADD KEY `fk_sm_moneda` (`ID_Moneda`);

--
-- Indices de la tabla `sesion_atm`
--
ALTER TABLE `sesion_atm`
  ADD PRIMARY KEY (`ID`),
  ADD KEY `fk_sesion_tarjeta_casc` (`ID_Tarjeta`),
  ADD KEY `fk_sesion_users_casc` (`ID_Users`);

--
-- Indices de la tabla `tarjeta`
--
ALTER TABLE `tarjeta`
  ADD PRIMARY KEY (`ID`),
  ADD UNIQUE KEY `Numero_tarjeta` (`Numero_tarjeta`),
  ADD KEY `idx_tarjeta_numero` (`Numero_tarjeta`),
  ADD KEY `fk_tarjeta_users_casc` (`ID_Users`);

--
-- Indices de la tabla `tarjeta_cuenta`
--
ALTER TABLE `tarjeta_cuenta`
  ADD PRIMARY KEY (`ID`),
  ADD UNIQUE KEY `uk_tarjeta_cuenta` (`ID_Tarjeta`,`ID_Cuenta`),
  ADD UNIQUE KEY `uk_tarjeta_orden` (`ID_Tarjeta`,`Orden`),
  ADD KEY `fk_tc_cuenta` (`ID_Cuenta`);

--
-- Indices de la tabla `tasa_cambio`
--
ALTER TABLE `tasa_cambio`
  ADD PRIMARY KEY (`ID`),
  ADD UNIQUE KEY `uk_monedas` (`Moneda_origen`,`Moneda_destino`);

--
-- Indices de la tabla `tasa_cambio_cache`
--
ALTER TABLE `tasa_cambio_cache`
  ADD PRIMARY KEY (`ID`),
  ADD UNIQUE KEY `uk_par_moneda` (`Moneda_origen`,`Moneda_destino`,`Tipo_tasa`);

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
  ADD KEY `idx_transacciones_fecha` (`Fecha_transaccion`),
  ADD KEY `fk_trans_cuenta_origen_casc` (`ID_Cuenta_Transfiere`),
  ADD KEY `fk_trans_cuenta_destino_null` (`ID_Cuenta_Transferida`),
  ADD KEY `fk_trans_tipo_restr` (`ID_Tipo_Transaccion`);

--
-- Indices de la tabla `users`
--
ALTER TABLE `users`
  ADD PRIMARY KEY (`ID`),
  ADD UNIQUE KEY `Correo` (`Correo`),
  ADD KEY `idx_users_correo` (`Correo`),
  ADD KEY `fk_users_persona_casc` (`ID_Persona`),
  ADD KEY `fk_users_rol_restr` (`ID_Rol`);

--
-- AUTO_INCREMENT de las tablas volcadas
--

--
-- AUTO_INCREMENT de la tabla `cambio`
--
ALTER TABLE `cambio`
  MODIFY `ID` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT de la tabla `cuenta`
--
ALTER TABLE `cuenta`
  MODIFY `ID` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=16;

--
-- AUTO_INCREMENT de la tabla `moneda`
--
ALTER TABLE `moneda`
  MODIFY `ID` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=9;

--
-- AUTO_INCREMENT de la tabla `persona`
--
ALTER TABLE `persona`
  MODIFY `ID` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=18;

--
-- AUTO_INCREMENT de la tabla `rol`
--
ALTER TABLE `rol`
  MODIFY `ID` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=4;

--
-- AUTO_INCREMENT de la tabla `saldo_moneda`
--
ALTER TABLE `saldo_moneda`
  MODIFY `ID` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=23;

--
-- AUTO_INCREMENT de la tabla `sesion_atm`
--
ALTER TABLE `sesion_atm`
  MODIFY `ID` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT de la tabla `tarjeta`
--
ALTER TABLE `tarjeta`
  MODIFY `ID` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=16;

--
-- AUTO_INCREMENT de la tabla `tarjeta_cuenta`
--
ALTER TABLE `tarjeta_cuenta`
  MODIFY `ID` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=7;

--
-- AUTO_INCREMENT de la tabla `tasa_cambio`
--
ALTER TABLE `tasa_cambio`
  MODIFY `ID` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=3;

--
-- AUTO_INCREMENT de la tabla `tasa_cambio_cache`
--
ALTER TABLE `tasa_cambio_cache`
  MODIFY `ID` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=138;

--
-- AUTO_INCREMENT de la tabla `tipo_transaccion`
--
ALTER TABLE `tipo_transaccion`
  MODIFY `ID` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=6;

--
-- AUTO_INCREMENT de la tabla `transacciones`
--
ALTER TABLE `transacciones`
  MODIFY `ID` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=131;

--
-- AUTO_INCREMENT de la tabla `users`
--
ALTER TABLE `users`
  MODIFY `ID` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=18;

--
-- Restricciones para tablas volcadas
--

--
-- Filtros para la tabla `cambio`
--
ALTER TABLE `cambio`
  ADD CONSTRAINT `fk_cambio_cuenta` FOREIGN KEY (`ID_Cuenta`) REFERENCES `cuenta` (`ID`) ON DELETE CASCADE ON UPDATE CASCADE;

--
-- Filtros para la tabla `cuenta`
--
ALTER TABLE `cuenta`
  ADD CONSTRAINT `fk_cuenta_users_casc` FOREIGN KEY (`ID_Users`) REFERENCES `users` (`ID`) ON DELETE CASCADE ON UPDATE CASCADE;

--
-- Filtros para la tabla `saldo_moneda`
--
ALTER TABLE `saldo_moneda`
  ADD CONSTRAINT `fk_sm_cuenta` FOREIGN KEY (`ID_Cuenta`) REFERENCES `cuenta` (`ID`) ON DELETE CASCADE ON UPDATE CASCADE,
  ADD CONSTRAINT `fk_sm_moneda` FOREIGN KEY (`ID_Moneda`) REFERENCES `moneda` (`ID`) ON UPDATE CASCADE;

--
-- Filtros para la tabla `sesion_atm`
--
ALTER TABLE `sesion_atm`
  ADD CONSTRAINT `fk_sesion_tarjeta_casc` FOREIGN KEY (`ID_Tarjeta`) REFERENCES `tarjeta` (`ID`) ON DELETE CASCADE ON UPDATE CASCADE,
  ADD CONSTRAINT `fk_sesion_users_casc` FOREIGN KEY (`ID_Users`) REFERENCES `users` (`ID`) ON DELETE CASCADE ON UPDATE CASCADE;

--
-- Filtros para la tabla `tarjeta`
--
ALTER TABLE `tarjeta`
  ADD CONSTRAINT `fk_tarjeta_users_casc` FOREIGN KEY (`ID_Users`) REFERENCES `users` (`ID`) ON DELETE CASCADE ON UPDATE CASCADE;

--
-- Filtros para la tabla `tarjeta_cuenta`
--
ALTER TABLE `tarjeta_cuenta`
  ADD CONSTRAINT `fk_tc_cuenta_fk` FOREIGN KEY (`ID_Cuenta`) REFERENCES `cuenta` (`ID`) ON DELETE CASCADE ON UPDATE CASCADE,
  ADD CONSTRAINT `fk_tc_tarjeta` FOREIGN KEY (`ID_Tarjeta`) REFERENCES `tarjeta` (`ID`) ON DELETE CASCADE ON UPDATE CASCADE;

--
-- Filtros para la tabla `transacciones`
--
ALTER TABLE `transacciones`
  ADD CONSTRAINT `fk_trans_cuenta_destino_null` FOREIGN KEY (`ID_Cuenta_Transferida`) REFERENCES `cuenta` (`ID`) ON DELETE SET NULL ON UPDATE CASCADE,
  ADD CONSTRAINT `fk_trans_cuenta_origen_casc` FOREIGN KEY (`ID_Cuenta_Transfiere`) REFERENCES `cuenta` (`ID`) ON DELETE CASCADE ON UPDATE CASCADE,
  ADD CONSTRAINT `fk_trans_tipo_restr` FOREIGN KEY (`ID_Tipo_Transaccion`) REFERENCES `tipo_transaccion` (`ID`) ON UPDATE CASCADE;

--
-- Filtros para la tabla `users`
--
ALTER TABLE `users`
  ADD CONSTRAINT `fk_users_persona_casc` FOREIGN KEY (`ID_Persona`) REFERENCES `persona` (`ID`) ON DELETE CASCADE ON UPDATE CASCADE,
  ADD CONSTRAINT `fk_users_rol_restr` FOREIGN KEY (`ID_Rol`) REFERENCES `rol` (`ID`) ON UPDATE CASCADE;
COMMIT;

/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;
