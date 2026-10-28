/* =============================================================================
   PROYECTO FINAL — SISTEMA DE VENTAS
   Base de Datos I · Oracle Database 21c XE
   -----------------------------------------------------------------------------
   Script completo: estructura, objetos PL/SQL, datos de prueba y verificación.

   CÓMO EJECUTARLO
   1. Conéctese con el usuario dueño del esquema (SISTEMA_VENTAS)
      en la PDB XEPDB1. NO lo ejecute como SYS.
   2. En SQL Developer presione F5 (Ejecutar script).
   3. El usuario necesita estos privilegios (otorgados por SYSDBA):
        CREATE SESSION, CREATE TABLE, CREATE VIEW, CREATE SEQUENCE,
        CREATE PROCEDURE, CREATE TRIGGER, CREATE JOB
        y cuota en el tablespace USERS (ver el ANEXO A).

   ADVERTENCIA
   La sección 1 ELIMINA las tablas y objetos del sistema para crearlos de nuevo.
   Todos los datos existentes del esquema se pierden.

   CONTENIDO
     1. Limpieza de objetos anteriores
     2. Secuencias
     3. Tablas y restricciones (PK, FK, NOT NULL, UNIQUE, CHECK)
     4. Índices
     5. Vistas
     6. Funciones
     7. Procedimientos almacenados
     8. Triggers
     9. Job programado (DBMS_SCHEDULER)
    10. Datos de prueba
    11. Consultas de verificación
    12. Pruebas de reglas de negocio y manejo de errores
    ANEXO A. DCL: roles, usuarios y privilegios de Oracle (como SYSDBA)
    ANEXO B. Respaldo y restauración con Data Pump (desde CMD)

   USUARIOS DE LA APLICACIÓN (contraseñas de prueba)
     admin_marta      / admin123     ADMINISTRADOR
     cajero1          / cajero123    CAJERO
     vendedor2        / vendedor123  VENDEDOR
     bodega_lab       / bodega123    BODEGUERO
     usuario_inactivo / inactivo123  VENDEDOR (inactivo: no puede ingresar)
   ============================================================================= */

SET DEFINE OFF
SET SERVEROUTPUT ON


-- =============================================================================
-- 1. LIMPIEZA DE OBJETOS ANTERIORES
--    Se ignoran los errores de "el objeto no existe" para que el script
--    pueda ejecutarse tanto en un esquema vacío como en uno ya usado.
-- =============================================================================
DECLARE
    TYPE t_lista IS TABLE OF VARCHAR2(60);

    v_tablas t_lista := t_lista(
        'PAGO_VENTA', 'METODO_PAGO', 'POLITICA_SANCION',
        'VALE_DESCUENTO', 'AUDITORIA_PRODUCTO', 'KARDEX', 'DETALLE_VENTA', 'VENTAS',
        'DETALLE_COMPRA', 'COMPRAS', 'DETALLE_COTIZACION', 'COTIZACION',
        'APERTURA_CAJA', 'CAJA', 'PRODUCTOS', 'PROVEEDORES', 'CLIENTES',
        'USUARIO_ROL', 'USUARIO', 'ROL');

    v_vistas t_lista := t_lista(
        'VW_SANCIONES_MES', 'VW_ANULACIONES_VENTA',
        'VW_RESUMEN_VENTAS', 'VW_PRODUCTOS_BAJO_STOCK',
        'VW_VENTAS_POR_PRODUCTO', 'VW_INCIDENCIAS_CAJA');

    v_secuencias t_lista := t_lista(
        'SEQ_USUARIO', 'SEQ_CLIENTE', 'SEQ_PROVEEDOR', 'SEQ_PRODUCTO', 'SEQ_CAJA',
        'SEQ_APERTURA', 'SEQ_COMPRA', 'SEQ_DETALLE_COMPRA', 'SEQ_VENTA',
        'SEQ_DETALLE_VENTA', 'SEQ_COTIZACION', 'SEQ_DETALLE_COTIZACION',
        'SEQ_KARDEX', 'SEQ_AUDITORIA_PRODUCTO', 'SEQ_VALE', 'SEQ_PAGO_VENTA');

    v_procedimientos t_lista := t_lista(
        'SP_REGISTRAR_CLIENTE', 'SP_REGISTRAR_DETALLE_COMPRA', 'SP_REGISTRAR_DETALLE_VENTA',
        'SP_VENTA_TRANSACCION', 'SP_PROCESAR_VENTA', 'SP_AGREGAR_DETALLE_COMPRA',
        'SP_CREAR_VENTA', 'SP_AGREGAR_DETALLE_VENTA', 'SP_AGREGAR_PAGO_VENTA',
        'SP_FINALIZAR_VENTA', 'SP_ANULAR_VENTA', 'SP_CADUCAR_COTIZACIONES',
        'SP_ABRIR_CAJA', 'SP_CERRAR_CAJA', 'SP_APLICAR_VALES_MES');

    v_funciones t_lista := t_lista(
        'FN_STOCK_PRODUCTO', 'FN_EFECTIVO_APERTURA');

    PROCEDURE eliminar(p_sentencia VARCHAR2) IS
    BEGIN
        EXECUTE IMMEDIATE p_sentencia;
    EXCEPTION
        WHEN OTHERS THEN
            -- -942: tabla o vista no existe | -2289: secuencia no existe | -4043: objeto no existe
            IF SQLCODE NOT IN (-942, -2289, -4043) THEN
                RAISE;
            END IF;
    END;
BEGIN
    -- El job programado se elimina primero (-27475: el job no existe)
    BEGIN
        DBMS_SCHEDULER.DROP_JOB('JOB_CADUCAR_COTIZACIONES', force => TRUE);
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE <> -27475 THEN
                RAISE;
            END IF;
    END;

    FOR i IN 1 .. v_vistas.COUNT LOOP
        eliminar('DROP VIEW ' || v_vistas(i));
    END LOOP;

    FOR i IN 1 .. v_procedimientos.COUNT LOOP
        eliminar('DROP PROCEDURE ' || v_procedimientos(i));
    END LOOP;

    FOR i IN 1 .. v_funciones.COUNT LOOP
        eliminar('DROP FUNCTION ' || v_funciones(i));
    END LOOP;

    -- Los triggers se eliminan junto con sus tablas
    FOR i IN 1 .. v_tablas.COUNT LOOP
        eliminar('DROP TABLE ' || v_tablas(i) || ' CASCADE CONSTRAINTS PURGE');
    END LOOP;

    FOR i IN 1 .. v_secuencias.COUNT LOOP
        eliminar('DROP SEQUENCE ' || v_secuencias(i));
    END LOOP;

    DBMS_OUTPUT.PUT_LINE('Limpieza completada.');
END;
/


-- =============================================================================
-- 2. SECUENCIAS
--    Los catálogos de prueba usan IDs fijos bajos; sus secuencias empiezan
--    en 100 para no chocar con ellos. Las operaciones usan secuencias desde 1.
-- =============================================================================
CREATE SEQUENCE SEQ_USUARIO            START WITH 100 INCREMENT BY 1 NOCACHE NOCYCLE;
CREATE SEQUENCE SEQ_CLIENTE            START WITH 100 INCREMENT BY 1 NOCACHE NOCYCLE;
CREATE SEQUENCE SEQ_PROVEEDOR          START WITH 100 INCREMENT BY 1 NOCACHE NOCYCLE;
CREATE SEQUENCE SEQ_PRODUCTO           START WITH 100 INCREMENT BY 1 NOCACHE NOCYCLE;
CREATE SEQUENCE SEQ_CAJA               START WITH 10  INCREMENT BY 1 NOCACHE NOCYCLE;
CREATE SEQUENCE SEQ_APERTURA           START WITH 1   INCREMENT BY 1 NOCACHE NOCYCLE;
CREATE SEQUENCE SEQ_COMPRA             START WITH 1   INCREMENT BY 1 NOCACHE NOCYCLE;
CREATE SEQUENCE SEQ_DETALLE_COMPRA     START WITH 1   INCREMENT BY 1 NOCACHE NOCYCLE;
CREATE SEQUENCE SEQ_VENTA              START WITH 1   INCREMENT BY 1 NOCACHE NOCYCLE;
CREATE SEQUENCE SEQ_DETALLE_VENTA      START WITH 1   INCREMENT BY 1 NOCACHE NOCYCLE;
CREATE SEQUENCE SEQ_COTIZACION         START WITH 1   INCREMENT BY 1 NOCACHE NOCYCLE;
CREATE SEQUENCE SEQ_DETALLE_COTIZACION START WITH 1   INCREMENT BY 1 NOCACHE NOCYCLE;
CREATE SEQUENCE SEQ_KARDEX             START WITH 1   INCREMENT BY 1 NOCACHE NOCYCLE;
CREATE SEQUENCE SEQ_AUDITORIA_PRODUCTO START WITH 1   INCREMENT BY 1 NOCACHE NOCYCLE;
CREATE SEQUENCE SEQ_VALE               START WITH 1   INCREMENT BY 1 NOCACHE NOCYCLE;
CREATE SEQUENCE SEQ_PAGO_VENTA         START WITH 1   INCREMENT BY 1 NOCACHE NOCYCLE;


-- =============================================================================
-- 3. TABLAS Y RESTRICCIONES
--    Se crean en orden de dependencia: primero las tablas sin llaves foráneas.
-- =============================================================================

-- ---------------------------- MÓDULO SEGURIDAD -------------------------------
CREATE TABLE ROL (
    id_rol       NUMBER(10),
    nombre_rol   VARCHAR2(50)  NOT NULL,
    descripcion  VARCHAR2(150),
    CONSTRAINT pk_rol        PRIMARY KEY (id_rol),
    CONSTRAINT uk_rol_nombre UNIQUE (nombre_rol)
);

CREATE TABLE USUARIO (
    id_usuario  NUMBER(10),
    usuario     VARCHAR2(50)   NOT NULL,
    password    VARCHAR2(255)  NOT NULL,     -- hash (scrypt), nunca texto plano
    estado      CHAR(1)        DEFAULT 'A' NOT NULL,
    CONSTRAINT pk_usuario         PRIMARY KEY (id_usuario),
    CONSTRAINT uk_usuario_usuario UNIQUE (usuario),
    CONSTRAINT chk_usuario_estado CHECK (estado IN ('A', 'I'))
);

-- Entidad asociativa: resuelve la relación muchos a muchos USUARIO <-> ROL
CREATE TABLE USUARIO_ROL (
    id_usuario  NUMBER(10),
    id_rol      NUMBER(10),
    CONSTRAINT pk_usuario_rol    PRIMARY KEY (id_usuario, id_rol),
    CONSTRAINT fk_usurol_usuario FOREIGN KEY (id_usuario) REFERENCES USUARIO(id_usuario),
    CONSTRAINT fk_usurol_rol     FOREIGN KEY (id_rol)     REFERENCES ROL(id_rol)
);

-- ---------------------------- MÓDULO PERSONAS --------------------------------
CREATE TABLE CLIENTES (
    id_cliente  NUMBER(10),
    nombre      VARCHAR2(100)  NOT NULL,
    direccion   VARCHAR2(150)  NOT NULL,
    telefono    VARCHAR2(20)   NOT NULL,
    correo      VARCHAR2(150),
    CONSTRAINT pk_clientes        PRIMARY KEY (id_cliente),
    CONSTRAINT uk_clientes_correo UNIQUE (correo)
);

CREATE TABLE PROVEEDORES (
    id_proveedor  NUMBER(10),
    nombre        VARCHAR2(100)  NOT NULL,
    direccion     VARCHAR2(150)  NOT NULL,
    telefono      VARCHAR2(20)   NOT NULL,
    nit           VARCHAR2(20)   NOT NULL,
    CONSTRAINT pk_proveedores     PRIMARY KEY (id_proveedor),
    CONSTRAINT uk_proveedores_nit UNIQUE (nit)
);

-- ---------------------------- MÓDULO INVENTARIO ------------------------------
CREATE TABLE PRODUCTOS (
    id_producto     NUMBER(10),
    nombre          VARCHAR2(100)  NOT NULL,
    precio_compra   NUMBER(12,2)   NOT NULL,
    precio_venta    NUMBER(12,2)   NOT NULL,
    stock           NUMBER(8)      DEFAULT 0 NOT NULL,
    estado          CHAR(1)        DEFAULT 'A' NOT NULL,
    fecha_registro  DATE           DEFAULT SYSDATE NOT NULL,
    stock_minimo    NUMBER(10)     DEFAULT 5 NOT NULL,
    CONSTRAINT pk_productos            PRIMARY KEY (id_producto),
    CONSTRAINT chk_productos_estado    CHECK (estado IN ('A', 'I')),
    CONSTRAINT chk_productos_stock     CHECK (stock >= 0),
    CONSTRAINT chk_productos_stock_min CHECK (stock_minimo >= 0),
    CONSTRAINT chk_productos_precios   CHECK (precio_compra > 0 AND precio_venta >= precio_compra)
);

-- ---------------------------- MÓDULO CAJA ------------------------------------
CREATE TABLE CAJA (
    id_caja  NUMBER(10),
    nombre   VARCHAR2(50)  NOT NULL,
    estado   CHAR(1)       DEFAULT 'A' NOT NULL,
    CONSTRAINT pk_caja      PRIMARY KEY (id_caja),
    CONSTRAINT chk_caja_est CHECK (estado IN ('A', 'I'))
);

CREATE TABLE APERTURA_CAJA (
    id_apertura         NUMBER(10),
    id_caja             NUMBER(10)    NOT NULL,
    id_usuario          NUMBER(10)    NOT NULL,
    fecha_apertura      DATE          DEFAULT SYSDATE NOT NULL,
    monto_inicial       NUMBER(12,2)  NOT NULL,
    fecha_cierre        DATE,
    monto_esperado      NUMBER(12,2)  DEFAULT 0,
    monto_contado       NUMBER(12,2)  DEFAULT 0,
    diferencia          NUMBER(12,2)  DEFAULT 0,
    estado              CHAR(1)       DEFAULT 'A' NOT NULL,
    observacion_cierre  VARCHAR2(200),
    CONSTRAINT pk_apertura_caja   PRIMARY KEY (id_apertura),
    CONSTRAINT fk_ape_caja        FOREIGN KEY (id_caja)    REFERENCES CAJA(id_caja),
    CONSTRAINT fk_ape_usuario     FOREIGN KEY (id_usuario) REFERENCES USUARIO(id_usuario),
    CONSTRAINT chk_ape_est        CHECK (estado IN ('A', 'C')),
    CONSTRAINT chk_ape_monto_ini  CHECK (monto_inicial >= 0),
    -- Una apertura cerrada debe tener fecha de cierre
    CONSTRAINT chk_ape_cierre     CHECK (estado = 'A' OR fecha_cierre IS NOT NULL)
);

-- ---------------------------- MÓDULO COTIZACIONES ----------------------------
CREATE TABLE COTIZACION (
    id_cotizacion      NUMBER(10),
    id_cliente         NUMBER(10)    NOT NULL,
    id_usuario         NUMBER(10)    NOT NULL,
    fecha              DATE          DEFAULT SYSDATE NOT NULL,
    fecha_vencimiento  DATE          NOT NULL,
    total              NUMBER(12,2)  DEFAULT 0 NOT NULL,
    estado             CHAR(1)       DEFAULT 'A' NOT NULL,   -- A=Abierta, C=Caducada, F=Facturada
    CONSTRAINT pk_cotizacion      PRIMARY KEY (id_cotizacion),
    CONSTRAINT fk_cotiz_cliente   FOREIGN KEY (id_cliente) REFERENCES CLIENTES(id_cliente),
    CONSTRAINT fk_cotiz_usuario   FOREIGN KEY (id_usuario) REFERENCES USUARIO(id_usuario),
    CONSTRAINT chk_cotiz_est      CHECK (estado IN ('A', 'C', 'F')),
    CONSTRAINT chk_cotiz_total    CHECK (total >= 0)
);

CREATE TABLE DETALLE_COTIZACION (
    id_detalle_cotizacion  NUMBER(10),
    id_cotizacion          NUMBER(10)    NOT NULL,
    id_producto            NUMBER(10)    NOT NULL,
    cantidad               NUMBER(8)     NOT NULL,
    precio                 NUMBER(12,2)  NOT NULL,
    subtotal               NUMBER(12,2)  NOT NULL,
    CONSTRAINT pk_detalle_cotizacion   PRIMARY KEY (id_detalle_cotizacion),
    CONSTRAINT fk_detcotiz_cotizacion  FOREIGN KEY (id_cotizacion) REFERENCES COTIZACION(id_cotizacion),
    CONSTRAINT fk_detcotiz_producto    FOREIGN KEY (id_producto)   REFERENCES PRODUCTOS(id_producto),
    CONSTRAINT chk_detcotiz_cantidad   CHECK (cantidad > 0),
    CONSTRAINT chk_detcotiz_precio     CHECK (precio > 0)
);

-- ---------------------------- MÓDULO COMPRAS (maestro–detalle) ---------------
CREATE TABLE COMPRAS (
    id_compra     NUMBER(10),
    fecha         DATE          DEFAULT SYSDATE NOT NULL,
    total         NUMBER(12,2)  DEFAULT 0 NOT NULL,
    id_proveedor  NUMBER(10)    NOT NULL,
    id_usuario    NUMBER(10)    NOT NULL,
    CONSTRAINT pk_compras           PRIMARY KEY (id_compra),
    CONSTRAINT fk_compras_proveedor FOREIGN KEY (id_proveedor) REFERENCES PROVEEDORES(id_proveedor),
    CONSTRAINT fk_compras_usuario   FOREIGN KEY (id_usuario)   REFERENCES USUARIO(id_usuario),
    CONSTRAINT chk_compras_total    CHECK (total >= 0)
);

