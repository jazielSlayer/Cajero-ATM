-- phpMyAdmin SQL Dump
-- version 5.2.1
-- https://www.phpmyadmin.net/
--
-- Servidor: 127.0.0.1
-- Tiempo de generación: 15-03-2026 a las 18:53:58
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
CREATE DEFINER=`root`@`localhost` PROCEDURE `sp_buscar_usuario_login` (IN `p_numero_tarjeta` VARCHAR(16))   BEGIN
    SELECT
        u.Contrasena        AS contrasena_hash,
        tar.Pin             AS pin_hash,
        r.Nombre_rol,
        u.Estado            AS estado_usuario,
        CONCAT(p.Nombre, ' ', p.Apellido) AS nombre_completo
    FROM Users u
    INNER JOIN Persona  p   ON u.ID_Persona  = p.ID
    INNER JOIN Rol      r   ON u.ID_Rol      = r.ID
    INNER JOIN Cuenta   c   ON c.ID_Users    = u.ID
    INNER JOIN Tarjeta  tar ON tar.ID_Cuenta = c.ID
    WHERE tar.Numero_tarjeta = p_numero_tarjeta
      AND u.Estado           = 'activo'
      AND tar.Estado         = 'activa'
    LIMIT 1;
END$$

CREATE DEFINER=`root`@`localhost` PROCEDURE `sp_cambiar_estado_tarjeta` (IN `p_pin` VARCHAR(255), IN `p_nombre_completo` VARCHAR(201), IN `p_nuevo_estado` ENUM('activa','bloqueada','cancelada'), OUT `p_mensaje` VARCHAR(255))   BEGIN
    DECLARE v_tarjeta_id INT;
    DECLARE v_usuario_id INT;

    -- Resolver usuario a partir del nombre completo
    SELECT vuc.usuario_id
    INTO   v_usuario_id
    FROM   vista_usuarios_completo vuc
    WHERE  vuc.nombre_completo = p_nombre_completo
    LIMIT 1;

    -- Resolver tarjeta a partir del PIN y del usuario
    SELECT tar.ID
    INTO   v_tarjeta_id
    FROM   Tarjeta tar
    INNER JOIN Cuenta c ON tar.ID_Cuenta = c.ID
    WHERE  tar.Pin      = p_pin
      AND  c.ID_Users   = v_usuario_id
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

CREATE DEFINER=`root`@`localhost` PROCEDURE `sp_datos_usuario_por_nombre` (IN `p_nombre_completo` VARCHAR(201))   BEGIN
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

CREATE DEFINER=`root`@`localhost` PROCEDURE `sp_realizar_deposito` (IN `p_correo` VARCHAR(150), IN `p_monto` DECIMAL(20,6), IN `p_id_moneda` INT, IN `p_metodo` ENUM('ATM','web','app_movil'), IN `p_contrasena` VARCHAR(255), IN `p_pin` VARCHAR(255), IN `p_tasa` DECIMAL(20,8), IN `p_tipo_tasa` ENUM('oficial','binance','manual'), OUT `p_transaccion_id` INT, OUT `p_mensaje` VARCHAR(255))   BEGIN
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

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SET p_transaccion_id = -1;
        SET p_mensaje = 'Error interno: Depósito cancelado.';
    END;

    SELECT ID INTO v_id_bob FROM moneda WHERE Codigo = 'BOB' LIMIT 1;
    SELECT Codigo INTO v_codigo_moneda FROM moneda WHERE ID = p_id_moneda LIMIT 1;

    SELECT u.ID, u.Contrasena, u.Estado
    INTO   v_usuario_id, v_contrasena_bd, v_estado_usuario
    FROM   Users u WHERE u.Correo = p_correo LIMIT 1;

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
        SELECT c.ID, c.Estado
        INTO   v_cuenta_id, v_estado_cuenta
        FROM   Cuenta c
        WHERE  c.ID_Users = v_usuario_id AND c.Estado = 'activa'
        LIMIT  1;

        -- Saldo BOB actual desde saldo_moneda
        SELECT ID, Saldo
        INTO   v_saldo_bob_id, v_saldo_bob
        FROM   saldo_moneda
        WHERE  ID_Cuenta = v_cuenta_id AND ID_Moneda = v_id_bob
        LIMIT  1;

        SELECT Pin INTO v_pin_bd
        FROM   Tarjeta
        WHERE  ID_Cuenta = v_cuenta_id AND Estado = 'activa'
        LIMIT  1;

        SELECT ID INTO v_tipo_deposito
        FROM   Tipo_Transaccion WHERE Nombre = 'Deposito';

        -- Calcular equivalente BOB
        IF p_id_moneda = v_id_bob THEN
            SET v_monto_bob = p_monto;
        ELSE
            SET v_monto_bob = p_monto * p_tasa;
        END IF;

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

            -- Actualizar o insertar saldo en la moneda depositada
            SELECT ID INTO v_saldo_mon_id
            FROM   saldo_moneda
            WHERE  ID_Cuenta = v_cuenta_id AND ID_Moneda = p_id_moneda
            LIMIT  1;

            IF v_saldo_mon_id IS NULL THEN
                INSERT INTO saldo_moneda (ID_Cuenta, ID_Moneda, Saldo)
                VALUES (v_cuenta_id, p_id_moneda, p_monto);
            ELSE
                UPDATE saldo_moneda
                SET    Saldo = Saldo + p_monto
                WHERE  ID = v_saldo_mon_id;
            END IF;

            -- Si la moneda NO es BOB, también sumar el equivalente BOB
            IF p_id_moneda != v_id_bob THEN
                IF v_saldo_bob_id IS NULL THEN
                    INSERT INTO saldo_moneda (ID_Cuenta, ID_Moneda, Saldo)
                    VALUES (v_cuenta_id, v_id_bob, v_monto_bob);
                ELSE
                    UPDATE saldo_moneda
                    SET    Saldo = Saldo + v_monto_bob
                    WHERE  ID = v_saldo_bob_id;
                END IF;
            END IF;

            INSERT INTO Transacciones (
                ID_Cuenta_Transfiere, ID_Tipo_Transaccion, Monto,
                Saldo_anterior, Saldo_posterior, Metodo_transaccion, Estado, Descripcion
            ) VALUES (
                v_cuenta_id, v_tipo_deposito, v_monto_bob,
                IFNULL(v_saldo_bob, 0),
                IFNULL(v_saldo_bob, 0) + v_monto_bob,
                p_metodo, 'exitosa',
                CONCAT('Depósito en ', v_codigo_moneda, ' | Tasa ', p_tipo_tasa, ': ', p_tasa)
            );

            SET p_transaccion_id = LAST_INSERT_ID();
            COMMIT;
            SET p_mensaje = CONCAT(
                'Depósito exitoso. Monto: ', p_monto, ' ', v_codigo_moneda,
                ' | Equivalente BOB: ', ROUND(v_monto_bob, 2),
                ' | Nuevo saldo BOB: ', ROUND(IFNULL(v_saldo_bob, 0) + v_monto_bob, 2)
            );
        END IF;
    END IF;
END$$