CREATE TABLE DETALLE_COMPRA (
    id_detalle_compra  NUMBER(10),
    id_compra          NUMBER(10)    NOT NULL,
    id_producto        NUMBER(10)    NOT NULL,
    cantidad           NUMBER(8)     NOT NULL,
    precio_costo       NUMBER(12,2)  NOT NULL,
    subtotal           NUMBER(12,2)  NOT NULL,
    CONSTRAINT pk_detalle_compra       PRIMARY KEY (id_detalle_compra),
    CONSTRAINT fk_detcompra_compra     FOREIGN KEY (id_compra)   REFERENCES COMPRAS(id_compra),
    CONSTRAINT fk_detcompra_producto   FOREIGN KEY (id_producto) REFERENCES PRODUCTOS(id_producto),
    CONSTRAINT chk_detcompra_cantidad  CHECK (cantidad > 0),
    CONSTRAINT chk_detcompra_precio    CHECK (precio_costo > 0)
);

-- ---------------------------- MÓDULO VENTAS (maestro–detalle) ----------------
CREATE TABLE VENTAS (
    id_venta       NUMBER(10),
    fecha          DATE          DEFAULT SYSDATE NOT NULL,
    total          NUMBER(12,2)  DEFAULT 0 NOT NULL,
    id_cliente     NUMBER(10)    NOT NULL,
    id_usuario     NUMBER(10)    NOT NULL,
    id_apertura    NUMBER(10)    NOT NULL,     -- toda venta pertenece a una apertura de caja
    id_cotizacion  NUMBER(10),                 -- opcional: venta generada desde una cotización
    estado               CHAR(1)  DEFAULT 'A' NOT NULL,   -- A=Activa, N=Anulada
    fecha_anulacion      DATE,
    id_usuario_anula     NUMBER(10),          -- quien solicitó la anulación
    id_usuario_autoriza  NUMBER(10),          -- administrador que la autorizó
    motivo_anulacion     VARCHAR2(200),
    CONSTRAINT pk_ventas            PRIMARY KEY (id_venta),
    CONSTRAINT fk_ventas_cliente    FOREIGN KEY (id_cliente)    REFERENCES CLIENTES(id_cliente),
    CONSTRAINT fk_ventas_usuario    FOREIGN KEY (id_usuario)    REFERENCES USUARIO(id_usuario),
    CONSTRAINT fk_ventas_apertura   FOREIGN KEY (id_apertura)   REFERENCES APERTURA_CAJA(id_apertura),
    CONSTRAINT fk_ventas_cotizacion FOREIGN KEY (id_cotizacion) REFERENCES COTIZACION(id_cotizacion),
    CONSTRAINT fk_ventas_usuario_anula    FOREIGN KEY (id_usuario_anula)    REFERENCES USUARIO(id_usuario),
    CONSTRAINT fk_ventas_usuario_autoriza FOREIGN KEY (id_usuario_autoriza) REFERENCES USUARIO(id_usuario),
    -- Una cotización solo puede convertirse en UNA venta
    CONSTRAINT uk_ventas_cotizacion UNIQUE (id_cotizacion),
    CONSTRAINT chk_ventas_total     CHECK (total >= 0),
    CONSTRAINT chk_ventas_estado    CHECK (estado IN ('A', 'N')),
    -- Activa: sin datos de anulación. Anulada: con fecha, solicitante, autorizador y motivo.
    CONSTRAINT chk_ventas_anulacion CHECK (
        (estado = 'A' AND fecha_anulacion IS NULL AND id_usuario_anula IS NULL
                      AND id_usuario_autoriza IS NULL AND motivo_anulacion IS NULL)
        OR
        (estado = 'N' AND fecha_anulacion IS NOT NULL AND id_usuario_anula IS NOT NULL
                      AND id_usuario_autoriza IS NOT NULL AND motivo_anulacion IS NOT NULL))
);

CREATE TABLE DETALLE_VENTA (
    id_detalle_venta  NUMBER(10),
    id_venta          NUMBER(10)    NOT NULL,
    id_producto       NUMBER(10)    NOT NULL,
    cantidad          NUMBER(8)     NOT NULL,
    precio_venta      NUMBER(12,2)  NOT NULL,
    subtotal          NUMBER(12,2)  NOT NULL,
    CONSTRAINT pk_detalle_venta       PRIMARY KEY (id_detalle_venta),
    CONSTRAINT fk_detventa_venta      FOREIGN KEY (id_venta)    REFERENCES VENTAS(id_venta),
    CONSTRAINT fk_detventa_producto   FOREIGN KEY (id_producto) REFERENCES PRODUCTOS(id_producto),
    CONSTRAINT chk_detventa_cantidad  CHECK (cantidad > 0),
    CONSTRAINT chk_detventa_precio    CHECK (precio_venta > 0)
);

-- ---------------------------- MÓDULO KARDEX ----------------------------------
CREATE TABLE KARDEX (
    id_kardex         NUMBER(10),
    id_producto       NUMBER(10)    NOT NULL,
    fecha             DATE          DEFAULT SYSDATE NOT NULL,
    tipo_movimiento   VARCHAR2(10)  NOT NULL,
    tipo_documento    VARCHAR2(20)  NOT NULL,
    referencia        VARCHAR2(50)  NOT NULL,
    cantidad_entrada  NUMBER(8)     DEFAULT 0 NOT NULL,
    cantidad_salida   NUMBER(8)     DEFAULT 0 NOT NULL,
    existencia_final  NUMBER(8)     NOT NULL,
    id_usuario        NUMBER(10)    NOT NULL,
    CONSTRAINT pk_kardex            PRIMARY KEY (id_kardex),
    CONSTRAINT fk_kardex_producto   FOREIGN KEY (id_producto) REFERENCES PRODUCTOS(id_producto),
    CONSTRAINT fk_kardex_usuario    FOREIGN KEY (id_usuario)  REFERENCES USUARIO(id_usuario),
    CONSTRAINT chk_kardex_tipo      CHECK (tipo_movimiento IN ('ENTRADA', 'SALIDA')),
    CONSTRAINT chk_kardex_cantidad  CHECK (cantidad_entrada >= 0 AND cantidad_salida >= 0),
    CONSTRAINT chk_kardex_existencia CHECK (existencia_final >= 0),
    -- Una ENTRADA no tiene salida y una SALIDA no tiene entrada
    CONSTRAINT chk_kardex_coherencia CHECK (
        (tipo_movimiento = 'ENTRADA' AND cantidad_salida = 0) OR
        (tipo_movimiento = 'SALIDA'  AND cantidad_entrada = 0))
);

-- ---------------------------- AUDITORÍA --------------------------------------
CREATE TABLE AUDITORIA_PRODUCTO (
    id_auditoria     NUMBER(10),
    id_producto      NUMBER(10)    NOT NULL,
    precio_anterior  NUMBER(12,2),
    precio_nuevo     NUMBER(12,2),
    usuario          VARCHAR2(50)  NOT NULL,
    fecha            DATE          DEFAULT SYSDATE NOT NULL,
    tipo_operacion   VARCHAR2(20)  NOT NULL,
    CONSTRAINT pk_auditoria_producto PRIMARY KEY (id_auditoria),
    CONSTRAINT fk_audprod_producto   FOREIGN KEY (id_producto) REFERENCES PRODUCTOS(id_producto)
);

-- ---------------------------- CONTROL DE CAJA: VALES -------------------------
-- Vale de descuento por faltante en el cierre de caja (relación 1:1 con APERTURA_CAJA).
-- El usuario y el monto del faltante NO se repiten aquí: se obtienen de APERTURA_CAJA (3FN).
CREATE TABLE VALE_DESCUENTO (
    id_vale           NUMBER(10),
    id_apertura       NUMBER(10)    NOT NULL,
    monto             NUMBER(12,2)  NOT NULL,
    estado            CHAR(1)       DEFAULT 'P' NOT NULL,   -- P=Pendiente, A=Aplicado, N=Anulado
    fecha_emision     DATE          DEFAULT SYSDATE NOT NULL,
    fecha_aplicacion  DATE,
    motivo_anulacion  VARCHAR2(200),
    CONSTRAINT pk_vale_descuento PRIMARY KEY (id_vale),
    CONSTRAINT fk_vale_apertura  FOREIGN KEY (id_apertura) REFERENCES APERTURA_CAJA(id_apertura),
    CONSTRAINT uq_vale_apertura  UNIQUE (id_apertura),
    CONSTRAINT chk_vale_monto    CHECK (monto > 0),
    CONSTRAINT chk_vale_estado   CHECK (estado IN ('P', 'A', 'N')),
    CONSTRAINT chk_vale_aplicado CHECK (estado <> 'A' OR fecha_aplicacion IS NOT NULL),
    CONSTRAINT chk_vale_anulado  CHECK (estado <> 'N' OR motivo_anulacion IS NOT NULL)
);

-- ---------------------------- MÉTODOS DE PAGO --------------------------------
-- Catálogo: agregar un método nuevo es un INSERT, no un cambio de estructura.
CREATE TABLE METODO_PAGO (
    id_metodo            NUMBER(10),
    nombre               VARCHAR2(30)  NOT NULL,
    afecta_caja          CHAR(1)       NOT NULL,   -- S: el dinero entra a la gaveta (efectivo)
    requiere_referencia  CHAR(1)       NOT NULL,   -- S: exige número de autorización o boleta
    estado               CHAR(1)       DEFAULT 'A' NOT NULL,
    CONSTRAINT pk_metodo_pago        PRIMARY KEY (id_metodo),
    CONSTRAINT uk_metodo_pago_nombre UNIQUE (nombre),
    CONSTRAINT chk_metodo_caja       CHECK (afecta_caja IN ('S', 'N')),
    CONSTRAINT chk_metodo_referencia CHECK (requiere_referencia IN ('S', 'N')),
    CONSTRAINT chk_metodo_estado     CHECK (estado IN ('A', 'I'))
);

-- Una venta puede pagarse con varios métodos (relación 1:N con VENTAS).
-- El cambio NO se guarda: se calcula como monto_recibido - monto (3FN).
CREATE TABLE PAGO_VENTA (
    id_pago         NUMBER(10),
    id_venta        NUMBER(10)    NOT NULL,
    id_metodo       NUMBER(10)    NOT NULL,
    monto           NUMBER(12,2)  NOT NULL,
    referencia      VARCHAR2(50),             -- autorización de tarjeta o número de boleta
    monto_recibido  NUMBER(12,2),             -- solo efectivo: con cuánto pagó el cliente
    CONSTRAINT pk_pago_venta     PRIMARY KEY (id_pago),
    CONSTRAINT fk_pago_venta     FOREIGN KEY (id_venta)  REFERENCES VENTAS(id_venta),
    CONSTRAINT fk_pago_metodo    FOREIGN KEY (id_metodo) REFERENCES METODO_PAGO(id_metodo),
    CONSTRAINT chk_pago_monto    CHECK (monto > 0),
    CONSTRAINT chk_pago_recibido CHECK (monto_recibido IS NULL OR monto_recibido >= monto)
);

-- ---------------------------- POLÍTICA DE SANCIONES --------------------------
-- La regla de negocio se guarda como datos: se modifica sin cambiar el código.
CREATE TABLE POLITICA_SANCION (
    id_politica         NUMBER(10),
    minimo_incidencias  NUMBER(3)     NOT NULL,
    sancion             VARCHAR2(100) NOT NULL,
    CONSTRAINT pk_politica_sancion PRIMARY KEY (id_politica),
    CONSTRAINT uk_politica_minimo  UNIQUE (minimo_incidencias),
    CONSTRAINT chk_politica_minimo CHECK (minimo_incidencias > 0)
);


-- =============================================================================
-- 4. ÍNDICES
--    Oracle indexa automáticamente las PK y los UNIQUE, pero NO las FK.
--    Estos índices aceleran los JOIN y evitan bloqueos de tabla completa
--    al modificar registros padre.
-- =============================================================================

-- Detalles y pagos
CREATE INDEX idx_detventa_venta        ON DETALLE_VENTA (id_venta);
CREATE INDEX idx_detventa_producto     ON DETALLE_VENTA (id_producto);
CREATE INDEX idx_detcompra_compra      ON DETALLE_COMPRA (id_compra);
CREATE INDEX idx_detcompra_producto    ON DETALLE_COMPRA (id_producto);
CREATE INDEX idx_detcotiz_cotizacion   ON DETALLE_COTIZACION (id_cotizacion);
CREATE INDEX idx_detcotiz_producto     ON DETALLE_COTIZACION (id_producto);
CREATE INDEX idx_pago_venta            ON PAGO_VENTA (id_venta);
CREATE INDEX idx_pago_metodo           ON PAGO_VENTA (id_metodo);

-- Encabezados
CREATE INDEX idx_ventas_cliente        ON VENTAS (id_cliente);
CREATE INDEX idx_ventas_usuario        ON VENTAS (id_usuario);
CREATE INDEX idx_ventas_apertura       ON VENTAS (id_apertura);
CREATE INDEX idx_ventas_usuario_anula  ON VENTAS (id_usuario_anula);
CREATE INDEX idx_ventas_usuario_autor  ON VENTAS (id_usuario_autoriza);
CREATE INDEX idx_compras_proveedor     ON COMPRAS (id_proveedor);
CREATE INDEX idx_compras_usuario       ON COMPRAS (id_usuario);
CREATE INDEX idx_cotizacion_cliente    ON COTIZACION (id_cliente);
CREATE INDEX idx_cotizacion_usuario    ON COTIZACION (id_usuario);

-- Índices compuestos para las consultas más frecuentes
CREATE INDEX idx_kardex_producto_fecha ON KARDEX (id_producto, fecha);         -- historial de un producto
CREATE INDEX idx_apertura_usuario_est  ON APERTURA_CAJA (id_usuario, estado);  -- caja abierta del usuario

-- Resto de llaves foráneas
CREATE INDEX idx_kardex_usuario        ON KARDEX (id_usuario);
CREATE INDEX idx_apertura_caja         ON APERTURA_CAJA (id_caja);
CREATE INDEX idx_audprod_producto      ON AUDITORIA_PRODUCTO (id_producto);
CREATE INDEX idx_usurol_rol            ON USUARIO_ROL (id_rol);


-- =============================================================================
-- 5. VISTAS
-- =============================================================================

-- Resumen de ventas con cliente y usuario
CREATE OR REPLACE VIEW VW_RESUMEN_VENTAS AS
SELECT v.id_venta,
       TO_CHAR(v.fecha, 'DD/MM/YYYY') AS fecha,
       c.nombre  AS cliente,
       u.usuario AS usuario,
       v.total,
       v.estado
FROM VENTAS v
INNER JOIN CLIENTES c ON v.id_cliente = c.id_cliente
INNER JOIN USUARIO u  ON v.id_usuario = u.id_usuario;

-- Productos con existencia igual o menor al mínimo
CREATE OR REPLACE VIEW VW_PRODUCTOS_BAJO_STOCK AS
SELECT id_producto,
       nombre AS producto,
       stock,
       stock_minimo
FROM PRODUCTOS
WHERE stock <= stock_minimo;

-- Unidades y monto vendido por producto (solo ventas activas)
CREATE OR REPLACE VIEW VW_VENTAS_POR_PRODUCTO AS
SELECT p.id_producto,
       p.nombre,
       SUM(d.cantidad)  AS unidades_vendidas,
       SUM(d.subtotal)  AS total_vendido
FROM DETALLE_VENTA d
JOIN VENTAS v    ON d.id_venta = v.id_venta
JOIN PRODUCTOS p ON d.id_producto = p.id_producto
WHERE v.estado = 'A'
GROUP BY p.id_producto, p.nombre;

-- Faltantes y sobrantes calculados desde los cierres de caja (no se duplican datos)
CREATE OR REPLACE VIEW VW_INCIDENCIAS_CAJA AS
SELECT a.id_apertura,
       a.id_usuario,
       u.usuario,
       c.nombre AS caja,
       a.fecha_cierre,
       CASE WHEN a.diferencia < 0 THEN 'FALTANTE' ELSE 'SOBRANTE' END AS tipo,
       ABS(a.diferencia) AS monto,
       a.observacion_cierre,
       v.id_vale,
       v.estado AS estado_vale
FROM APERTURA_CAJA a
JOIN USUARIO u ON a.id_usuario = u.id_usuario
JOIN CAJA c    ON a.id_caja = c.id_caja
LEFT JOIN VALE_DESCUENTO v ON v.id_apertura = a.id_apertura
WHERE a.estado = 'C'
  AND a.diferencia <> 0;

-- Ventas anuladas: quién vendió, quién solicitó y quién autorizó la anulación
CREATE OR REPLACE VIEW VW_ANULACIONES_VENTA AS
SELECT v.id_venta,
       v.fecha,
       v.fecha_anulacion,
       uv.usuario AS vendedor,
       ua.usuario AS anulado_por,
       uz.usuario AS autorizado_por,
       c.nombre   AS cliente,
       v.total,
       v.motivo_anulacion,
       v.id_apertura
FROM VENTAS v
JOIN USUARIO uv  ON v.id_usuario = uv.id_usuario
JOIN USUARIO ua  ON v.id_usuario_anula = ua.id_usuario
JOIN USUARIO uz  ON v.id_usuario_autoriza = uz.id_usuario
JOIN CLIENTES c  ON v.id_cliente = c.id_cliente
WHERE v.estado = 'N';

-- Incidencias sancionables por usuario y mes, con la sanción sugerida por la política.
-- Cuenta los faltantes no justificados (vale no anulado) y las ventas anuladas.
CREATE OR REPLACE VIEW VW_SANCIONES_MES AS
SELECT r.mes,
       r.usuario,
       r.faltantes,
       r.monto_faltante,
       r.anulaciones,
       r.faltantes + r.anulaciones AS total_incidencias,
       (SELECT p.sancion
          FROM POLITICA_SANCION p
         WHERE p.minimo_incidencias = (SELECT MAX(p2.minimo_incidencias)
                                         FROM POLITICA_SANCION p2
                                        WHERE p2.minimo_incidencias <= r.faltantes + r.anulaciones)
       ) AS sancion_sugerida
FROM (
    SELECT mes,
           usuario,
           SUM(faltante)       AS faltantes,
           SUM(monto_faltante) AS monto_faltante,
           SUM(anulacion)      AS anulaciones
    FROM (
        SELECT TO_CHAR(fecha_cierre, 'YYYY-MM') AS mes,
               usuario,
               1     AS faltante,
               monto AS monto_faltante,
               0     AS anulacion
          FROM VW_INCIDENCIAS_CAJA
         WHERE tipo = 'FALTANTE'
           AND NVL(estado_vale, 'P') <> 'N'
        UNION ALL
        SELECT TO_CHAR(fecha_anulacion, 'YYYY-MM'),
               vendedor,
               0,
               0,
               1
          FROM VW_ANULACIONES_VENTA
    )
    GROUP BY mes, usuario
) r;


-- =============================================================================
-- 6. FUNCIONES
-- =============================================================================
CREATE OR REPLACE FUNCTION FN_STOCK_PRODUCTO (
    p_id_producto IN PRODUCTOS.id_producto%TYPE
)
RETURN NUMBER
IS
    v_stock PRODUCTOS.stock%TYPE;
BEGIN
    SELECT stock
      INTO v_stock
      FROM PRODUCTOS
     WHERE id_producto = p_id_producto;

    RETURN v_stock;

EXCEPTION
    WHEN NO_DATA_FOUND THEN
        RAISE_APPLICATION_ERROR(-20001, 'No existe el producto solicitado.');
END FN_STOCK_PRODUCTO;
/

-- Efectivo que debería haber en la gaveta por las ventas ACTIVAS de una apertura.
-- Solo los métodos con afecta_caja = 'S' (efectivo) entran a la caja.
CREATE OR REPLACE FUNCTION FN_EFECTIVO_APERTURA (
    p_id_apertura IN APERTURA_CAJA.id_apertura%TYPE
)
RETURN NUMBER
IS
    v_efectivo NUMBER(12,2);
BEGIN
    SELECT NVL(SUM(p.monto), 0)
      INTO v_efectivo
      FROM PAGO_VENTA p
      JOIN VENTAS v      ON p.id_venta  = v.id_venta
      JOIN METODO_PAGO m ON p.id_metodo = m.id_metodo
     WHERE v.id_apertura = p_id_apertura
       AND v.estado      = 'A'
       AND m.afecta_caja = 'S';

    RETURN v_efectivo;
END FN_EFECTIVO_APERTURA;
/


-- =============================================================================
-- 7. PROCEDIMIENTOS ALMACENADOS
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 7.1 CLIENTES
-- -----------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE SP_REGISTRAR_CLIENTE (
    p_nombre     IN CLIENTES.nombre%TYPE,
    p_direccion  IN CLIENTES.direccion%TYPE,
    p_telefono   IN CLIENTES.telefono%TYPE,
    p_correo     IN CLIENTES.correo%TYPE
)
IS
    v_id_cliente CLIENTES.id_cliente%TYPE;
BEGIN
    INSERT INTO CLIENTES (id_cliente, nombre, direccion, telefono, correo)
    VALUES (SEQ_CLIENTE.NEXTVAL, p_nombre, p_direccion, p_telefono, p_correo)
    RETURNING id_cliente INTO v_id_cliente;

    COMMIT;

    DBMS_OUTPUT.PUT_LINE('Cliente registrado correctamente con ID: ' || v_id_cliente);

EXCEPTION
    WHEN DUP_VAL_ON_INDEX THEN
        ROLLBACK;
        RAISE_APPLICATION_ERROR(-20020, 'Ya existe un cliente registrado con el correo ' || p_correo || '.');
END SP_REGISTRAR_CLIENTE;
/

-- -----------------------------------------------------------------------------
-- 7.2 PROCEDIMIENTOS DEL LABORATORIO 3 (operaciones de UN producto, con COMMIT propio)
--     Se conservan como evidencia del laboratorio. La aplicación usa las
--     versiones de varios productos de las secciones 7.3 y 7.4.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE SP_REGISTRAR_DETALLE_COMPRA (
    p_id_compra     IN COMPRAS.id_compra%TYPE,
    p_id_producto   IN PRODUCTOS.id_producto%TYPE,
    p_cantidad      IN DETALLE_COMPRA.cantidad%TYPE,
    p_precio_costo  IN DETALLE_COMPRA.precio_costo%TYPE
)
IS
    v_id_usuario    COMPRAS.id_usuario%TYPE;
    v_stock_nuevo   PRODUCTOS.stock%TYPE;
    v_subtotal      DETALLE_COMPRA.subtotal%TYPE;
BEGIN
    IF p_cantidad <= 0 THEN
        RAISE_APPLICATION_ERROR(-20003, 'La cantidad comprada debe ser mayor a cero.');
    END IF;

    BEGIN
        SELECT id_usuario INTO v_id_usuario
          FROM COMPRAS
         WHERE id_compra = p_id_compra;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RAISE_APPLICATION_ERROR(-20002, 'No existe la compra solicitada.');
    END;

    v_subtotal := p_cantidad * p_precio_costo;

    UPDATE PRODUCTOS
       SET stock = stock + p_cantidad
     WHERE id_producto = p_id_producto
    RETURNING stock INTO v_stock_nuevo;

    IF SQL%ROWCOUNT = 0 THEN
        RAISE_APPLICATION_ERROR(-20001, 'No existe el producto solicitado.');
    END IF;

    INSERT INTO DETALLE_COMPRA (id_detalle_compra, id_compra, id_producto,
                                cantidad, precio_costo, subtotal)
    VALUES (SEQ_DETALLE_COMPRA.NEXTVAL, p_id_compra, p_id_producto,
            p_cantidad, p_precio_costo, v_subtotal);

    UPDATE COMPRAS
       SET total = total + v_subtotal
     WHERE id_compra = p_id_compra;

    INSERT INTO KARDEX (id_kardex, id_producto, fecha, tipo_movimiento,
                        tipo_documento, referencia, cantidad_entrada,
                        cantidad_salida, existencia_final, id_usuario)
    VALUES (SEQ_KARDEX.NEXTVAL, p_id_producto, SYSDATE, 'ENTRADA',
            'COMPRA', 'COMPRA #' || p_id_compra, p_cantidad,
            0, v_stock_nuevo, v_id_usuario);

    COMMIT;

    DBMS_OUTPUT.PUT_LINE('Compra registrada. Producto ' || p_id_producto ||
                         ' | Cantidad: ' || p_cantidad ||
                         ' | Nuevo stock: ' || v_stock_nuevo);

EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        RAISE;
END SP_REGISTRAR_DETALLE_COMPRA;
/

CREATE OR REPLACE PROCEDURE SP_REGISTRAR_DETALLE_VENTA (
    p_id_venta      IN VENTAS.id_venta%TYPE,
    p_id_producto   IN PRODUCTOS.id_producto%TYPE,
    p_cantidad      IN DETALLE_VENTA.cantidad%TYPE,
    p_precio_venta  IN DETALLE_VENTA.precio_venta%TYPE
)
IS
    v_id_usuario    VENTAS.id_usuario%TYPE;
    v_id_apertura   VENTAS.id_apertura%TYPE;
    v_stock_actual  PRODUCTOS.stock%TYPE;
    v_stock_nuevo   PRODUCTOS.stock%TYPE;
    v_subtotal      DETALLE_VENTA.subtotal%TYPE;
BEGIN
    IF p_cantidad <= 0 THEN
        RAISE_APPLICATION_ERROR(-20003, 'La cantidad vendida debe ser mayor a cero.');
    END IF;

    BEGIN
        SELECT id_usuario, id_apertura INTO v_id_usuario, v_id_apertura
          FROM VENTAS
         WHERE id_venta = p_id_venta
           AND estado = 'A';
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RAISE_APPLICATION_ERROR(-20005, 'No existe la venta solicitada.');
    END;

    -- FOR UPDATE bloquea la fila para que nadie modifique el stock mientras se vende
    BEGIN
        SELECT stock INTO v_stock_actual
          FROM PRODUCTOS
         WHERE id_producto = p_id_producto
           FOR UPDATE;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RAISE_APPLICATION_ERROR(-20001, 'No existe el producto solicitado.');
    END;

    IF v_stock_actual < p_cantidad THEN
        RAISE_APPLICATION_ERROR(-20004,
            'Stock insuficiente para realizar la venta. Disponible: ' ||
            v_stock_actual || ', solicitado: ' || p_cantidad);
    END IF;

    v_subtotal    := p_cantidad * p_precio_venta;
    v_stock_nuevo := v_stock_actual - p_cantidad;

    INSERT INTO DETALLE_VENTA (id_detalle_venta, id_venta, id_producto,
                               cantidad, precio_venta, subtotal)
    VALUES (SEQ_DETALLE_VENTA.NEXTVAL, p_id_venta, p_id_producto,
            p_cantidad, p_precio_venta, v_subtotal);

    UPDATE PRODUCTOS
       SET stock = v_stock_nuevo
     WHERE id_producto = p_id_producto;

    UPDATE VENTAS
       SET total = total + v_subtotal
     WHERE id_venta = p_id_venta;

    INSERT INTO KARDEX (id_kardex, id_producto, fecha, tipo_movimiento,
                        tipo_documento, referencia, cantidad_entrada,
                        cantidad_salida, existencia_final, id_usuario)
    VALUES (SEQ_KARDEX.NEXTVAL, p_id_producto, SYSDATE, 'SALIDA',
            'VENTA', 'VENTA #' || p_id_venta, 0,
            p_cantidad, v_stock_nuevo, v_id_usuario);

    -- Pago en efectivo del producto agregado y actualización de la caja
    INSERT INTO PAGO_VENTA (id_pago, id_venta, id_metodo, monto, referencia, monto_recibido)
    VALUES (SEQ_PAGO_VENTA.NEXTVAL, p_id_venta, 1, v_subtotal, NULL, NULL);

    UPDATE APERTURA_CAJA
       SET monto_esperado = monto_inicial + FN_EFECTIVO_APERTURA(v_id_apertura)
     WHERE id_apertura = v_id_apertura;

    COMMIT;

    DBMS_OUTPUT.PUT_LINE('Venta registrada. Producto ' || p_id_producto ||
                         ' | Cantidad: ' || p_cantidad ||
                         ' | Stock restante: ' || v_stock_nuevo);

EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        RAISE;
END SP_REGISTRAR_DETALLE_VENTA;
/

-- Simulación de una venta completa para demostrar COMMIT y ROLLBACK (Lab 3, Actividad 9).
-- Ahora asocia la venta a la caja abierta del usuario, porque VENTAS.id_apertura es obligatorio.
CREATE OR REPLACE PROCEDURE SP_VENTA_TRANSACCION (
    p_id_cliente     IN VENTAS.id_cliente%TYPE,
    p_id_usuario     IN VENTAS.id_usuario%TYPE,
    p_id_producto    IN PRODUCTOS.id_producto%TYPE,
    p_cantidad       IN NUMBER,
    p_simular_error  IN CHAR DEFAULT 'N'
)
IS
    v_id_venta     VENTAS.id_venta%TYPE;
    v_id_apertura  APERTURA_CAJA.id_apertura%TYPE;
    v_precio       PRODUCTOS.precio_venta%TYPE;
    v_stock        PRODUCTOS.stock%TYPE;
    v_subtotal     NUMBER(12,2);
BEGIN
    BEGIN
        SELECT id_apertura INTO v_id_apertura
          FROM APERTURA_CAJA
         WHERE id_usuario = p_id_usuario
           AND estado = 'A'
         FETCH FIRST 1 ROWS ONLY;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RAISE_APPLICATION_ERROR(-20013, 'No existe una apertura de caja activa para este usuario.');
    END;

    SELECT precio_venta, stock INTO v_precio, v_stock
      FROM PRODUCTOS
     WHERE id_producto = p_id_producto
       FOR UPDATE;

    IF v_stock < p_cantidad THEN
        RAISE_APPLICATION_ERROR(-20004, 'Stock insuficiente para realizar la venta.');
    END IF;

    v_subtotal := p_cantidad * v_precio;

    -- 1. VENTA
    INSERT INTO VENTAS (id_venta, fecha, total, id_cliente, id_usuario, id_apertura)
    VALUES (SEQ_VENTA.NEXTVAL, SYSDATE, v_subtotal, p_id_cliente, p_id_usuario, v_id_apertura)
    RETURNING id_venta INTO v_id_venta;
    DBMS_OUTPUT.PUT_LINE('Paso 1: Venta #' || v_id_venta || ' registrada.');

    -- 2. DETALLE_VENTA
    INSERT INTO DETALLE_VENTA (id_detalle_venta, id_venta, id_producto,
                               cantidad, precio_venta, subtotal)
    VALUES (SEQ_DETALLE_VENTA.NEXTVAL, v_id_venta, p_id_producto,
            p_cantidad, v_precio, v_subtotal);
    DBMS_OUTPUT.PUT_LINE('Paso 2: Detalle registrado.');

    -- 3. PRODUCTO
    UPDATE PRODUCTOS
       SET stock = stock - p_cantidad
     WHERE id_producto = p_id_producto;
    DBMS_OUTPUT.PUT_LINE('Paso 3: Stock actualizado a ' || (v_stock - p_cantidad) || '.');

    -- >>> ERROR PROVOCADO INTENCIONALMENTE <<<
    IF p_simular_error = 'S' THEN
        RAISE_APPLICATION_ERROR(-20099, 'Error simulado antes de registrar el Kardex.');
    END IF;

    -- 4. KARDEX
    INSERT INTO KARDEX (id_kardex, id_producto, fecha, tipo_movimiento,
                        tipo_documento, referencia, cantidad_entrada,
                        cantidad_salida, existencia_final, id_usuario)
    VALUES (SEQ_KARDEX.NEXTVAL, p_id_producto, SYSDATE, 'SALIDA',
            'VENTA', 'VENTA #' || v_id_venta, 0,
            p_cantidad, v_stock - p_cantidad, p_id_usuario);
    DBMS_OUTPUT.PUT_LINE('Paso 4: Kardex registrado.');

    -- 5. PAGO en efectivo y OPERACIÓN DE CAJA
    INSERT INTO PAGO_VENTA (id_pago, id_venta, id_metodo, monto, referencia, monto_recibido)
    VALUES (SEQ_PAGO_VENTA.NEXTVAL, v_id_venta, 1, v_subtotal, NULL, NULL);

    UPDATE APERTURA_CAJA
       SET monto_esperado = monto_inicial + FN_EFECTIVO_APERTURA(v_id_apertura)
     WHERE id_apertura = v_id_apertura;
    DBMS_OUTPUT.PUT_LINE('Paso 5: Pago y caja registrados.');

    COMMIT;
    DBMS_OUTPUT.PUT_LINE('COMMIT ejecutado: la venta #' || v_id_venta || ' quedó registrada completa.');

EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        DBMS_OUTPUT.PUT_LINE('ERROR: ' || SQLERRM);
        DBMS_OUTPUT.PUT_LINE('ROLLBACK ejecutado: la venta NO quedó registrada (ni parcialmente).');
END SP_VENTA_TRANSACCION;
/

-- Proceso integrador de venta de un producto (Lab 3, Actividad 10)
CREATE OR REPLACE PROCEDURE SP_PROCESAR_VENTA (
    p_id_cliente   IN CLIENTES.id_cliente%TYPE,
    p_id_usuario   IN USUARIO.id_usuario%TYPE,
    p_id_producto  IN PRODUCTOS.id_producto%TYPE,
    p_cantidad     IN NUMBER
)
IS
    v_existe          NUMBER;
    v_estado_usuario  USUARIO.estado%TYPE;
    v_id_apertura     APERTURA_CAJA.id_apertura%TYPE;
    v_estado_producto PRODUCTOS.estado%TYPE;
    v_precio          PRODUCTOS.precio_venta%TYPE;
    v_stock           PRODUCTOS.stock%TYPE;
    v_total           NUMBER(12,2);
    v_id_venta        VENTAS.id_venta%TYPE;