CREATE DEFINER=`root`@`localhost` PROCEDURE `sp_realizar_deposito_multimoneda` (IN `p_correo` VARCHAR(150), IN `p_monto_origen` DECIMAL(20,6), IN `p_id_moneda_origen` INT, IN `p_monto_destino` DECIMAL(20,6), IN `p_id_moneda_destino` INT, IN `p_metodo` ENUM('ATM','web','app_movil'), IN `p_contrasena` VARCHAR(255), IN `p_pin` VARCHAR(255), IN `p_tasa` DECIMAL(20,8), IN `p_tipo_tasa` ENUM('oficial','binance','manual'), OUT `p_transaccion_id` INT, OUT `p_mensaje` VARCHAR(255))   BEGIN
    DECLARE v_cuenta_id      INT;
    DECLARE v_saldo_bob      DECIMAL(20,6) DEFAULT 0;
    DECLARE v_usuario_id     INT;
    DECLARE v_contrasena_bd  VARCHAR(255);
    DECLARE v_estado_usuario VARCHAR(20);
    DECLARE v_pin_bd         VARCHAR(255);
    DECLARE v_tipo_deposito  INT;
    DECLARE v_monto_bob      DECIMAL(20,6);
    DECLARE v_saldo_dest_id  INT;
    DECLARE v_saldo_bob_id   INT;
    DECLARE v_saldo_dest_actual DECIMAL(20,6) DEFAULT 0;
    DECLARE v_codigo_origen  VARCHAR(10);
    DECLARE v_codigo_destino VARCHAR(10);
    DECLARE v_id_bob         INT;

    -- ¿Hay conversión real entre monedas distintas?
    DECLARE v_hay_conversion TINYINT(1) DEFAULT 0;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SET p_transaccion_id = -1;
        SET p_mensaje = 'Error interno: Depósito cancelado.';
    END;

    SELECT ID     INTO v_id_bob          FROM moneda WHERE Codigo = 'BOB' LIMIT 1;
    SELECT Codigo INTO v_codigo_origen   FROM moneda WHERE ID = p_id_moneda_origen  LIMIT 1;
    SELECT Codigo INTO v_codigo_destino  FROM moneda WHERE ID = p_id_moneda_destino LIMIT 1;

    -- ¿Conversión real?
    SET v_hay_conversion = IF(p_id_moneda_origen != p_id_moneda_destino, 1, 0);

    SELECT u.ID, u.Contrasena, u.Estado
    INTO   v_usuario_id, v_contrasena_bd, v_estado_usuario
    FROM   Users u WHERE u.Correo = p_correo LIMIT 1;

    IF v_usuario_id IS NULL THEN
        SET p_transaccion_id = -1; SET p_mensaje = 'Error: Usuario no encontrado.';
    ELSEIF v_estado_usuario != 'activo' THEN
        SET p_transaccion_id = -1; SET p_mensaje = 'Error: El usuario no está activo.';
    ELSEIF v_contrasena_bd != p_contrasena THEN
        SET p_transaccion_id = -1; SET p_mensaje = 'Error: Contraseña incorrecta.';
    ELSE
        SELECT c.ID INTO v_cuenta_id
        FROM   Cuenta c WHERE c.ID_Users = v_usuario_id AND c.Estado = 'activa' LIMIT 1;

        -- Saldo BOB actual (solo relevante si hay conversión)
        SELECT ID, Saldo INTO v_saldo_bob_id, v_saldo_bob
        FROM   saldo_moneda
        WHERE  ID_Cuenta = v_cuenta_id AND ID_Moneda = v_id_bob LIMIT 1;

        SELECT tar.Pin INTO v_pin_bd
        FROM   Tarjeta tar WHERE tar.ID_Cuenta = v_cuenta_id AND tar.Estado = 'activa' LIMIT 1;

        SELECT ID INTO v_tipo_deposito FROM Tipo_Transaccion WHERE Nombre = 'Deposito';

        -- Equivalente BOB del depósito
        IF p_id_moneda_origen = v_id_bob THEN
            SET v_monto_bob = p_monto_origen;
        ELSE
            SET v_monto_bob = p_monto_origen * p_tasa;
        END IF;

        IF v_cuenta_id IS NULL THEN
            SET p_transaccion_id = -1; SET p_mensaje = 'Error: No se encontró cuenta activa.';
        ELSEIF v_pin_bd IS NULL THEN
            SET p_transaccion_id = -1; SET p_mensaje = 'Error: No se encontró tarjeta activa.';
        ELSEIF v_pin_bd != p_pin THEN
            SET p_transaccion_id = -1; SET p_mensaje = 'Error: PIN incorrecto.';
        ELSEIF p_monto_origen <= 0 THEN
            SET p_transaccion_id = -1; SET p_mensaje = 'Error: El monto debe ser mayor a 0.';
        ELSE
            START TRANSACTION;

            -- Saldo actual en moneda destino (para el mensaje)
            SELECT ID, Saldo INTO v_saldo_dest_id, v_saldo_dest_actual
            FROM   saldo_moneda
            WHERE  ID_Cuenta = v_cuenta_id AND ID_Moneda = p_id_moneda_destino LIMIT 1;

            -- Acreditar moneda destino
            IF v_saldo_dest_id IS NULL THEN
                INSERT INTO saldo_moneda (ID_Cuenta, ID_Moneda, Saldo)
                VALUES (v_cuenta_id, p_id_moneda_destino, p_monto_destino);
            ELSE
                UPDATE saldo_moneda
                SET    Saldo = Saldo + p_monto_destino
                WHERE  ID = v_saldo_dest_id;
            END IF;

            -- ▸ CAMBIO: actualizar BOB espejo SOLO si hay conversión real
            --   y la moneda destino no es BOB
            IF v_hay_conversion = 1 AND p_id_moneda_destino != v_id_bob THEN
                IF v_saldo_bob_id IS NULL THEN
                    INSERT INTO saldo_moneda (ID_Cuenta, ID_Moneda, Saldo)
                    VALUES (v_cuenta_id, v_id_bob, v_monto_bob);
                ELSE
                    UPDATE saldo_moneda
                    SET    Saldo = Saldo + v_monto_bob
                    WHERE  ID = v_saldo_bob_id;
                END IF;
            END IF;

            -- Registrar transacción
            -- Saldo anterior y posterior en la moneda real del depósito
            INSERT INTO Transacciones (
                ID_Cuenta_Transfiere, ID_Tipo_Transaccion, Monto,
                Saldo_anterior, Saldo_posterior, Metodo_transaccion, Estado, Descripcion
            ) VALUES (
                v_cuenta_id, v_tipo_deposito,
                -- Monto en BOB solo si es conversión, si no en la moneda real
                IF(v_hay_conversion = 1, v_monto_bob, p_monto_destino),
                IFNULL(v_saldo_dest_actual, 0),
                IFNULL(v_saldo_dest_actual, 0) + p_monto_destino,
                p_metodo, 'exitosa',
                IF(v_hay_conversion = 1,
                    CONCAT('Depósito ', p_monto_origen, ' ', v_codigo_origen,
                           ' → ', p_monto_destino, ' ', v_codigo_destino,
                           ' | Tasa ', p_tipo_tasa, ': ', p_tasa),
                    CONCAT('Depósito directo ', p_monto_destino, ' ', v_codigo_destino)
                )
            );

            SET p_transaccion_id = LAST_INSERT_ID();
            COMMIT;

            -- Mensaje con saldo en la moneda REAL (no siempre BOB)
            SET p_mensaje = IF(v_hay_conversion = 1,
                CONCAT(
                    'Depósito exitoso. ',
                    p_monto_origen, ' ', v_codigo_origen,
                    ' → acreditado: ', p_monto_destino, ' ', v_codigo_destino,
                    ' | Equiv. BOB sumado: ', ROUND(v_monto_bob, 2),
                    ' | Nuevo saldo BOB: ', ROUND(IFNULL(v_saldo_bob, 0) + v_monto_bob, 2)
                ),
                CONCAT(
                    'Depósito exitoso. ', p_monto_destino, ' ', v_codigo_destino,
                    ' | Nuevo saldo ', v_codigo_destino, ': ',
                    ROUND(IFNULL(v_saldo_dest_actual, 0) + p_monto_destino, 6)
                )
            );
        END IF;
    END IF;