BEGIN
    IF p_cantidad IS NULL OR p_cantidad <= 0 THEN
        RAISE_APPLICATION_ERROR(-20003, 'La cantidad vendida debe ser mayor a cero.');
    END IF;

    SELECT COUNT(*) INTO v_existe FROM CLIENTES WHERE id_cliente = p_id_cliente;
    IF v_existe = 0 THEN
        RAISE_APPLICATION_ERROR(-20010, 'No existe el cliente indicado.');
    END IF;

    BEGIN
        SELECT estado INTO v_estado_usuario
          FROM USUARIO
         WHERE id_usuario = p_id_usuario;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RAISE_APPLICATION_ERROR(-20011, 'No existe el usuario indicado.');
    END;

    IF v_estado_usuario <> 'A' THEN
        RAISE_APPLICATION_ERROR(-20012, 'El usuario se encuentra inactivo y no puede realizar ventas.');
    END IF;

    BEGIN
        SELECT a.id_apertura INTO v_id_apertura
          FROM APERTURA_CAJA a
          JOIN CAJA c ON a.id_caja = c.id_caja
         WHERE a.id_usuario = p_id_usuario
           AND a.estado = 'A'
           AND c.estado = 'A'
         ORDER BY a.fecha_apertura DESC
         FETCH FIRST 1 ROWS ONLY;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RAISE_APPLICATION_ERROR(-20013, 'No existe una apertura de caja activa para este usuario.');
    END;

    BEGIN
        SELECT estado, precio_venta, stock
          INTO v_estado_producto, v_precio, v_stock
          FROM PRODUCTOS
         WHERE id_producto = p_id_producto
           FOR UPDATE;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RAISE_APPLICATION_ERROR(-20001, 'No existe el producto solicitado.');
    END;

    IF v_estado_producto <> 'A' THEN
        RAISE_APPLICATION_ERROR(-20014, 'El producto se encuentra inactivo y no puede venderse.');
    END IF;

    IF v_stock < p_cantidad THEN
        RAISE_APPLICATION_ERROR(-20004, 'Stock insuficiente para realizar la venta. Disponible: '
                                        || v_stock || ', solicitado: ' || p_cantidad);
    END IF;

    v_total := p_cantidad * v_precio;

    INSERT INTO VENTAS (id_venta, fecha, total, id_cliente, id_usuario, id_apertura)
    VALUES (SEQ_VENTA.NEXTVAL, SYSDATE, v_total, p_id_cliente, p_id_usuario, v_id_apertura)
    RETURNING id_venta INTO v_id_venta;

    INSERT INTO DETALLE_VENTA (id_detalle_venta, id_venta, id_producto,
                               cantidad, precio_venta, subtotal)
    VALUES (SEQ_DETALLE_VENTA.NEXTVAL, v_id_venta, p_id_producto,
            p_cantidad, v_precio, v_total);

    UPDATE PRODUCTOS
       SET stock = stock - p_cantidad
     WHERE id_producto = p_id_producto;

    INSERT INTO KARDEX (id_kardex, id_producto, fecha, tipo_movimiento,
                        tipo_documento, referencia, cantidad_entrada,
                        cantidad_salida, existencia_final, id_usuario)
    VALUES (SEQ_KARDEX.NEXTVAL, p_id_producto, SYSDATE, 'SALIDA',
            'VENTA', 'VENTA #' || v_id_venta, 0,
            p_cantidad, v_stock - p_cantidad, p_id_usuario);

    -- PAGO en efectivo
    INSERT INTO PAGO_VENTA (id_pago, id_venta, id_metodo, monto, referencia, monto_recibido)
    VALUES (SEQ_PAGO_VENTA.NEXTVAL, v_id_venta, 1, v_total, NULL, NULL);

    -- OPERACIÓN DE CAJA: solo el efectivo entra a la gaveta
    UPDATE APERTURA_CAJA
       SET monto_esperado = monto_inicial + FN_EFECTIVO_APERTURA(v_id_apertura)
     WHERE id_apertura = v_id_apertura;

    COMMIT;

    DBMS_OUTPUT.PUT_LINE('VENTA PROCESADA CORRECTAMENTE');
    DBMS_OUTPUT.PUT_LINE('Venta #' || v_id_venta || ' | Apertura de caja: ' || v_id_apertura);
    DBMS_OUTPUT.PUT_LINE('Producto: ' || p_id_producto || ' | Cantidad: ' || p_cantidad ||
                         ' | Total: Q' || v_total);
    DBMS_OUTPUT.PUT_LINE('Stock restante: ' || (v_stock - p_cantidad));

EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        DBMS_OUTPUT.PUT_LINE('VENTA RECHAZADA: ' || SQLERRM);
        RAISE;
END SP_PROCESAR_VENTA;
/

-- -----------------------------------------------------------------------------
-- 7.3 COMPRAS DE VARIOS PRODUCTOS (usado por la aplicación)
--     NO hace COMMIT: la aplicación confirma o deshace la compra completa.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE SP_AGREGAR_DETALLE_COMPRA (
    p_id_compra     IN COMPRAS.id_compra%TYPE,
    p_id_producto   IN PRODUCTOS.id_producto%TYPE,
    p_cantidad      IN DETALLE_COMPRA.cantidad%TYPE,
    p_precio_costo  IN DETALLE_COMPRA.precio_costo%TYPE
)
IS
    v_id_usuario      COMPRAS.id_usuario%TYPE;
    v_estado_producto PRODUCTOS.estado%TYPE;
    v_stock_nuevo     PRODUCTOS.stock%TYPE;
    v_subtotal        DETALLE_COMPRA.subtotal%TYPE;
BEGIN
    IF p_cantidad IS NULL OR p_cantidad <= 0 THEN
        RAISE_APPLICATION_ERROR(-20003, 'La cantidad comprada debe ser mayor a cero.');
    END IF;

    IF p_precio_costo IS NULL OR p_precio_costo <= 0 THEN
        RAISE_APPLICATION_ERROR(-20006, 'El precio de costo debe ser mayor a cero.');
    END IF;

    BEGIN
        SELECT id_usuario INTO v_id_usuario
          FROM COMPRAS
         WHERE id_compra = p_id_compra;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RAISE_APPLICATION_ERROR(-20002, 'No existe la compra solicitada.');
    END;

    BEGIN
        SELECT estado INTO v_estado_producto
          FROM PRODUCTOS
         WHERE id_producto = p_id_producto
           FOR UPDATE;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RAISE_APPLICATION_ERROR(-20001, 'No existe el producto solicitado.');
    END;

    IF v_estado_producto <> 'A' THEN
        RAISE_APPLICATION_ERROR(-20014, 'El producto ' || p_id_producto ||
                                        ' se encuentra inactivo y no puede comprarse.');
    END IF;

    v_subtotal := p_cantidad * p_precio_costo;

    -- 1. Aumentar el stock
    UPDATE PRODUCTOS
       SET stock = stock + p_cantidad
     WHERE id_producto = p_id_producto
    RETURNING stock INTO v_stock_nuevo;

    -- 2. Detalle de la compra
    INSERT INTO DETALLE_COMPRA (id_detalle_compra, id_compra, id_producto,
                                cantidad, precio_costo, subtotal)
    VALUES (SEQ_DETALLE_COMPRA.NEXTVAL, p_id_compra, p_id_producto,
            p_cantidad, p_precio_costo, v_subtotal);

    -- 3. Total de la compra
    UPDATE COMPRAS
       SET total = total + v_subtotal
     WHERE id_compra = p_id_compra;

    -- 4. ENTRADA en el Kardex
    INSERT INTO KARDEX (id_kardex, id_producto, fecha, tipo_movimiento,
                        tipo_documento, referencia, cantidad_entrada,
                        cantidad_salida, existencia_final, id_usuario)
    VALUES (SEQ_KARDEX.NEXTVAL, p_id_producto, SYSDATE, 'ENTRADA',
            'COMPRA', 'COMPRA #' || p_id_compra, p_cantidad,
            0, v_stock_nuevo, v_id_usuario);
END SP_AGREGAR_DETALLE_COMPRA;
/

-- -----------------------------------------------------------------------------
-- 7.4 VENTAS DE VARIOS PRODUCTOS (usado por la aplicación)
--     Orden: SP_CREAR_VENTA -> SP_AGREGAR_DETALLE_VENTA (por producto)
--            -> SP_AGREGAR_PAGO_VENTA (por pago) -> SP_FINALIZAR_VENTA
--            -> COMMIT / ROLLBACK
--     Ninguno hace COMMIT: la venta completa es una sola transacción.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE SP_CREAR_VENTA (
    p_id_cliente     IN  VENTAS.id_cliente%TYPE,
    p_id_usuario     IN  VENTAS.id_usuario%TYPE,
    p_id_cotizacion  IN  VENTAS.id_cotizacion%TYPE,
    p_id_venta       OUT VENTAS.id_venta%TYPE
)
IS
    v_existe          NUMBER;
    v_estado_usuario  USUARIO.estado%TYPE;
    v_id_apertura     APERTURA_CAJA.id_apertura%TYPE;
    v_estado_cot      COTIZACION.estado%TYPE;
    v_cliente_cot     COTIZACION.id_cliente%TYPE;
BEGIN
    -- CLIENTE
    SELECT COUNT(*) INTO v_existe FROM CLIENTES WHERE id_cliente = p_id_cliente;
    IF v_existe = 0 THEN
        RAISE_APPLICATION_ERROR(-20010, 'No existe el cliente indicado.');
    END IF;

    -- USUARIO
    BEGIN
        SELECT estado INTO v_estado_usuario FROM USUARIO WHERE id_usuario = p_id_usuario;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RAISE_APPLICATION_ERROR(-20011, 'No existe el usuario indicado.');
    END;

    IF v_estado_usuario <> 'A' THEN
        RAISE_APPLICATION_ERROR(-20012, 'El usuario se encuentra inactivo y no puede realizar ventas.');
    END IF;

    -- CAJA ABIERTA
    BEGIN
        SELECT a.id_apertura INTO v_id_apertura
          FROM APERTURA_CAJA a
          JOIN CAJA c ON a.id_caja = c.id_caja
         WHERE a.id_usuario = p_id_usuario
           AND a.estado = 'A'
           AND c.estado = 'A'
         ORDER BY a.fecha_apertura DESC
         FETCH FIRST 1 ROWS ONLY;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RAISE_APPLICATION_ERROR(-20013, 'No existe una apertura de caja activa para este usuario. Abra una caja antes de vender.');
    END;

    -- COTIZACIÓN (opcional)
    IF p_id_cotizacion IS NOT NULL THEN
        BEGIN
            SELECT estado, id_cliente INTO v_estado_cot, v_cliente_cot
              FROM COTIZACION
             WHERE id_cotizacion = p_id_cotizacion
               FOR UPDATE;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                RAISE_APPLICATION_ERROR(-20016, 'No existe la cotización indicada.');
        END;

        IF v_estado_cot <> 'A' THEN
            RAISE_APPLICATION_ERROR(-20017, 'La cotización no está abierta (ya fue facturada o caducó).');
        END IF;

        IF v_cliente_cot <> p_id_cliente THEN
            RAISE_APPLICATION_ERROR(-20018, 'La cotización pertenece a otro cliente.');
        END IF;

        UPDATE COTIZACION SET estado = 'F' WHERE id_cotizacion = p_id_cotizacion;
    END IF;

    INSERT INTO VENTAS (id_venta, fecha, total, id_cliente, id_usuario, id_apertura, id_cotizacion)
    VALUES (SEQ_VENTA.NEXTVAL, SYSDATE, 0, p_id_cliente, p_id_usuario, v_id_apertura, p_id_cotizacion)
    RETURNING id_venta INTO p_id_venta;
END SP_CREAR_VENTA;
/

CREATE OR REPLACE PROCEDURE SP_AGREGAR_DETALLE_VENTA (
    p_id_venta     IN VENTAS.id_venta%TYPE,
    p_id_producto  IN PRODUCTOS.id_producto%TYPE,
    p_cantidad     IN DETALLE_VENTA.cantidad%TYPE
)
IS
    v_id_usuario  VENTAS.id_usuario%TYPE;
    v_estado      PRODUCTOS.estado%TYPE;
    v_nombre      PRODUCTOS.nombre%TYPE;
    v_precio      PRODUCTOS.precio_venta%TYPE;
    v_stock       PRODUCTOS.stock%TYPE;
    v_subtotal    DETALLE_VENTA.subtotal%TYPE;
BEGIN
    IF p_cantidad IS NULL OR p_cantidad <= 0 THEN
        RAISE_APPLICATION_ERROR(-20003, 'La cantidad vendida debe ser mayor a cero.');
    END IF;

    BEGIN
        SELECT id_usuario INTO v_id_usuario FROM VENTAS WHERE id_venta = p_id_venta;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RAISE_APPLICATION_ERROR(-20005, 'No existe la venta solicitada.');
    END;

    BEGIN
        SELECT estado, nombre, precio_venta, stock
          INTO v_estado, v_nombre, v_precio, v_stock
          FROM PRODUCTOS
         WHERE id_producto = p_id_producto
           FOR UPDATE;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RAISE_APPLICATION_ERROR(-20001, 'No existe el producto solicitado.');
    END;

    IF v_estado <> 'A' THEN
        RAISE_APPLICATION_ERROR(-20014, 'El producto ' || v_nombre || ' se encuentra inactivo y no puede venderse.');
    END IF;

    IF v_stock < p_cantidad THEN
        RAISE_APPLICATION_ERROR(-20004, 'Stock insuficiente de ' || v_nombre ||
                                        '. Disponible: ' || v_stock || ', solicitado: ' || p_cantidad || '.');
    END IF;

    v_subtotal := p_cantidad * v_precio;

    -- 1. Detalle (el precio sale del catálogo, no del usuario)
    INSERT INTO DETALLE_VENTA (id_detalle_venta, id_venta, id_producto, cantidad, precio_venta, subtotal)
    VALUES (SEQ_DETALLE_VENTA.NEXTVAL, p_id_venta, p_id_producto, p_cantidad, v_precio, v_subtotal);

    -- 2. Disminuir el stock
    UPDATE PRODUCTOS SET stock = stock - p_cantidad WHERE id_producto = p_id_producto;

    -- 3. Total de la venta
    UPDATE VENTAS SET total = total + v_subtotal WHERE id_venta = p_id_venta;

    -- 4. SALIDA en el Kardex
    INSERT INTO KARDEX (id_kardex, id_producto, fecha, tipo_movimiento, tipo_documento,
                        referencia, cantidad_entrada, cantidad_salida, existencia_final, id_usuario)
    VALUES (SEQ_KARDEX.NEXTVAL, p_id_producto, SYSDATE, 'SALIDA', 'VENTA',
            'VENTA #' || p_id_venta, 0, p_cantidad, v_stock - p_cantidad, v_id_usuario);
END SP_AGREGAR_DETALLE_VENTA;
/

-- Registra un pago de la venta (efectivo, tarjeta o transferencia). No hace COMMIT.
CREATE OR REPLACE PROCEDURE SP_AGREGAR_PAGO_VENTA (
    p_id_venta        IN PAGO_VENTA.id_venta%TYPE,
    p_id_metodo       IN PAGO_VENTA.id_metodo%TYPE,
    p_monto           IN PAGO_VENTA.monto%TYPE,
    p_referencia      IN PAGO_VENTA.referencia%TYPE,
    p_monto_recibido  IN PAGO_VENTA.monto_recibido%TYPE
)
IS
    v_estado_venta   VENTAS.estado%TYPE;
    v_nombre         METODO_PAGO.nombre%TYPE;
    v_afecta_caja    METODO_PAGO.afecta_caja%TYPE;
    v_requiere_ref   METODO_PAGO.requiere_referencia%TYPE;
    v_estado_metodo  METODO_PAGO.estado%TYPE;
BEGIN
    IF p_monto IS NULL OR p_monto <= 0 THEN
        RAISE_APPLICATION_ERROR(-20050, 'El monto del pago debe ser mayor a cero.');
    END IF;

    BEGIN
        SELECT estado INTO v_estado_venta FROM VENTAS WHERE id_venta = p_id_venta;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RAISE_APPLICATION_ERROR(-20005, 'No existe la venta solicitada.');
    END;

    IF v_estado_venta <> 'A' THEN
        RAISE_APPLICATION_ERROR(-20057, 'No se pueden registrar pagos en una venta anulada.');
    END IF;

    BEGIN
        SELECT nombre, afecta_caja, requiere_referencia, estado
          INTO v_nombre, v_afecta_caja, v_requiere_ref, v_estado_metodo
          FROM METODO_PAGO
         WHERE id_metodo = p_id_metodo;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RAISE_APPLICATION_ERROR(-20051, 'No existe el método de pago indicado.');
    END;

    IF v_estado_metodo <> 'A' THEN
        RAISE_APPLICATION_ERROR(-20052, 'El método de pago ' || v_nombre || ' no está disponible.');
    END IF;

    IF v_requiere_ref = 'S' AND TRIM(p_referencia) IS NULL THEN
        RAISE_APPLICATION_ERROR(-20053, 'El pago con ' || v_nombre ||
                                        ' requiere el número de autorización o referencia.');
    END IF;

    IF p_monto_recibido IS NOT NULL THEN
        IF v_afecta_caja <> 'S' THEN
            RAISE_APPLICATION_ERROR(-20054, 'Solo los pagos en efectivo registran monto recibido.');
        END IF;
        IF p_monto_recibido < p_monto THEN
            RAISE_APPLICATION_ERROR(-20055, 'El efectivo recibido no cubre el monto del pago.');
        END IF;
    END IF;

    INSERT INTO PAGO_VENTA (id_pago, id_venta, id_metodo, monto, referencia, monto_recibido)
    VALUES (SEQ_PAGO_VENTA.NEXTVAL, p_id_venta, p_id_metodo, p_monto,
            TRIM(p_referencia), p_monto_recibido);
END SP_AGREGAR_PAGO_VENTA;
/

-- Cierra la venta: valida productos y pagos y actualiza la caja. No hace COMMIT.
CREATE OR REPLACE PROCEDURE SP_FINALIZAR_VENTA (
    p_id_venta IN VENTAS.id_venta%TYPE
)
IS
    v_lineas       NUMBER;
    v_id_apertura  VENTAS.id_apertura%TYPE;
    v_total        VENTAS.total%TYPE;
    v_pagado       NUMBER(12,2);
    v_efectivo     NUMBER(12,2);
BEGIN
    SELECT COUNT(*) INTO v_lineas FROM DETALLE_VENTA WHERE id_venta = p_id_venta;
    IF v_lineas = 0 THEN
        RAISE_APPLICATION_ERROR(-20015, 'La venta debe tener al menos un producto.');
    END IF;

    SELECT id_apertura, total INTO v_id_apertura, v_total
      FROM VENTAS WHERE id_venta = p_id_venta;

    -- La suma de los pagos debe cubrir exactamente el total
    SELECT NVL(SUM(monto), 0) INTO v_pagado FROM PAGO_VENTA WHERE id_venta = p_id_venta;

    IF v_pagado <> v_total THEN
        RAISE_APPLICATION_ERROR(-20056, 'La suma de los pagos (Q' || v_pagado ||
                                        ') debe ser igual al total de la venta (Q' || v_total || ').');
    END IF;

    -- OPERACIÓN DE CAJA: solo el efectivo entra a la gaveta
    v_efectivo := FN_EFECTIVO_APERTURA(v_id_apertura);

    UPDATE APERTURA_CAJA
       SET monto_esperado = monto_inicial + v_efectivo
     WHERE id_apertura = v_id_apertura;
END SP_FINALIZAR_VENTA;
/

-- Anula una venta con autorización de un ADMINISTRADOR (con COMMIT propio).
-- Devuelve el stock con un cursor, registra la ENTRADA en el Kardex y ajusta la caja.
CREATE OR REPLACE PROCEDURE SP_ANULAR_VENTA (
    p_id_venta     IN VENTAS.id_venta%TYPE,
    p_id_usuario   IN USUARIO.id_usuario%TYPE,      -- quien solicita la anulación
    p_id_autoriza  IN USUARIO.id_usuario%TYPE,      -- administrador que la autoriza
    p_motivo       IN VENTAS.motivo_anulacion%TYPE
)
IS
    v_estado_venta     VENTAS.estado%TYPE;
    v_id_apertura      VENTAS.id_apertura%TYPE;
    v_estado_apertura  APERTURA_CAJA.estado%TYPE;
    v_estado_usuario   USUARIO.estado%TYPE;
    v_es_admin         NUMBER;
    v_stock_nuevo      PRODUCTOS.stock%TYPE;
    v_efectivo         NUMBER(12,2);

    -- Productos de la venta que se devolverán al inventario
    CURSOR c_detalle IS
        SELECT id_producto, cantidad
          FROM DETALLE_VENTA
         WHERE id_venta = p_id_venta;
BEGIN
    IF p_motivo IS NULL OR LENGTH(TRIM(p_motivo)) < 5 THEN
        RAISE_APPLICATION_ERROR(-20060, 'Indique el motivo de la anulación (mínimo 5 caracteres).');
    END IF;

    -- Quien solicita debe existir y estar activo
    BEGIN
        SELECT estado INTO v_estado_usuario FROM USUARIO WHERE id_usuario = p_id_usuario;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RAISE_APPLICATION_ERROR(-20011, 'No existe el usuario indicado.');
    END;

    IF v_estado_usuario <> 'A' THEN
        RAISE_APPLICATION_ERROR(-20012, 'El usuario se encuentra inactivo.');
    END IF;

    -- Quien autoriza debe ser un ADMINISTRADOR activo
    SELECT COUNT(*) INTO v_es_admin
      FROM USUARIO u
      JOIN USUARIO_ROL ur ON u.id_usuario = ur.id_usuario
      JOIN ROL r          ON ur.id_rol = r.id_rol
     WHERE u.id_usuario = p_id_autoriza
       AND u.estado     = 'A'
       AND r.nombre_rol = 'ADMINISTRADOR';

    IF v_es_admin = 0 THEN
        RAISE_APPLICATION_ERROR(-20063, 'La anulación debe ser autorizada por un administrador activo.');
    END IF;

    BEGIN
        SELECT estado, id_apertura INTO v_estado_venta, v_id_apertura
          FROM VENTAS
         WHERE id_venta = p_id_venta
           FOR UPDATE;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RAISE_APPLICATION_ERROR(-20005, 'No existe la venta solicitada.');
    END;

    IF v_estado_venta = 'N' THEN
        RAISE_APPLICATION_ERROR(-20061, 'Esta venta ya fue anulada.');
    END IF;

    SELECT estado INTO v_estado_apertura FROM APERTURA_CAJA WHERE id_apertura = v_id_apertura;

    IF v_estado_apertura <> 'A' THEN
        RAISE_APPLICATION_ERROR(-20062, 'No se puede anular: la caja de esta venta ya fue cerrada.');
    END IF;

    -- 1. Devolver cada producto al inventario y registrar la ENTRADA en el Kardex
    FOR linea IN c_detalle LOOP
        UPDATE PRODUCTOS
           SET stock = stock + linea.cantidad
         WHERE id_producto = linea.id_producto
        RETURNING stock INTO v_stock_nuevo;

        INSERT INTO KARDEX (id_kardex, id_producto, fecha, tipo_movimiento, tipo_documento,
                            referencia, cantidad_entrada, cantidad_salida, existencia_final, id_usuario)
        VALUES (SEQ_KARDEX.NEXTVAL, linea.id_producto, SYSDATE, 'ENTRADA', 'ANULACION',
                'ANULACION VENTA #' || p_id_venta, linea.cantidad, 0, v_stock_nuevo, p_id_usuario);
    END LOOP;

    -- 2. Marcar la venta como anulada
    UPDATE VENTAS
       SET estado              = 'N',
           fecha_anulacion     = SYSDATE,
           id_usuario_anula    = p_id_usuario,
           id_usuario_autoriza = p_id_autoriza,
           motivo_anulacion    = TRIM(p_motivo)
     WHERE id_venta = p_id_venta;

    -- 3. Recalcular la caja (la venta anulada ya no suma efectivo)
    v_efectivo := FN_EFECTIVO_APERTURA(v_id_apertura);

    UPDATE APERTURA_CAJA
       SET monto_esperado = monto_inicial + v_efectivo
     WHERE id_apertura = v_id_apertura;

    COMMIT;

EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        RAISE;
END SP_ANULAR_VENTA;
/

-- -----------------------------------------------------------------------------
-- 7.5 COTIZACIONES
-- -----------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE SP_CADUCAR_COTIZACIONES
IS
BEGIN
    UPDATE COTIZACION
       SET estado = 'C'
     WHERE estado = 'A'
       AND TRUNC(fecha_vencimiento) < TRUNC(SYSDATE);

    DBMS_OUTPUT.PUT_LINE('Cotizaciones caducadas: ' || SQL%ROWCOUNT);
    COMMIT;
END SP_CADUCAR_COTIZACIONES;
/

-- -----------------------------------------------------------------------------
-- 7.6 CAJA
-- -----------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE SP_ABRIR_CAJA (
    p_id_caja        IN  CAJA.id_caja%TYPE,
    p_id_usuario     IN  USUARIO.id_usuario%TYPE,
    p_monto_inicial  IN  APERTURA_CAJA.monto_inicial%TYPE,
    p_id_apertura    OUT APERTURA_CAJA.id_apertura%TYPE
)
IS
    v_estado_usuario  USUARIO.estado%TYPE;
    v_estado_caja     CAJA.estado%TYPE;
    v_abiertas        NUMBER;
BEGIN
    IF p_monto_inicial IS NULL OR p_monto_inicial < 0 THEN
        RAISE_APPLICATION_ERROR(-20030, 'El monto inicial no puede ser negativo.');
    END IF;

    BEGIN
        SELECT estado INTO v_estado_usuario FROM USUARIO WHERE id_usuario = p_id_usuario;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RAISE_APPLICATION_ERROR(-20011, 'No existe el usuario indicado.');
    END;

    IF v_estado_usuario <> 'A' THEN
        RAISE_APPLICATION_ERROR(-20012, 'El usuario se encuentra inactivo.');
    END IF;

    BEGIN
        SELECT estado INTO v_estado_caja FROM CAJA WHERE id_caja = p_id_caja FOR UPDATE;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RAISE_APPLICATION_ERROR(-20031, 'No existe la caja indicada.');
    END;

    IF v_estado_caja <> 'A' THEN
        RAISE_APPLICATION_ERROR(-20032, 'La caja se encuentra inactiva.');
    END IF;

    SELECT COUNT(*) INTO v_abiertas
      FROM APERTURA_CAJA
     WHERE id_usuario = p_id_usuario AND estado = 'A';

    IF v_abiertas > 0 THEN
        RAISE_APPLICATION_ERROR(-20033, 'El usuario ya tiene una caja abierta. Debe cerrarla antes de abrir otra.');
    END IF;

    SELECT COUNT(*) INTO v_abiertas
      FROM APERTURA_CAJA
     WHERE id_caja = p_id_caja AND estado = 'A';

    IF v_abiertas > 0 THEN
        RAISE_APPLICATION_ERROR(-20034, 'Esa caja ya está abierta por otro usuario.');
    END IF;

    INSERT INTO APERTURA_CAJA (id_apertura, id_caja, id_usuario, fecha_apertura,
                               monto_inicial, monto_esperado, monto_contado, diferencia, estado)
    VALUES (SEQ_APERTURA.NEXTVAL, p_id_caja, p_id_usuario, SYSDATE,
            p_monto_inicial, p_monto_inicial, 0, 0, 'A')
    RETURNING id_apertura INTO p_id_apertura;

    COMMIT;

EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        RAISE;
END SP_ABRIR_CAJA;
/

CREATE OR REPLACE PROCEDURE SP_CERRAR_CAJA (
    p_id_apertura    IN APERTURA_CAJA.id_apertura%TYPE,
    p_id_usuario     IN USUARIO.id_usuario%TYPE,
    p_monto_contado  IN APERTURA_CAJA.monto_contado%TYPE,
    p_observacion    IN APERTURA_CAJA.observacion_cierre%TYPE DEFAULT NULL
)
IS
    v_id_usuario     APERTURA_CAJA.id_usuario%TYPE;
    v_estado         APERTURA_CAJA.estado%TYPE;
    v_monto_inicial  APERTURA_CAJA.monto_inicial%TYPE;
    v_esperado       NUMBER(12,2);
BEGIN
    IF p_monto_contado IS NULL OR p_monto_contado < 0 THEN
        RAISE_APPLICATION_ERROR(-20035, 'El monto contado no puede ser negativo.');
    END IF;

    BEGIN
        SELECT id_usuario, estado, monto_inicial
          INTO v_id_usuario, v_estado, v_monto_inicial
          FROM APERTURA_CAJA
         WHERE id_apertura = p_id_apertura
           FOR UPDATE;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RAISE_APPLICATION_ERROR(-20036, 'No existe la apertura de caja indicada.');
    END;

    IF v_estado <> 'A' THEN
        RAISE_APPLICATION_ERROR(-20037, 'Esta caja ya fue cerrada.');
    END IF;

    IF v_id_usuario <> p_id_usuario THEN
        RAISE_APPLICATION_ERROR(-20038, 'Solo el usuario que abrió la caja puede cerrarla.');
    END IF;

    -- Monto esperado = monto inicial + efectivo de las ventas activas
    v_esperado := v_monto_inicial + FN_EFECTIVO_APERTURA(p_id_apertura);

    -- Al cambiar el estado a 'C' se dispara TRG_VALE_FALTANTE (si hay faltante)
    UPDATE APERTURA_CAJA
       SET fecha_cierre       = SYSDATE,
           monto_esperado     = v_esperado,
           monto_contado      = p_monto_contado,
           diferencia         = p_monto_contado - v_esperado,
           observacion_cierre = p_observacion,
           estado             = 'C'
     WHERE id_apertura = p_id_apertura;

    COMMIT;

EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        RAISE;
END SP_CERRAR_CAJA;
/

CREATE OR REPLACE PROCEDURE SP_APLICAR_VALES_MES (
    p_mes       IN  VARCHAR2,   -- formato 'YYYY-MM'
    p_cantidad  OUT NUMBER
)
IS
BEGIN
    IF p_mes IS NULL OR NOT REGEXP_LIKE(p_mes, '^[0-9]{4}-[0-9]{2}$') THEN
        RAISE_APPLICATION_ERROR(-20040, 'El mes debe tener el formato AAAA-MM.');
    END IF;

    UPDATE VALE_DESCUENTO
       SET estado = 'A',
           fecha_aplicacion = SYSDATE
     WHERE estado = 'P'
       AND TO_CHAR(fecha_emision, 'YYYY-MM') = p_mes;

    p_cantidad := SQL%ROWCOUNT;
    COMMIT;

EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        RAISE;
END SP_APLICAR_VALES_MES;
/


-- =============================================================================
-- 8. TRIGGERS
-- =============================================================================

-- Auditoría: registra automáticamente cada cambio del precio de venta.
-- Guarda el usuario de la aplicación (CLIENT_IDENTIFIER) o, si no viene, el de Oracle.
CREATE OR REPLACE TRIGGER TRG_AUDITORIA_PRECIO
AFTER UPDATE OF precio_venta ON PRODUCTOS
FOR EACH ROW
WHEN (OLD.precio_venta <> NEW.precio_venta)
BEGIN
    INSERT INTO AUDITORIA_PRODUCTO (id_auditoria, id_producto, precio_anterior,
                                    precio_nuevo, usuario, fecha, tipo_operacion)
    VALUES (SEQ_AUDITORIA_PRODUCTO.NEXTVAL, :OLD.id_producto, :OLD.precio_venta,
            :NEW.precio_venta,
            NVL(SYS_CONTEXT('USERENV', 'CLIENT_IDENTIFIER'), USER),
            SYSDATE, 'UPDATE PRECIO');
END TRG_AUDITORIA_PRECIO;
/

-- Regla de negocio: al cerrar una caja con FALTANTE se genera el vale de descuento.
CREATE OR REPLACE TRIGGER TRG_VALE_FALTANTE
AFTER UPDATE OF estado ON APERTURA_CAJA
FOR EACH ROW
WHEN (OLD.estado = 'A' AND NEW.estado = 'C' AND NEW.diferencia < 0)
BEGIN
    INSERT INTO VALE_DESCUENTO (id_vale, id_apertura, monto, estado, fecha_emision)
    VALUES (SEQ_VALE.NEXTVAL, :NEW.id_apertura, ABS(:NEW.diferencia), 'P', SYSDATE);
END TRG_VALE_FALTANTE;
/


-- =============================================================================
-- 9. JOB PROGRAMADO (DBMS_SCHEDULER)
--    Oracle ejecuta SP_CADUCAR_COTIZACIONES todos los días a las 00:05,
--    aunque nadie use la aplicación. Requiere el privilegio CREATE JOB.
-- =============================================================================
BEGIN
    DBMS_SCHEDULER.CREATE_JOB(
        job_name        => 'JOB_CADUCAR_COTIZACIONES',
        job_type        => 'STORED_PROCEDURE',
        job_action      => 'SP_CADUCAR_COTIZACIONES',
        start_date      => SYSTIMESTAMP,
        repeat_interval => 'FREQ=DAILY; BYHOUR=0; BYMINUTE=5; BYSECOND=0',
        enabled         => TRUE,
        comments        => 'Marca como caducadas las cotizaciones vencidas, todos los días a las 00:05'
    );
END;
/


-- =============================================================================
-- 10. DATOS DE PRUEBA
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 10.1 CATÁLOGOS
-- -----------------------------------------------------------------------------
INSERT INTO ROL (id_rol, nombre_rol, descripcion) VALUES (1, 'ADMINISTRADOR', 'Acceso total al sistema');
INSERT INTO ROL (id_rol, nombre_rol, descripcion) VALUES (2, 'VENDEDOR',      'Gestión de ventas y cotizaciones');
INSERT INTO ROL (id_rol, nombre_rol, descripcion) VALUES (3, 'CAJERO',        'Manejo de caja y cobros');
INSERT INTO ROL (id_rol, nombre_rol, descripcion) VALUES (4, 'BODEGUERO',     'Gestión de inventario y compras');

-- Contraseñas guardadas como hash (scrypt). Ver la tabla de usuarios al inicio del script.
INSERT INTO USUARIO (id_usuario, usuario, password, estado) VALUES (1, 'admin_marta',
  'scrypt:32768:8:1$sLqmTX6Dr6UOaHLu$69a5b264c022d5dfb5dd157d3bae705001d4e7fcb24c3c23c0fbf8181eba155b71f9ae07add624f221e8d6e1765abd4a8325ade27b7e08db24f9389e70f4cfe9', 'A');