END$$

CREATE DEFINER=`root`@`localhost` PROCEDURE `sp_realizar_retiro` (IN `p_pin` VARCHAR(255), IN `p_monto` DECIMAL(20,6), IN `p_id_moneda` INT, IN `p_metodo` ENUM('ATM','web','app_movil'), IN `p_tasa` DECIMAL(20,8), IN `p_tipo_tasa` ENUM('oficial','binance','manual'), OUT `p_transaccion_id` INT, OUT `p_mensaje` VARCHAR(255))   BEGIN
    DECLARE v_cuenta_id      INT;
    DECLARE v_saldo_bob      DECIMAL(20,6) DEFAULT 0;
    DECLARE v_tipo_retiro    INT;
    DECLARE v_monto_bob      DECIMAL(20,6);
    DECLARE v_saldo_mon_id   INT;
    DECLARE v_saldo_moneda   DECIMAL(20,6) DEFAULT 0;
    DECLARE v_saldo_bob_id   INT;
    DECLARE v_codigo_moneda  VARCHAR(10);
    DECLARE v_id_bob         INT;

    -- ¿El retiro implica conversión? Solo si la moneda no es BOB
    -- y no hay saldo suficiente en esa moneda (lo maneja el JS,
    -- aquí registramos si debemos descontar BOB espejo).
    -- En retiro directo (tiene saldo en la moneda pedida) NO se toca BOB.
    DECLARE v_es_retiro_directo TINYINT(1) DEFAULT 1;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SET p_transaccion_id = -1;
        SET p_mensaje = 'Error interno: Retiro cancelado.';
    END;

    SELECT ID     INTO v_id_bob        FROM moneda WHERE Codigo = 'BOB' LIMIT 1;
    SELECT Codigo INTO v_codigo_moneda FROM moneda WHERE ID = p_id_moneda LIMIT 1;

    SELECT c.ID INTO v_cuenta_id
    FROM   Tarjeta tar
    INNER JOIN Cuenta c ON tar.ID_Cuenta = c.ID
    WHERE  tar.Pin = p_pin AND tar.Estado = 'activa' AND c.Estado = 'activa'
    LIMIT 1;

    SELECT ID INTO v_tipo_retiro FROM Tipo_Transaccion WHERE Nombre = 'Retiro';

    -- Saldo en la moneda solicitada
    SELECT ID, Saldo INTO v_saldo_mon_id, v_saldo_moneda
    FROM   saldo_moneda
    WHERE  ID_Cuenta = v_cuenta_id AND ID_Moneda = p_id_moneda LIMIT 1;

    -- Saldo BOB (para auditoría y para el caso de conversión)
    SELECT ID, Saldo INTO v_saldo_bob_id, v_saldo_bob
    FROM   saldo_moneda
    WHERE  ID_Cuenta = v_cuenta_id AND ID_Moneda = v_id_bob LIMIT 1;

    -- Calcular equivalente BOB
    IF p_id_moneda = v_id_bob THEN
        SET v_monto_bob = p_monto;
    ELSE
        SET v_monto_bob = p_monto * p_tasa;
    END IF;

    -- ¿Es retiro directo? Sí si tiene saldo suficiente en la moneda pedida.
    -- Es conversión si NO tiene saldo y se descuenta de BOB.
    IF p_id_moneda != v_id_bob AND (v_saldo_mon_id IS NULL OR v_saldo_moneda < p_monto) THEN
        SET v_es_retiro_directo = 0; -- conversión: usará BOB
    END IF;

    -- ── Validaciones ─────────────────────────────────────────────────────────
    IF v_cuenta_id IS NULL THEN
        SET p_transaccion_id = -1;
        SET p_mensaje = 'Error: No se encontró cuenta activa para ese PIN.';

    ELSEIF p_monto <= 0 THEN
        SET p_transaccion_id = -1;
        SET p_mensaje = 'Error: El monto debe ser mayor a 0.';

    ELSEIF v_es_retiro_directo = 1 THEN
        -- Validar saldo directo
        IF v_saldo_mon_id IS NULL THEN
            SET p_transaccion_id = -1;
            SET p_mensaje = CONCAT('Error: No tiene saldo registrado en ', v_codigo_moneda, '.');
        ELSEIF v_saldo_moneda < p_monto THEN
            SET p_transaccion_id = -1;
            SET p_mensaje = CONCAT('Error: Saldo insuficiente en ', v_codigo_moneda,
                                   '. Disponible: ', v_saldo_moneda);
        ELSE
            -- ── Retiro directo ────────────────────────────────────────────────
            START TRANSACTION;

            UPDATE saldo_moneda SET Saldo = Saldo - p_monto WHERE ID = v_saldo_mon_id;

            -- Si la moneda no es BOB, también descontar el espejo BOB
            -- SOLO si el espejo existe (fue acreditado al depositar)
            IF p_id_moneda != v_id_bob AND v_saldo_bob_id IS NOT NULL AND v_saldo_bob >= v_monto_bob THEN
                UPDATE saldo_moneda SET Saldo = Saldo - v_monto_bob WHERE ID = v_saldo_bob_id;
            END IF;

            INSERT INTO Transacciones (
                ID_Cuenta_Transfiere, ID_Tipo_Transaccion, Monto,
                Saldo_anterior, Saldo_posterior, Metodo_transaccion, Estado, Descripcion
            ) VALUES (
                v_cuenta_id, v_tipo_retiro, v_monto_bob,
                IFNULL(v_saldo_bob, v_saldo_moneda),
                IFNULL(v_saldo_bob, v_saldo_moneda) - v_monto_bob,
                p_metodo, 'exitosa',
                CONCAT('Retiro directo en ', v_codigo_moneda, ' | Tasa ', p_tipo_tasa, ': ', p_tasa)
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
        -- ── Conversión desde BOB (no tiene saldo en la moneda pedida) ─────────
        IF v_saldo_bob_id IS NULL OR v_saldo_bob < v_monto_bob THEN
            SET p_transaccion_id = -1;
            SET p_mensaje = CONCAT('Error: Saldo BOB insuficiente. Necesita ',
                                   ROUND(v_monto_bob, 2), ' BOB. Disponible: ',
                                   IFNULL(v_saldo_bob, 0));
        ELSE
            START TRANSACTION;

            UPDATE saldo_moneda SET Saldo = Saldo - v_monto_bob WHERE ID = v_saldo_bob_id;

            INSERT INTO Transacciones (
                ID_Cuenta_Transfiere, ID_Tipo_Transaccion, Monto,
                Saldo_anterior, Saldo_posterior, Metodo_transaccion, Estado, Descripcion
            ) VALUES (
                v_cuenta_id, v_tipo_retiro, v_monto_bob,
                v_saldo_bob, v_saldo_bob - v_monto_bob,
                p_metodo, 'exitosa',
                CONCAT('Retiro conv. ', p_monto, ' ', v_codigo_moneda,
                       ' desde BOB | Tasa ', p_tipo_tasa, ': ', p_tasa)
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

CREATE DEFINER=`root`@`localhost` PROCEDURE `sp_realizar_retiro_conversion` (IN `p_pin` VARCHAR(255), IN `p_monto` DECIMAL(20,6), IN `p_id_moneda` INT, IN `p_metodo` ENUM('ATM','web','app_movil'), IN `p_tasa_bob` DECIMAL(20,8), IN `p_tipo_tasa` ENUM('oficial','binance','manual'), OUT `p_transaccion_id` INT, OUT `p_mensaje` VARCHAR(255))   BEGIN
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
        SET p_mensaje = 'Error interno: Retiro con conversión cancelado.';
    END;

    SELECT ID    INTO v_id_bob        FROM moneda WHERE Codigo = 'BOB' LIMIT 1;
    SELECT Codigo INTO v_codigo_moneda FROM moneda WHERE ID = p_id_moneda LIMIT 1;

    SET v_monto_bob = p_monto * p_tasa_bob;

    SELECT c.ID INTO v_cuenta_id
    FROM   Tarjeta tar
    INNER JOIN Cuenta c ON tar.ID_Cuenta = c.ID
    WHERE  tar.Pin = p_pin AND tar.Estado = 'activa' AND c.Estado = 'activa'
    LIMIT 1;

    SELECT ID INTO v_tipo_retiro FROM Tipo_Transaccion WHERE Nombre = 'Retiro';

    SELECT ID, Saldo INTO v_saldo_bob_id, v_saldo_bob
    FROM   saldo_moneda
    WHERE  ID_Cuenta = v_cuenta_id AND ID_Moneda = v_id_bob LIMIT 1;

    IF v_cuenta_id IS NULL THEN
        SET p_transaccion_id = -1;
        SET p_mensaje = 'Error: No se encontró cuenta activa para ese PIN.';
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
            ID_Cuenta_Transfiere, ID_Tipo_Transaccion, Monto,
            Saldo_anterior, Saldo_posterior, Metodo_transaccion, Estado, Descripcion
        ) VALUES (
            v_cuenta_id, v_tipo_retiro, v_monto_bob,
            v_saldo_bob, v_saldo_bob - v_monto_bob,
            p_metodo, 'exitosa',
            CONCAT('Retiro (conv.) ', p_monto, ' ', v_codigo_moneda,
                   ' desde BOB | Tasa ', p_tipo_tasa, ': ', p_tasa_bob)
        );

        SET p_transaccion_id = LAST_INSERT_ID();
        COMMIT;
        SET p_mensaje = CONCAT(
            'Retiro exitoso (conversión). ',
            p_monto, ' ', v_codigo_moneda,
            ' | BOB descontados: ', ROUND(v_monto_bob, 2),
            ' | Saldo BOB restante: ', ROUND(v_saldo_bob - v_monto_bob, 2)
        );
    END IF;
END$$

CREATE DEFINER=`root`@`localhost` PROCEDURE `sp_realizar_transferencia` (IN `p_numero_cuenta_origen` VARCHAR(20), IN `p_numero_cuenta_destino` VARCHAR(20), IN `p_monto` DECIMAL(15,2), IN `p_metodo` ENUM('ATM','web','app_movil'), IN `p_descripcion` VARCHAR(255), OUT `p_transaccion_id` INT, OUT `p_mensaje` VARCHAR(255))   BEGIN
    DECLARE v_cuenta_origen_id   INT;
    DECLARE v_cuenta_destino_id  INT;
    DECLARE v_saldo_origen       DECIMAL(20,6) DEFAULT 0;
    DECLARE v_saldo_bob_origen_id INT;
    DECLARE v_saldo_bob_destino_id INT;
    DECLARE v_estado_origen      VARCHAR(20);
    DECLARE v_estado_destino     VARCHAR(20);
    DECLARE v_tipo_transferencia INT;
    DECLARE v_id_bob             INT;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SET p_transaccion_id = -1;
        SET p_mensaje = 'Error interno: Transferencia cancelada.';
    END;

    SELECT ID INTO v_id_bob FROM moneda WHERE Codigo = 'BOB' LIMIT 1;

    SELECT ID, Estado INTO v_cuenta_origen_id, v_estado_origen
    FROM   Cuenta WHERE Numero_cuenta = p_numero_cuenta_origen LIMIT 1;

    SELECT ID, Estado INTO v_cuenta_destino_id, v_estado_destino
    FROM   Cuenta WHERE Numero_cuenta = p_numero_cuenta_destino LIMIT 1;

    -- Saldo BOB origen
    SELECT ID, Saldo INTO v_saldo_bob_origen_id, v_saldo_origen
    FROM   saldo_moneda
    WHERE  ID_Cuenta = v_cuenta_origen_id AND ID_Moneda = v_id_bob LIMIT 1;

    -- ID saldo BOB destino
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
            Monto, Saldo_anterior, Saldo_posterior, Metodo_transaccion, Estado, Descripcion
        ) VALUES (
            v_cuenta_origen_id, v_cuenta_destino_id, v_tipo_transferencia,
            p_monto, v_saldo_origen, v_saldo_origen - p_monto,
            p_metodo, 'exitosa', p_descripcion
        );

        SET p_transaccion_id = LAST_INSERT_ID();
        COMMIT;
        SET p_mensaje = CONCAT('Transferencia exitosa. Nuevo saldo: ', v_saldo_origen - p_monto);
    END IF;