INSERT INTO USUARIO (id_usuario, usuario, password, estado) VALUES (2, 'cajero1',
  'scrypt:32768:8:1$nKWJa63dOsuCN4XE$ceb4f182417a750e5085b1abde413d52a3bb4e24c086f423fdb0fc42e2dbf74485b84f70f5eb36cf793d2721e1573694619e4bb1509f18f836f9908fbcf2671c', 'A');
INSERT INTO USUARIO (id_usuario, usuario, password, estado) VALUES (3, 'vendedor2',
  'scrypt:32768:8:1$2kUn4R6KWppuxS0j$0b4cca18347419490bae17272eaee2d92cab3dc9bc0ac51307f0ceeba465a763d7a32c3f300666d7ae8593492d2fd1b1a4b1cfd82cd7803d370e19624f69e8f5', 'A');
INSERT INTO USUARIO (id_usuario, usuario, password, estado) VALUES (4, 'bodega_lab',
  'scrypt:32768:8:1$QCy7FZbbeG1Inbih$9387a05faf1dee81238b1b48a8a7c7d670f4590afd9a4605cf5de9fbd83e2b898b9d8f4969d2450cccf3a8268abd06d0ea5a6cd2eab90ae5420433c18123628d', 'A');
INSERT INTO USUARIO (id_usuario, usuario, password, estado) VALUES (5, 'usuario_inactivo',
  'scrypt:32768:8:1$fbs8ppwLfO3m3afm$57507b5be5b61bbba9599585d3cb72e625af94f1412ecc20d0f5c8853dc8092bb09efcd9b126030fed30525154bba30fdae1ad6931ac463489a92b38365bd801', 'I');

INSERT INTO USUARIO_ROL (id_usuario, id_rol) VALUES (1, 1);
INSERT INTO USUARIO_ROL (id_usuario, id_rol) VALUES (2, 3);
INSERT INTO USUARIO_ROL (id_usuario, id_rol) VALUES (3, 2);
INSERT INTO USUARIO_ROL (id_usuario, id_rol) VALUES (4, 4);
INSERT INTO USUARIO_ROL (id_usuario, id_rol) VALUES (5, 2);

INSERT INTO CLIENTES (id_cliente, nombre, direccion, telefono, correo) VALUES (1, 'Juan Pérez',     'Calle 5, Zona 11, Guatemala',         '77885214', 'juan.perez@email.com');
INSERT INTO CLIENTES (id_cliente, nombre, direccion, telefono, correo) VALUES (2, 'María López',    'Av. Las Américas, Zona 14, Guatemala', '55443322', 'maria.lopez@email.com');
INSERT INTO CLIENTES (id_cliente, nombre, direccion, telefono, correo) VALUES (3, 'Carlos Gómez',   'Colonia El Maestro, Zona 15',         '50539569', 'carlos.gomez@email.com');
INSERT INTO CLIENTES (id_cliente, nombre, direccion, telefono, correo) VALUES (4, 'Ana Martínez',   'Calzada Roosevelt, Zona 7',           '55776655', 'ana.martinez@email.com');
INSERT INTO CLIENTES (id_cliente, nombre, direccion, telefono, correo) VALUES (5, 'Pedro Gómez',    'Escuintla',                           '78301122', 'pedro.gomez@email.com');
INSERT INTO CLIENTES (id_cliente, nombre, direccion, telefono, correo) VALUES (6, 'Luis Hernández', 'Zona 18, Guatemala',                  '55441122', 'luis.hernandez@email.com');
INSERT INTO CLIENTES (id_cliente, nombre, direccion, telefono, correo) VALUES (7, 'Sofía Castillo', 'Mixco, Guatemala',                    '55998877', 'sofia.castillo@email.com');

INSERT INTO PROVEEDORES (id_proveedor, nombre, direccion, telefono, nit) VALUES (1, 'Eden S.A.',         'Zona 15, Quiché',  '59560379', '1234567-4');
INSERT INTO PROVEEDORES (id_proveedor, nombre, direccion, telefono, nit) VALUES (2, 'Empresa Global',    'Zona 1, Quiché',   '45897452', '8765432-5');
INSERT INTO PROVEEDORES (id_proveedor, nombre, direccion, telefono, nit) VALUES (3, 'Ciudad República',  'Zona 3, Quiché',   '24445566', '5544334-5');
INSERT INTO PROVEEDORES (id_proveedor, nombre, direccion, telefono, nit) VALUES (4, 'Comercial La Paz',  'Chimaltenango',    '78390000', '1122334-5');

-- Todos los productos inician con stock 0: la existencia solo aumenta con compras.
INSERT INTO PRODUCTOS (id_producto, nombre, precio_compra, precio_venta, stock, estado, fecha_registro, stock_minimo) VALUES (1,  'Mouse Inalámbrico',        45,   75,   0, 'A', DATE '2026-08-01', 10);
INSERT INTO PRODUCTOS (id_producto, nombre, precio_compra, precio_venta, stock, estado, fecha_registro, stock_minimo) VALUES (2,  'Teclado Mecánico',         120,  200,  0, 'A', DATE '2026-08-01', 5);
INSERT INTO PRODUCTOS (id_producto, nombre, precio_compra, precio_venta, stock, estado, fecha_registro, stock_minimo) VALUES (3,  'Monitor 24 pulgadas',      800,  1250, 0, 'A', DATE '2026-08-01', 3);
INSERT INTO PRODUCTOS (id_producto, nombre, precio_compra, precio_venta, stock, estado, fecha_registro, stock_minimo) VALUES (4,  'Audífonos Bluetooth',      150,  300,  0, 'A', DATE '2026-08-01', 5);
INSERT INTO PRODUCTOS (id_producto, nombre, precio_compra, precio_venta, stock, estado, fecha_registro, stock_minimo) VALUES (5,  'Memoria USB 64GB',         30,   55,   0, 'A', DATE '2026-08-01', 10);
INSERT INTO PRODUCTOS (id_producto, nombre, precio_compra, precio_venta, stock, estado, fecha_registro, stock_minimo) VALUES (6,  'Disco Duro Externo 1TB',   300,  480,  0, 'A', DATE '2026-08-01', 3);
INSERT INTO PRODUCTOS (id_producto, nombre, precio_compra, precio_venta, stock, estado, fecha_registro, stock_minimo) VALUES (7,  'Proyector Full HD',        2500, 3800, 0, 'A', DATE '2026-08-01', 2);
INSERT INTO PRODUCTOS (id_producto, nombre, precio_compra, precio_venta, stock, estado, fecha_registro, stock_minimo) VALUES (8,  'Silla Ergonómica Oficina', 900,  1500, 0, 'A', DATE '2026-08-01', 2);
INSERT INTO PRODUCTOS (id_producto, nombre, precio_compra, precio_venta, stock, estado, fecha_registro, stock_minimo) VALUES (9,  'Webcam HD 1080p',          180,  300,  0, 'A', DATE '2026-08-01', 5);
INSERT INTO PRODUCTOS (id_producto, nombre, precio_compra, precio_venta, stock, estado, fecha_registro, stock_minimo) VALUES (10, 'Lápiz Óptico Tablet',      90,   180,  0, 'A', DATE '2026-08-01', 5);
INSERT INTO PRODUCTOS (id_producto, nombre, precio_compra, precio_venta, stock, estado, fecha_registro, stock_minimo) VALUES (11, 'Monitor Gamer 27"',        1500, 2200, 0, 'A', DATE '2026-08-01', 2);
INSERT INTO PRODUCTOS (id_producto, nombre, precio_compra, precio_venta, stock, estado, fecha_registro, stock_minimo) VALUES (12, 'Hub USB-C 7 en 1',         140,  260,  0, 'I', DATE '2026-08-01', 5);

INSERT INTO CAJA (id_caja, nombre, estado) VALUES (1, 'Caja 1 - Principal', 'A');
INSERT INTO CAJA (id_caja, nombre, estado) VALUES (2, 'Caja 2 - Mostrador', 'A');
INSERT INTO CAJA (id_caja, nombre, estado) VALUES (3, 'Caja 3 - Bodega',    'I');

INSERT INTO METODO_PAGO (id_metodo, nombre, afecta_caja, requiere_referencia, estado) VALUES (1, 'Efectivo',      'S', 'N', 'A');
INSERT INTO METODO_PAGO (id_metodo, nombre, afecta_caja, requiere_referencia, estado) VALUES (2, 'Tarjeta',       'N', 'S', 'A');
INSERT INTO METODO_PAGO (id_metodo, nombre, afecta_caja, requiere_referencia, estado) VALUES (3, 'Transferencia', 'N', 'S', 'A');

-- Política de sanciones (por mes): desde cuántas incidencias aplica cada nivel
INSERT INTO POLITICA_SANCION (id_politica, minimo_incidencias, sancion) VALUES (1, 2, 'Llamada de atención verbal');
INSERT INTO POLITICA_SANCION (id_politica, minimo_incidencias, sancion) VALUES (2, 3, 'Amonestación por escrito');
INSERT INTO POLITICA_SANCION (id_politica, minimo_incidencias, sancion) VALUES (3, 5, 'Suspensión y revisión por gerencia');

COMMIT;

-- -----------------------------------------------------------------------------
-- 10.2 OPERACIONES (agosto a octubre de 2026)
--     Se registran con los MISMOS procedimientos que usa la aplicación, para que
--     stock, Kardex, pagos y caja cuadren. Luego se ajustan las fechas a días
--     pasados para que los reportes muestren varios meses.
-- -----------------------------------------------------------------------------
DECLARE
    v_id_compra    NUMBER;
    v_id_venta     NUMBER;
    v_id_apertura  NUMBER;
    v_ap_agosto    NUMBER;
    v_ap_sept      NUMBER;
    v_id_cot       NUMBER;
    v_cantidad     NUMBER;
    v_total        NUMBER;

    -- ===== Compras =====
    FUNCTION crear_compra(p_proveedor NUMBER, p_usuario NUMBER) RETURN NUMBER IS
        v_id NUMBER;
    BEGIN
        SELECT SEQ_COMPRA.NEXTVAL INTO v_id FROM DUAL;
        INSERT INTO COMPRAS (id_compra, fecha, total, id_proveedor, id_usuario)
        VALUES (v_id, SYSDATE, 0, p_proveedor, p_usuario);
        RETURN v_id;
    END;

    PROCEDURE fechar_compra(p_id NUMBER, p_fecha DATE) IS
    BEGIN
        UPDATE COMPRAS SET fecha = p_fecha WHERE id_compra = p_id;
        UPDATE KARDEX  SET fecha = p_fecha WHERE referencia = 'COMPRA #' || p_id;
        COMMIT;
    END;

    -- ===== Pagos =====
    -- EFECTIVO: un pago, recibido redondeado al siguiente billete de Q100
    -- TARJETA / TRANSFERENCIA: un pago con número de referencia
    -- MIXTO: la mitad en efectivo y la otra mitad con tarjeta
    PROCEDURE pagar(p_venta NUMBER, p_total NUMBER, p_forma VARCHAR2) IS
        v_efectivo NUMBER;
    BEGIN
        IF p_forma = 'TARJETA' THEN
            SP_AGREGAR_PAGO_VENTA(p_venta, 2, p_total, 'AUT-' || LPAD(p_venta, 6, '0'), NULL);
        ELSIF p_forma = 'TRANSFERENCIA' THEN
            SP_AGREGAR_PAGO_VENTA(p_venta, 3, p_total, 'BOL-' || LPAD(p_venta, 6, '0'), NULL);
        ELSIF p_forma = 'MIXTO' THEN
            v_efectivo := ROUND(p_total / 2, 2);
            SP_AGREGAR_PAGO_VENTA(p_venta, 1, v_efectivo, NULL, CEIL(v_efectivo / 100) * 100);
            SP_AGREGAR_PAGO_VENTA(p_venta, 2, p_total - v_efectivo, 'AUT-' || LPAD(p_venta, 6, '0'), NULL);
        ELSE
            SP_AGREGAR_PAGO_VENTA(p_venta, 1, p_total, NULL, CEIL(p_total / 100) * 100);
        END IF;
    END;

    -- ===== Ventas (hasta dos productos por venta) =====
    FUNCTION vender(p_cliente NUMBER, p_usuario NUMBER,
                    p_prod1 NUMBER, p_cant1 NUMBER,
                    p_prod2 NUMBER, p_cant2 NUMBER,
                    p_fecha DATE, p_forma VARCHAR2) RETURN NUMBER IS
        v_id     NUMBER;
        v_monto  NUMBER;
    BEGIN
        SP_CREAR_VENTA(p_cliente, p_usuario, NULL, v_id);
        SP_AGREGAR_DETALLE_VENTA(v_id, p_prod1, p_cant1);
        IF p_prod2 IS NOT NULL THEN
            SP_AGREGAR_DETALLE_VENTA(v_id, p_prod2, p_cant2);
        END IF;

        SELECT total INTO v_monto FROM VENTAS WHERE id_venta = v_id;
        pagar(v_id, v_monto, p_forma);
        SP_FINALIZAR_VENTA(v_id);

        UPDATE VENTAS SET fecha = p_fecha WHERE id_venta = v_id;
        UPDATE KARDEX SET fecha = p_fecha WHERE referencia = 'VENTA #' || v_id;
        COMMIT;
        RETURN v_id;
    END;

    -- ===== Anulación autorizada =====
    PROCEDURE anular(p_venta NUMBER, p_solicita NUMBER, p_autoriza NUMBER,
                     p_motivo VARCHAR2, p_fecha DATE) IS
    BEGIN
        SP_ANULAR_VENTA(p_venta, p_solicita, p_autoriza, p_motivo);
        UPDATE VENTAS SET fecha_anulacion = p_fecha WHERE id_venta = p_venta;
        UPDATE KARDEX SET fecha = p_fecha WHERE referencia = 'ANULACION VENTA #' || p_venta;
        COMMIT;
    END;

    -- ===== Caja =====
    PROCEDURE abrir(p_caja NUMBER, p_usuario NUMBER, p_monto NUMBER,
                    p_fecha DATE, p_id OUT NUMBER) IS
    BEGIN
        SP_ABRIR_CAJA(p_caja, p_usuario, p_monto, p_id);
        UPDATE APERTURA_CAJA SET fecha_apertura = p_fecha WHERE id_apertura = p_id;
        COMMIT;
    END;

    PROCEDURE cerrar(p_id NUMBER, p_usuario NUMBER, p_contado NUMBER,
                     p_observacion VARCHAR2, p_fecha DATE) IS
    BEGIN
        SP_CERRAR_CAJA(p_id, p_usuario, p_contado, p_observacion);
        UPDATE APERTURA_CAJA  SET fecha_cierre  = p_fecha WHERE id_apertura = p_id;
        UPDATE VALE_DESCUENTO SET fecha_emision = p_fecha WHERE id_apertura = p_id;
        COMMIT;
    END;

    -- ===== Cotizaciones =====
    FUNCTION crear_cotizacion(p_cliente NUMBER, p_usuario NUMBER, p_dias NUMBER) RETURN NUMBER IS
        v_id NUMBER;
    BEGIN
        SELECT SEQ_COTIZACION.NEXTVAL INTO v_id FROM DUAL;
        INSERT INTO COTIZACION (id_cotizacion, id_cliente, id_usuario, fecha,
                                fecha_vencimiento, total, estado)
        VALUES (v_id, p_cliente, p_usuario, SYSDATE, TRUNC(SYSDATE) + p_dias, 0, 'A');
        RETURN v_id;
    END;

    PROCEDURE cotizar(p_cotizacion NUMBER, p_producto NUMBER, p_cantidad NUMBER) IS
    BEGIN
        INSERT INTO DETALLE_COTIZACION (id_detalle_cotizacion, id_cotizacion,
                                        id_producto, cantidad, precio, subtotal)
        SELECT SEQ_DETALLE_COTIZACION.NEXTVAL, p_cotizacion, id_producto,
               p_cantidad, precio_venta, p_cantidad * precio_venta
          FROM PRODUCTOS
         WHERE id_producto = p_producto;

        UPDATE COTIZACION
           SET total = (SELECT SUM(subtotal) FROM DETALLE_COTIZACION
                         WHERE id_cotizacion = p_cotizacion)
         WHERE id_cotizacion = p_cotizacion;
    END;

    PROCEDURE fechar_cotizacion(p_cotizacion NUMBER, p_fecha DATE, p_dias NUMBER) IS
    BEGIN
        UPDATE COTIZACION
           SET fecha = p_fecha,
               fecha_vencimiento = TRUNC(p_fecha) + p_dias
         WHERE id_cotizacion = p_cotizacion;
    END;

BEGIN
    -- Usuarios: 1 = admin_marta, 2 = cajero1, 3 = vendedor2, 4 = bodega_lab

    -- ======================= AGOSTO =======================

    -- Compra 1 · Eden S.A. · 03/08
    v_id_compra := crear_compra(1, 4);
    SP_AGREGAR_DETALLE_COMPRA(v_id_compra, 1, 40, 45);
    SP_AGREGAR_DETALLE_COMPRA(v_id_compra, 2, 15, 120);
    SP_AGREGAR_DETALLE_COMPRA(v_id_compra, 5, 60, 30);
    fechar_compra(v_id_compra, DATE '2026-08-03' + 9/24);

    -- Compra 2 · Empresa Global · 05/08
    v_id_compra := crear_compra(2, 4);
    SP_AGREGAR_DETALLE_COMPRA(v_id_compra, 3, 8, 800);
    SP_AGREGAR_DETALLE_COMPRA(v_id_compra, 6, 10, 300);
    SP_AGREGAR_DETALLE_COMPRA(v_id_compra, 11, 4, 1500);
    fechar_compra(v_id_compra, DATE '2026-08-05' + 9/24);

    -- Compra 3 · Ciudad República · 10/08
    v_id_compra := crear_compra(3, 4);
    SP_AGREGAR_DETALLE_COMPRA(v_id_compra, 4, 20, 150);
    SP_AGREGAR_DETALLE_COMPRA(v_id_compra, 10, 15, 90);
    SP_AGREGAR_DETALLE_COMPRA(v_id_compra, 7, 3, 2500);
    SP_AGREGAR_DETALLE_COMPRA(v_id_compra, 8, 5, 900);
    fechar_compra(v_id_compra, DATE '2026-08-10' + 9/24);

    -- Caja 12/08 · cajero1 · cierre cuadrado
    -- Efectivo esperado: 500 + 315 + 390 = 1,205
    abrir(1, 2, 500, DATE '2026-08-12' + 8/24, v_id_apertura);
    v_id_venta := vender(1, 2, 1, 2, 5, 3,       DATE '2026-08-12' + 10/24, 'EFECTIVO');  -- Q315
    v_id_venta := vender(2, 2, 3, 1, NULL, NULL, DATE '2026-08-12' + 12/24, 'TARJETA');   -- Q1,250
    v_id_venta := vender(3, 2, 4, 2, 10, 1,      DATE '2026-08-12' + 15/24, 'MIXTO');     -- Q780 (390 + 390)
    cerrar(v_id_apertura, 2, 1205, NULL, DATE '2026-08-12' + 18/24);

    -- Caja 20/08 · vendedor2 · FALTANTE de Q30 -> vale
    -- Efectivo esperado: 300 + 350 = 650
    abrir(2, 3, 300, DATE '2026-08-20' + 8/24, v_id_apertura);
    v_id_venta := vender(4, 3, 2, 1, 1, 2,       DATE '2026-08-20' + 11/24, 'EFECTIVO');       -- Q350
    v_id_venta := vender(1, 3, 6, 1, NULL, NULL, DATE '2026-08-20' + 16/24, 'TRANSFERENCIA');  -- Q480
    cerrar(v_id_apertura, 3, 620, 'No se encontró el origen de la diferencia', DATE '2026-08-20' + 18/24);
    v_ap_agosto := v_id_apertura;

    -- ======================= SEPTIEMBRE =======================

    -- Cotización que vencerá sin facturarse (quedará CADUCADA)
    v_id_cot := crear_cotizacion(3, 3, 15);
    cotizar(v_id_cot, 3, 2);
    cotizar(v_id_cot, 2, 2);
    fechar_cotizacion(v_id_cot, DATE '2026-09-01' + 10/24, 15);
    COMMIT;

    -- Caja 05/09 · cajero1 · SOBRANTE de Q20 -> solo incidencia
    -- Efectivo esperado: 500 + 1,575 = 2,075
    abrir(1, 2, 500, DATE '2026-09-05' + 8/24, v_id_apertura);
    v_id_venta := vender(5, 2, 7, 1, NULL, NULL, DATE '2026-09-05' + 10/24, 'TARJETA');   -- Q3,800
    v_id_venta := vender(2, 2, 8, 1, 1, 1,       DATE '2026-09-05' + 14/24, 'EFECTIVO');  -- Q1,575
    cerrar(v_id_apertura, 2, 2095, 'Cliente no esperó su cambio', DATE '2026-09-05' + 18/24);

    -- Compra 4 · Comercial La Paz · 15/09
    v_id_compra := crear_compra(4, 4);
    SP_AGREGAR_DETALLE_COMPRA(v_id_compra, 1, 20, 45);
    SP_AGREGAR_DETALLE_COMPRA(v_id_compra, 4, 10, 150);
    fechar_compra(v_id_compra, DATE '2026-09-15' + 9/24);

    -- Caja 18/09 · vendedor2 · FALTANTE de Q50 -> vale (luego anulado por justificación)
    -- Efectivo esperado: 300 + 900 = 1,200
    abrir(2, 3, 300, DATE '2026-09-18' + 8/24, v_id_apertura);
    v_id_venta := vender(3, 3, 4, 3, NULL, NULL,  DATE '2026-09-18' + 10/24, 'EFECTIVO');  -- Q900
    v_id_venta := vender(6, 3, 11, 1, NULL, NULL, DATE '2026-09-18' + 13/24, 'TARJETA');   -- Q2,200
    cerrar(v_id_apertura, 3, 1150, 'Error al dar cambio', DATE '2026-09-18' + 18/24);
    v_ap_sept := v_id_apertura;

    -- ======================= OCTUBRE =======================

    -- Compra 5 · Eden S.A. · 05/10
    v_id_compra := crear_compra(1, 4);
    SP_AGREGAR_DETALLE_COMPRA(v_id_compra, 2, 5, 120);
    SP_AGREGAR_DETALLE_COMPRA(v_id_compra, 5, 30, 30);
    fechar_compra(v_id_compra, DATE '2026-10-05' + 9/24);

    -- Caja 08/10 · cajero1 · una venta ANULADA (autorizada por admin_marta) · cierre cuadrado
    -- Efectivo esperado: 500 + 475 + 360 = 1,335 (la venta anulada no cuenta)
    abrir(1, 2, 500, DATE '2026-10-08' + 8/24, v_id_apertura);
    v_id_venta := vender(1, 2, 5, 10, 2, 2,       DATE '2026-10-08' + 11/24, 'MIXTO');     -- Q950 (475 + 475)
    v_id_venta := vender(4, 2, 10, 2, NULL, NULL, DATE '2026-10-08' + 13/24, 'EFECTIVO');  -- Q360
    v_id_venta := vender(3, 2, 2, 1, NULL, NULL,  DATE '2026-10-08' + 15/24, 'EFECTIVO');  -- Q200
    anular(v_id_venta, 2, 1, 'El cliente desistió de la compra antes de retirar el producto',
           DATE '2026-10-08' + 15.5/24);
    cerrar(v_id_apertura, 2, 1335, NULL, DATE '2026-10-08' + 18/24);

    -- Cotización 10/10 que se convertirá en venta (quedará FACTURADA)
    v_id_cot := crear_cotizacion(2, 3, 15);
    cotizar(v_id_cot, 6, 1);
    cotizar(v_id_cot, 4, 1);
    fechar_cotizacion(v_id_cot, DATE '2026-10-10' + 10/24, 15);
    COMMIT;

    -- Caja 12/10 · vendedor2 · conversión de la cotización + una venta ANULADA · FALTANTE de Q20
    -- Efectivo esperado: 300 + 780 = 1,080 (la venta anulada no cuenta)
    abrir(2, 3, 300, DATE '2026-10-12' + 8/24, v_id_apertura);

    SP_CREAR_VENTA(2, 3, v_id_cot, v_id_venta);
    FOR linea IN (SELECT id_producto, cantidad
                    FROM DETALLE_COTIZACION
                   WHERE id_cotizacion = v_id_cot
                   ORDER BY id_detalle_cotizacion) LOOP
        SP_AGREGAR_DETALLE_VENTA(v_id_venta, linea.id_producto, linea.cantidad);
    END LOOP;
    SELECT total INTO v_total FROM VENTAS WHERE id_venta = v_id_venta;
    pagar(v_id_venta, v_total, 'EFECTIVO');
    SP_FINALIZAR_VENTA(v_id_venta);
    UPDATE VENTAS SET fecha = DATE '2026-10-12' + 11/24 WHERE id_venta = v_id_venta;
    UPDATE KARDEX SET fecha = DATE '2026-10-12' + 11/24 WHERE referencia = 'VENTA #' || v_id_venta;
    COMMIT;                                                                       -- Q780

    v_id_venta := vender(7, 3, 10, 1, NULL, NULL, DATE '2026-10-12' + 14/24, 'EFECTIVO');  -- Q180
    anular(v_id_venta, 3, 1, 'Producto con defecto de fábrica, el cliente lo devolvió',
           DATE '2026-10-12' + 15/24);

    cerrar(v_id_apertura, 3, 1060, 'Billete falso recibido', DATE '2026-10-12' + 18/24);

    -- ======================= VALES =======================
    -- Agosto: aplicado como descuento a fin de mes
    SP_APLICAR_VALES_MES('2026-08', v_cantidad);
    UPDATE VALE_DESCUENTO SET fecha_aplicacion = DATE '2026-08-31' WHERE id_apertura = v_ap_agosto;

    -- Septiembre: anulado por justificación del supervisor
    UPDATE VALE_DESCUENTO
       SET estado = 'N',
           motivo_anulacion = 'Diferencia justificada: error de conteo verificado por el supervisor'
     WHERE id_apertura = v_ap_sept;

    -- Octubre: queda PENDIENTE para el cierre de mes
    COMMIT;

    -- ======================= AUDITORÍA =======================
    -- Cambio de precio hecho por admin_marta: lo registra el trigger TRG_AUDITORIA_PRECIO
    DBMS_SESSION.SET_IDENTIFIER('admin_marta');
    UPDATE PRODUCTOS SET precio_venta = 320 WHERE id_producto = 4;
    DBMS_SESSION.CLEAR_IDENTIFIER;
    COMMIT;

    -- ======================= HOY =======================
    -- Cotización abierta para demostrar la conversión en venta durante la defensa
    v_id_cot := crear_cotizacion(6, 3, 15);
    cotizar(v_id_cot, 3, 1);
    cotizar(v_id_cot, 8, 1);
    COMMIT;

    -- Caja ABIERTA de cajero1 para poder vender desde la aplicación de inmediato
    abrir(1, 2, 400, SYSDATE, v_id_apertura);
    v_id_venta := vender(5, 2, 1, 1, NULL, NULL, SYSDATE, 'EFECTIVO');               -- Q75

    -- Marcar como caducadas las cotizaciones vencidas
    SP_CADUCAR_COTIZACIONES;

    DBMS_OUTPUT.PUT_LINE('Datos de prueba cargados correctamente.');
END;
/

-- Estadísticas actualizadas para que el optimizador use bien los índices
BEGIN
    DBMS_STATS.GATHER_SCHEMA_STATS(USER);
END;
/


-- =============================================================================
-- 11. CONSULTAS DE VERIFICACIÓN
-- =============================================================================

-- 11.1 Cantidad de registros por tabla
SELECT 'ROL' AS tabla, COUNT(*) AS registros FROM ROL
UNION ALL SELECT 'USUARIO',            COUNT(*) FROM USUARIO
UNION ALL SELECT 'USUARIO_ROL',        COUNT(*) FROM USUARIO_ROL
UNION ALL SELECT 'CLIENTES',           COUNT(*) FROM CLIENTES
UNION ALL SELECT 'PROVEEDORES',        COUNT(*) FROM PROVEEDORES
UNION ALL SELECT 'PRODUCTOS',          COUNT(*) FROM PRODUCTOS
UNION ALL SELECT 'CAJA',               COUNT(*) FROM CAJA
UNION ALL SELECT 'APERTURA_CAJA',      COUNT(*) FROM APERTURA_CAJA
UNION ALL SELECT 'COMPRAS',            COUNT(*) FROM COMPRAS
UNION ALL SELECT 'DETALLE_COMPRA',     COUNT(*) FROM DETALLE_COMPRA
UNION ALL SELECT 'VENTAS',             COUNT(*) FROM VENTAS
UNION ALL SELECT 'DETALLE_VENTA',      COUNT(*) FROM DETALLE_VENTA
UNION ALL SELECT 'METODO_PAGO',        COUNT(*) FROM METODO_PAGO
UNION ALL SELECT 'PAGO_VENTA',         COUNT(*) FROM PAGO_VENTA
UNION ALL SELECT 'COTIZACION',         COUNT(*) FROM COTIZACION
UNION ALL SELECT 'DETALLE_COTIZACION', COUNT(*) FROM DETALLE_COTIZACION
UNION ALL SELECT 'KARDEX',             COUNT(*) FROM KARDEX
UNION ALL SELECT 'AUDITORIA_PRODUCTO', COUNT(*) FROM AUDITORIA_PRODUCTO
UNION ALL SELECT 'VALE_DESCUENTO',     COUNT(*) FROM VALE_DESCUENTO
UNION ALL SELECT 'POLITICA_SANCION',   COUNT(*) FROM POLITICA_SANCION;

-- 11.2 Inventario: el stock debe coincidir con entradas - salidas del Kardex
SELECT p.id_producto,
       p.nombre,
       p.stock AS stock_tabla,
       NVL(SUM(k.cantidad_entrada), 0) - NVL(SUM(k.cantidad_salida), 0) AS stock_segun_kardex,
       CASE WHEN p.stock = NVL(SUM(k.cantidad_entrada), 0) - NVL(SUM(k.cantidad_salida), 0)
            THEN 'OK' ELSE 'DESCUADRE' END AS verificacion
FROM PRODUCTOS p
LEFT JOIN KARDEX k ON p.id_producto = k.id_producto
GROUP BY p.id_producto, p.nombre, p.stock
ORDER BY p.id_producto;

-- 11.3 Ventas: el total debe ser la suma de sus detalles
SELECT v.id_venta,
       v.estado,
       v.total,
       SUM(d.subtotal) AS suma_detalle,
       CASE WHEN v.total = SUM(d.subtotal) THEN 'OK' ELSE 'DESCUADRE' END AS verificacion
FROM VENTAS v
JOIN DETALLE_VENTA d ON v.id_venta = d.id_venta
GROUP BY v.id_venta, v.estado, v.total
ORDER BY v.id_venta;

-- 11.4 Pagos: la suma de los pagos debe ser igual al total de cada venta
SELECT v.id_venta,
       v.total,
       NVL(SUM(p.monto), 0) AS pagado,
       CASE WHEN v.total = NVL(SUM(p.monto), 0) THEN 'OK' ELSE 'DESCUADRE' END AS verificacion
FROM VENTAS v
LEFT JOIN PAGO_VENTA p ON v.id_venta = p.id_venta
GROUP BY v.id_venta, v.total
ORDER BY v.id_venta;

-- 11.5 Caja: monto esperado = monto inicial + efectivo de las ventas activas
SELECT a.id_apertura,
       u.usuario,
       a.estado,
       a.monto_inicial,
       FN_EFECTIVO_APERTURA(a.id_apertura) AS efectivo_ventas,
       a.monto_esperado,
       a.monto_contado,
       a.diferencia,
       CASE WHEN a.monto_esperado = a.monto_inicial + FN_EFECTIVO_APERTURA(a.id_apertura)
            THEN 'OK' ELSE 'DESCUADRE' END AS verificacion
FROM APERTURA_CAJA a
JOIN USUARIO u ON a.id_usuario = u.id_usuario
ORDER BY a.id_apertura;

-- 11.6 Vistas
SELECT * FROM VW_RESUMEN_VENTAS ORDER BY id_venta;
SELECT * FROM VW_PRODUCTOS_BAJO_STOCK ORDER BY stock;
SELECT * FROM VW_VENTAS_POR_PRODUCTO ORDER BY unidades_vendidas DESC;
SELECT * FROM VW_INCIDENCIAS_CAJA ORDER BY fecha_cierre;
SELECT * FROM VW_ANULACIONES_VENTA ORDER BY fecha_anulacion;
SELECT * FROM VW_SANCIONES_MES ORDER BY mes, total_incidencias DESC;

-- 11.7 Funciones dentro de consultas
SELECT id_producto, nombre, FN_STOCK_PRODUCTO(id_producto) AS stock
FROM PRODUCTOS
ORDER BY id_producto;

SELECT id_apertura, FN_EFECTIVO_APERTURA(id_apertura) AS efectivo
FROM APERTURA_CAJA
ORDER BY id_apertura;

-- 11.8 Estados de cotizaciones (A=Abierta, C=Caducada, F=Facturada)
SELECT c.id_cotizacion, cl.nombre AS cliente, c.fecha, c.fecha_vencimiento, c.total, c.estado,
       (SELECT v.id_venta FROM VENTAS v WHERE v.id_cotizacion = c.id_cotizacion) AS venta_generada
FROM COTIZACION c
JOIN CLIENTES cl ON c.id_cliente = cl.id_cliente
ORDER BY c.id_cotizacion;

-- 11.9 Cobros por método de pago (solo ventas activas)
SELECT m.nombre AS metodo, COUNT(p.id_pago) AS pagos, SUM(p.monto) AS total
FROM PAGO_VENTA p
JOIN METODO_PAGO m ON p.id_metodo = m.id_metodo
JOIN VENTAS v      ON p.id_venta = v.id_venta
WHERE v.estado = 'A'
GROUP BY m.nombre
ORDER BY total DESC;

-- 11.10 Vales de descuento y auditoría de precios
SELECT * FROM VALE_DESCUENTO ORDER BY id_vale;
SELECT * FROM AUDITORIA_PRODUCTO ORDER BY id_auditoria;

-- 11.11 JOIN + GROUP BY + HAVING: clientes que compraron más de Q1,000 (ventas activas)
SELECT c.nombre, COUNT(v.id_venta) AS compras, SUM(v.total) AS total_comprado
FROM CLIENTES c
JOIN VENTAS v ON c.id_cliente = v.id_cliente
WHERE v.estado = 'A'
GROUP BY c.nombre
HAVING SUM(v.total) > 1000
ORDER BY total_comprado DESC;