END$$

CREATE DEFINER=`root`@`localhost` PROCEDURE `sp_realizar_transferencia_multimoneda` (IN `p_numero_cuenta_origen` VARCHAR(20), IN `p_numero_cuenta_destino` VARCHAR(20), IN `p_monto_origen` DECIMAL(20,6), IN `p_id_moneda_origen` INT, IN `p_monto_destino` DECIMAL(20,6), IN `p_id_moneda_destino` INT, IN `p_metodo` ENUM('ATM','web','app_movil'), IN `p_descripcion` VARCHAR(255), IN `p_tasa_origen_bob` DECIMAL(20,8), IN `p_tasa_destino_bob` DECIMAL(20,8), IN `p_tipo_tasa` ENUM('oficial','binance','manual'), OUT `p_transaccion_id` INT, OUT `p_mensaje` VARCHAR(255))   BEGIN
    DECLARE v_cuenta_origen_id     INT;
    DECLARE v_cuenta_destino_id    INT;
    DECLARE v_saldo_origen_bob     DECIMAL(20,6) DEFAULT 0;
    DECLARE v_estado_origen        VARCHAR(20);
    DECLARE v_estado_destino       VARCHAR(20);
    DECLARE v_saldo_mon_origen_id  INT;
    DECLARE v_saldo_mon_origen     DECIMAL(20,6) DEFAULT 0;
    DECLARE v_saldo_mon_destino_id INT;
    DECLARE v_saldo_bob_origen_id  INT;
    DECLARE v_saldo_bob_destino_id INT;
    DECLARE v_tipo_transferencia   INT;
    DECLARE v_monto_bob            DECIMAL(20,6);
    DECLARE v_monto_bob_destino    DECIMAL(20,6);
    DECLARE v_codigo_origen        VARCHAR(10);
    DECLARE v_codigo_destino       VARCHAR(10);
    DECLARE v_id_bob               INT;

    -- Flag: ¿la transferencia implica conversión real de monedas?
    DECLARE v_hay_conversion       TINYINT(1) DEFAULT 0;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SET p_transaccion_id = -1;
        SET p_mensaje = 'Error interno: Transferencia cancelada.';
    END;

    SELECT ID     INTO v_id_bob          FROM moneda WHERE Codigo = 'BOB' LIMIT 1;
    SELECT Codigo INTO v_codigo_origen   FROM moneda WHERE ID = p_id_moneda_origen  LIMIT 1;
    SELECT Codigo INTO v_codigo_destino  FROM moneda WHERE ID = p_id_moneda_destino LIMIT 1;

    -- ¿Hay conversión real? Solo cuando las monedas son distintas.
    SET v_hay_conversion = IF(p_id_moneda_origen != p_id_moneda_destino, 1, 0);

    SELECT ID, Estado INTO v_cuenta_origen_id,  v_estado_origen
    FROM   Cuenta WHERE Numero_cuenta = p_numero_cuenta_origen  LIMIT 1;

    SELECT ID, Estado INTO v_cuenta_destino_id, v_estado_destino
    FROM   Cuenta WHERE Numero_cuenta = p_numero_cuenta_destino LIMIT 1;

    SELECT ID INTO v_tipo_transferencia FROM Tipo_Transaccion WHERE Nombre = 'Transferencia';

    -- Saldo en moneda origen
    SELECT ID, Saldo INTO v_saldo_mon_origen_id, v_saldo_mon_origen
    FROM   saldo_moneda
    WHERE  ID_Cuenta = v_cuenta_origen_id AND ID_Moneda = p_id_moneda_origen LIMIT 1;

    -- Saldo BOB origen (solo relevante si hay conversión)
    SELECT ID, Saldo INTO v_saldo_bob_origen_id, v_saldo_origen_bob
    FROM   saldo_moneda
    WHERE  ID_Cuenta = v_cuenta_origen_id AND ID_Moneda = v_id_bob LIMIT 1;

    -- Saldo moneda destino
    SELECT ID INTO v_saldo_mon_destino_id
    FROM   saldo_moneda
    WHERE  ID_Cuenta = v_cuenta_destino_id AND ID_Moneda = p_id_moneda_destino LIMIT 1;

    -- Saldo BOB destino
    SELECT ID INTO v_saldo_bob_destino_id
    FROM   saldo_moneda
    WHERE  ID_Cuenta = v_cuenta_destino_id AND ID_Moneda = v_id_bob LIMIT 1;

    -- Equivalente BOB del monto origen
    IF p_id_moneda_origen = v_id_bob THEN
        SET v_monto_bob = p_monto_origen;
    ELSE
        SET v_monto_bob = p_monto_origen * p_tasa_origen_bob;
    END IF;

    -- Equivalente BOB del monto destino
    IF p_id_moneda_destino = v_id_bob THEN
        SET v_monto_bob_destino = p_monto_destino;
    ELSE
        SET v_monto_bob_destino = p_monto_destino * p_tasa_destino_bob;
    END IF;

    -- ── Validaciones ─────────────────────────────────────────────────────────
    IF v_cuenta_origen_id IS NULL THEN
        SET p_transaccion_id = -1;
        SET p_mensaje = 'Error: Cuenta origen no encontrada.';

    ELSEIF v_cuenta_destino_id IS NULL THEN
        SET p_transaccion_id = -1;
        SET p_mensaje = 'Error: Cuenta destino no encontrada.';

    ELSEIF v_cuenta_origen_id = v_cuenta_destino_id THEN
        SET p_transaccion_id = -1;
        SET p_mensaje = 'Error: Origen y destino no pueden ser la misma cuenta.';

    ELSEIF v_estado_origen != 'activa' THEN
        SET p_transaccion_id = -1;
        SET p_mensaje = 'Error: La cuenta origen no está activa.';

    ELSEIF v_estado_destino != 'activa' THEN
        SET p_transaccion_id = -1;
        SET p_mensaje = 'Error: La cuenta destino no está activa.';

    ELSEIF p_monto_origen <= 0 THEN
        SET p_transaccion_id = -1;
        SET p_mensaje = 'Error: El monto debe ser mayor a 0.';

    ELSEIF v_saldo_mon_origen_id IS NULL OR v_saldo_mon_origen < p_monto_origen THEN
        SET p_transaccion_id = -1;
        SET p_mensaje = CONCAT('Error: Saldo insuficiente en ', v_codigo_origen,
                               '. Disponible: ', IFNULL(v_saldo_mon_origen, 0));

    -- ▸ CAMBIO 1: solo verificar BOB si hay conversión real entre monedas distintas
    ELSEIF v_hay_conversion = 1
        AND p_id_moneda_origen != v_id_bob
        AND (v_saldo_bob_origen_id IS NULL OR v_saldo_origen_bob < v_monto_bob) THEN
        SET p_transaccion_id = -1;
        SET p_mensaje = 'Error: Saldo BOB insuficiente en la cuenta origen.';

    ELSE
        START TRANSACTION;

        -- Descontar moneda origen
        UPDATE saldo_moneda
        SET    Saldo = Saldo - p_monto_origen
        WHERE  ID = v_saldo_mon_origen_id;

        -- ▸ CAMBIO 2: descontar BOB espejo solo si hay conversión real
        IF v_hay_conversion = 1 AND p_id_moneda_origen != v_id_bob THEN
            UPDATE saldo_moneda
            SET    Saldo = Saldo - v_monto_bob
            WHERE  ID = v_saldo_bob_origen_id;
        END IF;

        -- Acreditar moneda destino
        IF v_saldo_mon_destino_id IS NULL THEN
            INSERT INTO saldo_moneda (ID_Cuenta, ID_Moneda, Saldo)
            VALUES (v_cuenta_destino_id, p_id_moneda_destino, p_monto_destino);
        ELSE
            UPDATE saldo_moneda
            SET    Saldo = Saldo + p_monto_destino
            WHERE  ID = v_saldo_mon_destino_id;
        END IF;

        -- Acreditar BOB espejo en destino solo si hay conversión real
        IF v_hay_conversion = 1 AND p_id_moneda_destino != v_id_bob THEN
            IF v_saldo_bob_destino_id IS NULL THEN
                INSERT INTO saldo_moneda (ID_Cuenta, ID_Moneda, Saldo)
                VALUES (v_cuenta_destino_id, v_id_bob, v_monto_bob_destino);
            ELSE
                UPDATE saldo_moneda
                SET    Saldo = Saldo + v_monto_bob_destino
                WHERE  ID = v_saldo_bob_destino_id;
            END IF;
        END IF;

        INSERT INTO Transacciones (
            ID_Cuenta_Transfiere, ID_Cuenta_Transferida, ID_Tipo_Transaccion,
            Monto, Saldo_anterior, Saldo_posterior,
            Metodo_transaccion, Estado, Descripcion
        ) VALUES (
            v_cuenta_origen_id, v_cuenta_destino_id, v_tipo_transferencia,
            v_monto_bob,
            IFNULL(v_saldo_origen_bob, v_saldo_mon_origen),
            IFNULL(v_saldo_origen_bob, v_saldo_mon_origen) - v_monto_bob,
            p_metodo, 'exitosa',
            CONCAT(
                IFNULL(p_descripcion, 'Transferencia'),
                ' | ', p_monto_origen, ' ', v_codigo_origen,
                ' → ', p_monto_destino, ' ', v_codigo_destino,
                ' | Tasa ', p_tipo_tasa
            )
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

CREATE DEFINER=`root`@`localhost` PROCEDURE `sp_registrar_usuario` (IN `p_nombre` VARCHAR(100), IN `p_apellido` VARCHAR(100), IN `p_direccion` VARCHAR(255), IN `p_telefono` VARCHAR(20), IN `p_edad` INT, IN `p_correo` VARCHAR(150), IN `p_contrasena` VARCHAR(255), IN `p_id_rol` INT, IN `p_numero_cuenta` VARCHAR(20), IN `p_tipo_cuenta` ENUM('ahorro','corriente'), IN `p_saldo_inicial` DECIMAL(15,2), IN `p_numero_tarjeta` VARCHAR(16), IN `p_pin` VARCHAR(255), IN `p_tipo_tarjeta` ENUM('debito','credito'), IN `p_fecha_vencimiento` DATE, OUT `p_usuario_id` INT, OUT `p_mensaje` VARCHAR(255))   BEGIN
    DECLARE v_persona_id INT;
    DECLARE v_cuenta_id  INT;
    DECLARE v_id_bob     INT;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SET p_usuario_id = -1;
        SET p_mensaje = 'Error: No se pudo registrar el usuario. Verifique los datos.';
    END;

    IF EXISTS (SELECT 1 FROM Users WHERE Correo = p_correo) THEN
        SET p_usuario_id = -1; SET p_mensaje = 'Error: El correo ya está registrado.';
    ELSEIF EXISTS (SELECT 1 FROM Cuenta WHERE Numero_cuenta = p_numero_cuenta) THEN
        SET p_usuario_id = -1; SET p_mensaje = 'Error: El número de cuenta ya existe.';
    ELSEIF EXISTS (SELECT 1 FROM Tarjeta WHERE Numero_tarjeta = p_numero_tarjeta) THEN
        SET p_usuario_id = -1; SET p_mensaje = 'Error: El número de tarjeta ya existe.';
    ELSE
        SELECT ID INTO v_id_bob FROM moneda WHERE Codigo = 'BOB' LIMIT 1;

        START TRANSACTION;

        INSERT INTO Persona (Nombre, Apellido, Direccion, Telefono, Edad)
        VALUES (p_nombre, p_apellido, p_direccion, p_telefono, p_edad);
        SET v_persona_id = LAST_INSERT_ID();

        INSERT INTO Users (ID_Persona, ID_Rol, Correo, Contrasena)
        VALUES (v_persona_id, p_id_rol, p_correo, p_contrasena);
        SET p_usuario_id = LAST_INSERT_ID();

        -- Cuenta sin columna Saldo
        INSERT INTO Cuenta (Numero_cuenta, ID_Users, Tipo_cuenta)
        VALUES (p_numero_cuenta, p_usuario_id, p_tipo_cuenta);
        SET v_cuenta_id = LAST_INSERT_ID();

        -- Saldo inicial va en saldo_moneda
        IF p_saldo_inicial > 0 THEN
            INSERT INTO saldo_moneda (ID_Cuenta, ID_Moneda, Saldo)
            VALUES (v_cuenta_id, v_id_bob, p_saldo_inicial);
        END IF;

        INSERT INTO Tarjeta (ID_Users, ID_Cuenta, Numero_tarjeta, Pin, Tipo_tarjeta, Fecha_vencimiento)
        VALUES (p_usuario_id, v_cuenta_id, p_numero_tarjeta, p_pin, p_tipo_tarjeta, p_fecha_vencimiento);

        COMMIT;
        SET p_mensaje = 'Usuario registrado exitosamente.';
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

CREATE DEFINER=`root`@`localhost` PROCEDURE `sp_transacciones_usuario` (IN `p_nombre_completo` VARCHAR(201), IN `p_tipo_transaccion` VARCHAR(50))   BEGIN
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
(9, '3520899553795811', 11, 'ahorro', 'activa', '2026-03-14 20:40:09', '2026-03-14 20:49:17');

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
(11, 'Jaziel Armando', 'Vargas Choque', 'Calle 21 de Enero 456', '76543210', 25, '2026-03-14 20:40:09', '2026-03-14 20:40:09');

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
(10, 9, 1, 700.00, '2026-03-14 20:49:17', '2026-03-15 13:40:23'),
(11, 9, 2, 2062.45, '2026-03-14 23:00:43', '2026-03-15 13:41:56'),
(12, 6, 2, 13.00, '2026-03-15 09:43:29', '2026-03-15 09:43:29'),
(13, 9, 3, 13.79, '2026-03-15 12:27:36', '2026-03-15 12:27:36');

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
(6, 8, 6, '10000277192', '$2b$10$NuwfhS9hN6OH2TT8Kpnkk.bxMxqBdILSynacw7clvWk0wRwLw31gi', 'debito', 'activa', '2025-12-31', '2026-03-14 13:59:22', '2026-03-14 13:59:22'),
(7, 9, 7, '5500112233445566', '$2b$10$c3wUTXatKxoc8qDXsoJ5kutoMAXt5qhPlNVbLpbb1s511jEQrJYg.', 'debito', 'activa', '2031-03-14', '2026-03-14 14:09:12', '2026-03-14 14:09:12'),
(8, 10, 8, '4141978347973558', '$2b$10$CjnIb.GEQ6sZvXWWuHiXyePSJobI.rlt5ufjDr5CedHJAJ/cpKHr6', 'debito', 'activa', '2031-03-14', '2026-03-14 16:50:19', '2026-03-14 16:50:19'),
(9, 11, 9, '4520899596991226', '$2b$10$FqeDvoREWUWYrtrK7CvrOOVwopuKz1HMDODXNkno9nxHZxfyIP1IC', 'credito', 'activa', '2031-03-15', '2026-03-14 20:40:09', '2026-03-14 20:40:09');

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
(1, 'BOB', 'USD', 0.14, 'oficial', '2026-03-15 13:11:21'),
(2, 'USD', 'BOB', 6.96, 'oficial', '2026-03-15 13:11:21'),
(3, 'BOB', 'USD', 0.11, 'binance', '2026-03-15 13:11:21'),
(4, 'USD', 'BOB', 9.42, 'binance', '2026-03-15 13:11:21');

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
(14, 9, NULL, 2, 9999999999999.99, 0.00, 9999999999999.99, 'ATM', 'exitosa', 'Depósito en BOB | Tasa oficial: 1.00000000', '2026-03-14 20:49:17', '2026-03-14 20:49:17', '2026-03-14 20:49:17'),
(15, 9, NULL, 2, 9999999999999.99, 9999999999999.99, 9999999999999.99, 'ATM', 'exitosa', 'Depósito en BOB | Tasa oficial: 1.00000000', '2026-03-14 20:49:56', '2026-03-14 20:49:56', '2026-03-14 20:49:56'),
(16, 9, NULL, 1, 100.00, 9999999999999.99, 9999999999999.99, 'ATM', 'exitosa', 'Retiro directo en BOB | Tasa oficial: 1.00000000', '2026-03-14 22:52:20', '2026-03-14 22:52:20', '2026-03-14 22:52:20'),
(17, 9, NULL, 1, 100.00, 9999999999999.99, 9999999999999.99, 'ATM', 'exitosa', 'Retiro directo en BOB | Tasa oficial: 1.00000000', '2026-03-14 22:52:38', '2026-03-14 22:52:38', '2026-03-14 22:52:38'),
(18, 9, NULL, 1, 348.00, 9999999999999.99, 9999999999999.99, 'ATM', 'exitosa', 'Retiro (conv.) 50.000000 USD desde BOB | Tasa oficial: 6.96000000', '2026-03-14 22:55:13', '2026-03-14 22:55:13', '2026-03-14 22:55:13'),
(19, 9, NULL, 2, 500.00, 9999999999999.99, 9999999999999.99, 'ATM', 'exitosa', 'Depósito 500.000000 BOB → 500.000000 BOB | Tasa oficial: 1.00000000', '2026-03-14 22:57:26', '2026-03-14 22:57:26', '2026-03-14 22:57:26'),
(20, 9, NULL, 2, 100.00, 9999999999999.99, 9999999999999.99, 'ATM', 'exitosa', 'Depósito 100.000000 USD → 944.000000 BOB | Tasa binance: 9.44000000', '2026-03-14 22:58:11', '2026-03-14 22:58:11', '2026-03-14 22:58:11'),
(21, 6, 9, 3, 200.00, 1000.00, 800.00, 'ATM', 'exitosa', 'Pago de deuda | 200.000000 BOB → 200.000000 BOB | Tasa oficial', '2026-03-14 23:00:22', '2026-03-14 23:00:22', '2026-03-14 23:00:22'),
(22, 6, 9, 3, 100.00, 800.00, 700.00, 'web', 'exitosa', 'Transferencia internacional | 100.000000 BOB → 14.367816 USD | Tasa oficial', '2026-03-14 23:00:43', '2026-03-14 23:00:43', '2026-03-14 23:00:43'),
(23, 6, 9, 3, 472.00, 700.00, 228.00, 'ATM', 'exitosa', 'Conversión confirmada | 472.000000 BOB → 472.000000 BOB | Tasa binance', '2026-03-14 23:01:17', '2026-03-14 23:01:17', '2026-03-14 23:01:17'),
(24, 9, 6, 3, 471.00, 9999999999999.99, 9999999999999.99, 'ATM', 'exitosa', 'Conversión confirmada | 471.000000 BOB → 471.000000 BOB | Tasa binance', '2026-03-15 08:27:17', '2026-03-15 08:27:17', '2026-03-15 08:27:17'),
(25, 9, 6, 3, 122.46, 0.00, -122.46, 'ATM', 'exitosa', 'Conversión confirmada | 13.000000 USD → 13.000000 USD | Tasa binance', '2026-03-15 09:43:29', '2026-03-15 09:43:29', '2026-03-15 09:43:29'),
(26, 9, NULL, 1, 6.96, 0.00, -6.96, 'ATM', 'exitosa', 'Retiro directo en USD | Tasa oficial: 6.96000000', '2026-03-15 09:57:59', '2026-03-15 09:57:59', '2026-03-15 09:57:59'),
(27, 9, NULL, 2, 4710.00, 0.00, 4710.00, 'ATM', 'exitosa', 'Depósito 500.000000 USD → 500.000000 USD | Tasa binance: 9.42000000', '2026-03-15 10:01:05', '2026-03-15 10:01:05', '2026-03-15 10:01:05'),
(28, 9, NULL, 2, 500.00, 500.37, 1000.37, 'ATM', 'exitosa', 'Depósito directo 500.000000 USD', '2026-03-15 10:07:19', '2026-03-15 10:07:19', '2026-03-15 10:07:19'),
(29, 9, NULL, 2, 500.00, 1000.37, 1053.45, 'ATM', 'exitosa', 'Depósito 500.000000 BOB → 53.078556 USD | Tasa binance: 1.00000000', '2026-03-15 10:07:41', '2026-03-15 10:07:41', '2026-03-15 10:07:41'),
(30, 9, NULL, 2, 942.00, 5210.00, 6152.00, 'ATM', 'exitosa', 'Depósito 100.000000 USD → 942.000000 BOB | Tasa binance: 9.42000000', '2026-03-15 10:08:09', '2026-03-15 10:08:09', '2026-03-15 10:08:09'),
(31, 6, 9, 3, 200.00, 699.00, 499.00, 'ATM', 'exitosa', 'Pago de deuda | 200.000000 BOB → 200.000000 BOB | Tasa oficial', '2026-03-15 10:08:29', '2026-03-15 10:08:29', '2026-03-15 10:08:29'),
(32, 9, NULL, 2, 942.00, 6352.00, 7294.00, 'ATM', 'exitosa', 'Depósito 100.000000 USD → 942.000000 BOB | Tasa binance: 9.42000000', '2026-03-15 10:09:13', '2026-03-15 10:09:13', '2026-03-15 10:09:13'),
(33, 9, NULL, 2, 10.00, 1053.45, 1063.45, 'ATM', 'exitosa', 'Depósito directo 10.000000 USD', '2026-03-15 12:11:51', '2026-03-15 12:11:51', '2026-03-15 12:11:51'),
(34, 9, NULL, 2, 104.33, 0.00, 13.79, 'ATM', 'exitosa', 'Depósito 14.990000 USD → 13.790747 EUR | Tasa oficial: 6.96000000', '2026-03-15 12:27:36', '2026-03-15 12:27:36', '2026-03-15 12:27:36'),
(35, 9, NULL, 2, 500.00, 1063.45, 1563.45, 'ATM', 'exitosa', 'Depósito directo 500.000000 USD', '2026-03-15 12:49:56', '2026-03-15 12:49:56', '2026-03-15 12:49:56'),
(36, 9, NULL, 1, 6.96, 7398.33, 7391.37, 'ATM', 'exitosa', 'Retiro directo en USD | Tasa oficial: 6.96000000', '2026-03-15 13:11:21', '2026-03-15 13:11:21', '2026-03-15 13:11:21'),
(37, 9, NULL, 1, 6.96, 7391.37, 7384.41, 'ATM', 'exitosa', 'Retiro directo en BOB | Tasa oficial: 1.00000000', '2026-03-15 13:13:44', '2026-03-15 13:13:44', '2026-03-15 13:13:44'),
(38, 9, NULL, 2, 500.00, 0.00, 500.00, 'ATM', 'exitosa', 'Depósito directo 500.000000 BOB', '2026-03-15 13:20:26', '2026-03-15 13:20:26', '2026-03-15 13:20:26'),
(39, 9, NULL, 1, 500.00, 500.00, 0.00, 'ATM', 'exitosa', 'Retiro directo en BOB | Tasa oficial: 1.00000000', '2026-03-15 13:22:25', '2026-03-15 13:22:25', '2026-03-15 13:22:25'),
(40, 9, NULL, 2, 500.00, 0.00, 500.00, 'ATM', 'exitosa', 'Depósito directo 500.000000 BOB', '2026-03-15 13:28:33', '2026-03-15 13:28:33', '2026-03-15 13:28:33'),
(41, 9, NULL, 2, 500.00, 500.00, 1000.00, 'ATM', 'exitosa', 'Depósito directo 500.000000 BOB', '2026-03-15 13:39:23', '2026-03-15 13:39:23', '2026-03-15 13:39:23'),
(42, 9, NULL, 1, 500.00, 1000.00, 500.00, 'ATM', 'exitosa', 'Retiro directo en BOB | Tasa oficial: 1.00000000', '2026-03-15 13:39:49', '2026-03-15 13:39:49', '2026-03-15 13:39:49'),
(43, 6, 9, 3, 200.00, 499.00, 299.00, 'ATM', 'exitosa', 'Pago de deuda | 200.000000 BOB → 200.000000 BOB | Tasa oficial', '2026-03-15 13:40:23', '2026-03-15 13:40:23', '2026-03-15 13:40:23'),
(44, 9, NULL, 2, 500.00, 1562.45, 2062.45, 'ATM', 'exitosa', 'Depósito directo 500.000000 USD', '2026-03-15 13:41:56', '2026-03-15 13:41:56', '2026-03-15 13:41:56');

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
(11, 11, 2, 'jazielarmandovargaschoque@gmail.com', '$2b$10$KVQXrPLUUg0I3RP4etXPWeUSwqMdxhVVf4jyPf24BBrWsHkAG5.62', 'activo', '2026-03-14 20:40:09', '2026-03-14 20:40:09');

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
);

-- --------------------------------------------------------

--
-- Estructura Stand-in para la vista `vista_estadisticas_sistema`
-- (Véase abajo para la vista actual)
--
CREATE TABLE `vista_estadisticas_sistema` (
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

CREATE ALGORITHM=UNDEFINED DEFINER=`root`@`localhost` SQL SECURITY DEFINER VIEW `vista_cuentas_resumen`  AS SELECT `c`.`ID` AS `cuenta_id`, `c`.`Numero_cuenta` AS `Numero_cuenta`, `c`.`Tipo_cuenta` AS `Tipo_cuenta`, `sm`.`Saldo` AS `saldo_bob`, `c`.`Estado` AS `estado_cuenta`, `c`.`Fecha_creacion` AS `fecha_apertura`, `u`.`ID` AS `usuario_id`, concat(`p`.`Nombre`,' ',`p`.`Apellido`) AS `nombre_titular`, `u`.`Correo` AS `Correo`, `tar`.`Numero_tarjeta` AS `Numero_tarjeta`, `tar`.`Tipo_tarjeta` AS `Tipo_tarjeta`, `tar`.`Estado` AS `estado_tarjeta`, `tar`.`Fecha_vencimiento` AS `Fecha_vencimiento`, `m`.`Codigo` AS `Codigo_moneda`, `sm`.`Saldo` AS `saldo_moneda` FROM (((((`cuenta` `c` join `users` `u` on(`c`.`ID_Users` = `u`.`ID`)) join `persona` `p` on(`u`.`ID_Persona` = `p`.`ID`)) left join `tarjeta` `tar` on(`tar`.`ID_Cuenta` = `c`.`ID`)) left join `saldo_moneda` `sm` on(`sm`.`ID_Cuenta` = `c`.`ID`)) left join `moneda` `m` on(`sm`.`ID_Moneda` = `m`.`ID`)) ;

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
  ADD KEY `fk_tarjeta_users_casc` (`ID_Users`),
  ADD KEY `fk_tarjeta_cuenta_casc` (`ID_Cuenta`);

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
  MODIFY `ID` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=10;

--
-- AUTO_INCREMENT de la tabla `moneda`
--
ALTER TABLE `moneda`
  MODIFY `ID` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=9;

--
-- AUTO_INCREMENT de la tabla `persona`
--
ALTER TABLE `persona`
  MODIFY `ID` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=12;

--
-- AUTO_INCREMENT de la tabla `rol`
--
ALTER TABLE `rol`
  MODIFY `ID` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=4;

--
-- AUTO_INCREMENT de la tabla `saldo_moneda`
--
ALTER TABLE `saldo_moneda`
  MODIFY `ID` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=14;

--
-- AUTO_INCREMENT de la tabla `sesion_atm`
--
ALTER TABLE `sesion_atm`
  MODIFY `ID` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT de la tabla `tarjeta`
--
ALTER TABLE `tarjeta`
  MODIFY `ID` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=10;

--
-- AUTO_INCREMENT de la tabla `tasa_cambio`
--
ALTER TABLE `tasa_cambio`
  MODIFY `ID` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=3;

--
-- AUTO_INCREMENT de la tabla `tasa_cambio_cache`
--
ALTER TABLE `tasa_cambio_cache`
  MODIFY `ID` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=78;

--
-- AUTO_INCREMENT de la tabla `tipo_transaccion`
--
ALTER TABLE `tipo_transaccion`
  MODIFY `ID` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=6;

--
-- AUTO_INCREMENT de la tabla `transacciones`
--
ALTER TABLE `transacciones`
  MODIFY `ID` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=45;

--
-- AUTO_INCREMENT de la tabla `users`
--
ALTER TABLE `users`
  MODIFY `ID` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=12;

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
  ADD CONSTRAINT `fk_tarjeta_cuenta_casc` FOREIGN KEY (`ID_Cuenta`) REFERENCES `cuenta` (`ID`) ON DELETE CASCADE ON UPDATE CASCADE,
  ADD CONSTRAINT `fk_tarjeta_users_casc` FOREIGN KEY (`ID_Users`) REFERENCES `users` (`ID`) ON DELETE CASCADE ON UPDATE CASCADE;

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