-- 11.12 Subconsulta: productos que no aparecen en ninguna venta activa
SELECT id_producto, nombre, stock, estado
FROM PRODUCTOS
WHERE id_producto NOT IN (SELECT d.id_producto
                            FROM DETALLE_VENTA d
                            JOIN VENTAS v ON d.id_venta = v.id_venta
                           WHERE v.estado = 'A')
ORDER BY id_producto;

-- 11.13 Job programado
SELECT job_name, enabled, state, repeat_interval,
       TO_CHAR(next_run_date, 'DD/MM/YYYY HH24:MI') AS proxima_ejecucion
FROM USER_SCHEDULER_JOBS;

-- 11.14 Llaves foráneas sin índice (debe devolver 0 filas)
SELECT c.table_name AS tabla, cc.column_name AS columna, c.constraint_name AS llave_foranea
FROM USER_CONSTRAINTS c
JOIN USER_CONS_COLUMNS cc ON c.constraint_name = cc.constraint_name
WHERE c.constraint_type = 'R'
  AND NOT EXISTS (SELECT 1
                    FROM USER_IND_COLUMNS ic
                   WHERE ic.table_name      = cc.table_name
                     AND ic.column_name     = cc.column_name
                     AND ic.column_position = 1)
ORDER BY c.table_name, cc.column_name;

-- 11.15 Plan de ejecución: historial del Kardex de un producto
EXPLAIN PLAN FOR
SELECT k.fecha, k.tipo_movimiento, k.cantidad_entrada, k.cantidad_salida, k.existencia_final
FROM KARDEX k
WHERE k.id_producto = 4
ORDER BY k.fecha;

SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY);


-- =============================================================================
-- 12. PRUEBAS DE REGLAS DE NEGOCIO Y MANEJO DE ERRORES
--     Ninguna de estas pruebas deja cambios en la base de datos.
-- =============================================================================

-- 12.1 ROLLBACK: la venta se registra completa y luego se deshace
DECLARE
    v_id_venta     NUMBER;
    v_total        NUMBER;
    v_stock_antes  NUMBER;
    v_existe       NUMBER;
BEGIN
    v_stock_antes := FN_STOCK_PRODUCTO(1);

    SP_CREAR_VENTA(1, 2, NULL, v_id_venta);          -- cajero1 tiene una caja abierta
    SP_AGREGAR_DETALLE_VENTA(v_id_venta, 1, 2);
    SELECT total INTO v_total FROM VENTAS WHERE id_venta = v_id_venta;
    SP_AGREGAR_PAGO_VENTA(v_id_venta, 1, v_total, NULL, NULL);
    SP_FINALIZAR_VENTA(v_id_venta);

    DBMS_OUTPUT.PUT_LINE('Antes del ROLLBACK -> venta #' || v_id_venta ||
                         ' | stock del producto 1: ' || FN_STOCK_PRODUCTO(1) ||
                         ' (antes era ' || v_stock_antes || ')');

    ROLLBACK;

    SELECT COUNT(*) INTO v_existe FROM VENTAS WHERE id_venta = v_id_venta;
    DBMS_OUTPUT.PUT_LINE('Después del ROLLBACK -> ventas con ese número: ' || v_existe ||
                         ' | stock del producto 1: ' || FN_STOCK_PRODUCTO(1));
END;
/

-- 12.2 Stock insuficiente: Oracle rechaza la venta y no queda nada registrado
DECLARE
    v_id_venta NUMBER;
BEGIN
    SP_CREAR_VENTA(1, 2, NULL, v_id_venta);
    SP_AGREGAR_DETALLE_VENTA(v_id_venta, 7, 100);    -- solo hay 2 proyectores
    COMMIT;
EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        DBMS_OUTPUT.PUT_LINE('Operación rechazada: ' || SQLERRM);
END;
/

-- 12.3 Producto inexistente (NO_DATA_FOUND controlado en la función)
DECLARE
    v_stock NUMBER;
BEGIN
    v_stock := FN_STOCK_PRODUCTO(9999);
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Consulta rechazada: ' || SQLERRM);
END;
/

-- 12.4 Vender sin caja abierta (admin_marta no tiene caja)
DECLARE
    v_id_venta NUMBER;
BEGIN
    SP_CREAR_VENTA(1, 1, NULL, v_id_venta);
EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        DBMS_OUTPUT.PUT_LINE('Venta rechazada: ' || SQLERRM);
END;
/

-- 12.5 Los pagos deben cubrir exactamente el total
DECLARE
    v_id_venta NUMBER;
BEGIN
    SP_CREAR_VENTA(1, 2, NULL, v_id_venta);
    SP_AGREGAR_DETALLE_VENTA(v_id_venta, 1, 2);
    SP_AGREGAR_PAGO_VENTA(v_id_venta, 1, 10, NULL, NULL);   -- solo Q10 de Q150
    SP_FINALIZAR_VENTA(v_id_venta);
    COMMIT;
EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        DBMS_OUTPUT.PUT_LINE('Venta rechazada: ' || SQLERRM);
END;
/

-- 12.6 La tarjeta requiere número de autorización
DECLARE
    v_id_venta NUMBER;
BEGIN
    SP_CREAR_VENTA(1, 2, NULL, v_id_venta);
    SP_AGREGAR_DETALLE_VENTA(v_id_venta, 1, 1);
    SP_AGREGAR_PAGO_VENTA(v_id_venta, 2, 75, NULL, NULL);   -- tarjeta sin referencia
    COMMIT;
EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        DBMS_OUTPUT.PUT_LINE('Pago rechazado: ' || SQLERRM);
END;
/

-- 12.7 Una anulación sin autorización de un administrador es rechazada
DECLARE
    v_id_venta NUMBER;
BEGIN
    SELECT MAX(v.id_venta) INTO v_id_venta
      FROM VENTAS v
      JOIN APERTURA_CAJA a ON v.id_apertura = a.id_apertura
     WHERE v.estado = 'A' AND a.estado = 'A';

    SP_ANULAR_VENTA(v_id_venta, 2, 2, 'Prueba sin autorización');   -- 2 = cajero1
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Anulación rechazada: ' || SQLERRM);
END;
/

-- 12.8 No se puede anular una venta de una caja ya cerrada
DECLARE
    v_id_venta NUMBER;
BEGIN
    SELECT MIN(id_venta) INTO v_id_venta FROM VENTAS WHERE estado = 'A';
    SP_ANULAR_VENTA(v_id_venta, 1, 1, 'Prueba sobre caja cerrada');
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Anulación rechazada: ' || SQLERRM);
END;
/

-- 12.9 CHECK de varias columnas: una venta anulada debe tener fecha, usuarios y motivo
BEGIN
    UPDATE VENTAS SET estado = 'N'
     WHERE id_venta = (SELECT MIN(id_venta) FROM VENTAS WHERE estado = 'A');
EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        DBMS_OUTPUT.PUT_LINE('Regla de anulación en acción: ' || SQLERRM);
END;
/

-- 12.10 CHECK: el stock nunca puede quedar negativo
BEGIN
    UPDATE PRODUCTOS SET stock = -5 WHERE id_producto = 1;
EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        DBMS_OUTPUT.PUT_LINE('CHECK en acción: ' || SQLERRM);
END;
/

-- 12.11 Integridad referencial: no se puede eliminar un cliente con ventas
BEGIN
    DELETE FROM CLIENTES WHERE id_cliente = 1;
EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        DBMS_OUTPUT.PUT_LINE('FK en acción: ' || SQLERRM);
END;
/

-- 12.12 CHECK de dos columnas: un vale anulado debe tener motivo
BEGIN
    UPDATE VALE_DESCUENTO SET estado = 'N' WHERE estado = 'P';
EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        DBMS_OUTPUT.PUT_LINE('Regla del vale en acción: ' || SQLERRM);
END;
/

-- 12.13 UNIQUE: no se puede repetir el NIT de un proveedor
BEGIN
    INSERT INTO PROVEEDORES (id_proveedor, nombre, direccion, telefono, nit)
    VALUES (SEQ_PROVEEDOR.NEXTVAL, 'Proveedor duplicado', 'Guatemala', '22223333', '1234567-4');
EXCEPTION
    WHEN DUP_VAL_ON_INDEX THEN
        ROLLBACK;
        DBMS_OUTPUT.PUT_LINE('UNIQUE en acción: ya existe un proveedor con ese NIT.');
END;
/

-- =============================================================================
-- FIN DEL SCRIPT PRINCIPAL
-- =============================================================================


/* =============================================================================
   ANEXO A — DCL: ROLES, USUARIOS Y PRIVILEGIOS DE ORACLE
   -----------------------------------------------------------------------------
   Se ejecuta APARTE, conectado como SYSDBA en XEPDB1.
   Orden de instalación:
     1. (SYSDBA)          Crear el usuario SISTEMA_VENTAS y darle sus privilegios.
     2. (SISTEMA_VENTAS)  Ejecutar el script principal con F5.
     3. (SYSDBA)          Ejecutar los GRANT sobre las tablas para los roles.
   Si los roles o usuarios ya existen (creados en el Laboratorio 1),
   omita las sentencias CREATE ROLE y CREATE USER y ejecute solo los GRANT.
   ============================================================================= */
/*
-- 1. Dueño del esquema
CREATE USER sistema_ventas IDENTIFIED BY "12345"
    DEFAULT TABLESPACE USERS QUOTA UNLIMITED ON USERS;

GRANT CREATE SESSION, CREATE TABLE, CREATE VIEW, CREATE SEQUENCE,
      CREATE PROCEDURE, CREATE TRIGGER, CREATE JOB TO sistema_ventas;

-- 2. Roles
CREATE ROLE R_ADMINISTRADOR;
CREATE ROLE R_VENDEDOR;
CREATE ROLE R_CAJERO;
CREATE ROLE R_BODEGUERO;
CREATE ROLE R_CONSULTOR_PRODUCTO;

GRANT CREATE SESSION TO R_ADMINISTRADOR, R_VENDEDOR, R_CAJERO, R_BODEGUERO, R_CONSULTOR_PRODUCTO;

-- 3. Privilegios por rol (después de ejecutar el script principal)

-- CONSULTOR: solo lectura de productos
GRANT SELECT ON SISTEMA_VENTAS.PRODUCTOS TO R_CONSULTOR_PRODUCTO;

-- VENDEDOR: clientes, cotizaciones, ventas y pagos
GRANT SELECT, INSERT, UPDATE ON SISTEMA_VENTAS.CLIENTES           TO R_VENDEDOR;
GRANT SELECT                 ON SISTEMA_VENTAS.PRODUCTOS          TO R_VENDEDOR;
GRANT SELECT, INSERT, UPDATE ON SISTEMA_VENTAS.COTIZACION         TO R_VENDEDOR;
GRANT SELECT, INSERT, UPDATE ON SISTEMA_VENTAS.DETALLE_COTIZACION TO R_VENDEDOR;
GRANT SELECT, INSERT         ON SISTEMA_VENTAS.VENTAS             TO R_VENDEDOR;
GRANT SELECT, INSERT         ON SISTEMA_VENTAS.DETALLE_VENTA      TO R_VENDEDOR;
GRANT SELECT                 ON SISTEMA_VENTAS.METODO_PAGO        TO R_VENDEDOR;
GRANT SELECT, INSERT         ON SISTEMA_VENTAS.PAGO_VENTA         TO R_VENDEDOR;

-- CAJERO: aperturas y cierres de caja, consulta de ventas y pagos
GRANT SELECT                 ON SISTEMA_VENTAS.CAJA               TO R_CAJERO;
GRANT SELECT, INSERT, UPDATE ON SISTEMA_VENTAS.APERTURA_CAJA      TO R_CAJERO;
GRANT SELECT                 ON SISTEMA_VENTAS.VENTAS             TO R_CAJERO;
GRANT SELECT                 ON SISTEMA_VENTAS.CLIENTES           TO R_CAJERO;
GRANT SELECT                 ON SISTEMA_VENTAS.METODO_PAGO        TO R_CAJERO;
GRANT SELECT                 ON SISTEMA_VENTAS.PAGO_VENTA         TO R_CAJERO;

-- BODEGUERO: productos, compras y Kardex (sin acceso a USUARIO)
GRANT SELECT, INSERT, UPDATE ON SISTEMA_VENTAS.PRODUCTOS          TO R_BODEGUERO;
GRANT SELECT, INSERT, UPDATE ON SISTEMA_VENTAS.COMPRAS            TO R_BODEGUERO;
GRANT SELECT, INSERT, UPDATE ON SISTEMA_VENTAS.DETALLE_COMPRA     TO R_BODEGUERO;
GRANT SELECT                 ON SISTEMA_VENTAS.PROVEEDORES        TO R_BODEGUERO;
GRANT SELECT, INSERT         ON SISTEMA_VENTAS.KARDEX             TO R_BODEGUERO;

-- ADMINISTRADOR: consulta de todas las tablas y reportes
GRANT SELECT ON SISTEMA_VENTAS.USUARIO              TO R_ADMINISTRADOR;
GRANT SELECT ON SISTEMA_VENTAS.ROL                  TO R_ADMINISTRADOR;
GRANT SELECT ON SISTEMA_VENTAS.USUARIO_ROL          TO R_ADMINISTRADOR;
GRANT SELECT ON SISTEMA_VENTAS.VENTAS               TO R_ADMINISTRADOR;
GRANT SELECT ON SISTEMA_VENTAS.PAGO_VENTA           TO R_ADMINISTRADOR;
GRANT SELECT ON SISTEMA_VENTAS.COMPRAS              TO R_ADMINISTRADOR;
GRANT SELECT ON SISTEMA_VENTAS.KARDEX               TO R_ADMINISTRADOR;
GRANT SELECT ON SISTEMA_VENTAS.APERTURA_CAJA        TO R_ADMINISTRADOR;
GRANT SELECT ON SISTEMA_VENTAS.VALE_DESCUENTO       TO R_ADMINISTRADOR;
GRANT SELECT ON SISTEMA_VENTAS.POLITICA_SANCION     TO R_ADMINISTRADOR;
GRANT SELECT ON SISTEMA_VENTAS.AUDITORIA_PRODUCTO   TO R_ADMINISTRADOR;
GRANT SELECT ON SISTEMA_VENTAS.VW_RESUMEN_VENTAS    TO R_ADMINISTRADOR;
GRANT SELECT ON SISTEMA_VENTAS.VW_INCIDENCIAS_CAJA  TO R_ADMINISTRADOR;
GRANT SELECT ON SISTEMA_VENTAS.VW_ANULACIONES_VENTA TO R_ADMINISTRADOR;
GRANT SELECT ON SISTEMA_VENTAS.VW_SANCIONES_MES     TO R_ADMINISTRADOR;

-- 4. Usuarios de base de datos
CREATE USER usr_consulta  IDENTIFIED BY "Consulta1234#";
CREATE USER usr_vendedor  IDENTIFIED BY "Vendedor1234#";
CREATE USER usr_bodeguero IDENTIFIED BY "Bodeguero1234#";

GRANT R_CONSULTOR_PRODUCTO TO usr_consulta;
GRANT R_VENDEDOR           TO usr_vendedor;
GRANT R_BODEGUERO          TO usr_bodeguero;

-- 5. Ejemplo de REVOKE (principio de menor privilegio)
REVOKE UPDATE ON SISTEMA_VENTAS.CLIENTES FROM R_VENDEDOR;
GRANT  UPDATE ON SISTEMA_VENTAS.CLIENTES TO   R_VENDEDOR;

-- 6. Prueba (conectado como usr_vendedor)
--    SELECT * FROM SISTEMA_VENTAS.CLIENTES;   -- funciona
--    SELECT * FROM SISTEMA_VENTAS.USUARIO;    -- ORA-00942 (sin permiso)
*/


/* =============================================================================
   ANEXO B — RESPALDO Y RESTAURACIÓN CON DATA PUMP
   -----------------------------------------------------------------------------
   1. Crear la carpeta C:\respaldos_oracle en Windows.

   2. Como SYSDBA en XEPDB1:
        CREATE OR REPLACE DIRECTORY DIR_RESPALDOS AS 'C:\respaldos_oracle';
        GRANT READ, WRITE ON DIRECTORY DIR_RESPALDOS TO sistema_ventas;

   3. Respaldo (en CMD):
        expdp sistema_ventas@localhost:1521/xepdb1 SCHEMAS=sistema_ventas
              DIRECTORY=DIR_RESPALDOS DUMPFILE=sistema_ventas.dmp
              LOGFILE=exp_sistema_ventas.log

   4. Restauración de prueba en otro esquema:
        -- Como SYSDBA:
        CREATE USER sistema_ventas_rest IDENTIFIED BY "12345"
            DEFAULT TABLESPACE USERS QUOTA UNLIMITED ON USERS;
        GRANT CREATE SESSION TO sistema_ventas_rest;

        -- En CMD:
        impdp system@localhost:1521/xepdb1 DIRECTORY=DIR_RESPALDOS
              DUMPFILE=sistema_ventas.dmp LOGFILE=imp_sistema_ventas_rest.log
              REMAP_SCHEMA=sistema_ventas:sistema_ventas_rest EXCLUDE=PROCOBJ

        -- Al terminar, como SYSDBA:
        DROP USER sistema_ventas_rest CASCADE;

   (Cada comando de CMD se escribe en una sola línea.)
   ============================================================================= */
