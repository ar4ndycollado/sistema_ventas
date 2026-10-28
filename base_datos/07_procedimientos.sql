-- Procedimientos almacenados
-- Generado desde el esquema SISTEMA_VENTAS (Oracle 21c XE)

CREATE OR REPLACE EDITIONABLE PROCEDURE "SP_ABRIR_CAJA" (
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

CREATE OR REPLACE EDITIONABLE PROCEDURE "SP_AGREGAR_DETALLE_COMPRA" (
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

CREATE OR REPLACE EDITIONABLE PROCEDURE "SP_AGREGAR_DETALLE_VENTA" (
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

CREATE OR REPLACE EDITIONABLE PROCEDURE "SP_AGREGAR_PAGO_VENTA" (
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

CREATE OR REPLACE EDITIONABLE PROCEDURE "SP_ANULAR_VENTA" (
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

CREATE OR REPLACE EDITIONABLE PROCEDURE "SP_APLICAR_VALES_MES" (
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

CREATE OR REPLACE EDITIONABLE PROCEDURE "SP_CADUCAR_COTIZACIONES" 
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

CREATE OR REPLACE EDITIONABLE PROCEDURE "SP_CERRAR_CAJA" (
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

CREATE OR REPLACE EDITIONABLE PROCEDURE "SP_CREAR_VENTA" (
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

CREATE OR REPLACE EDITIONABLE PROCEDURE "SP_FINALIZAR_VENTA" (
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

CREATE OR REPLACE EDITIONABLE PROCEDURE "SP_PROCESAR_VENTA" (
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

CREATE OR REPLACE EDITIONABLE PROCEDURE "SP_REGISTRAR_CLIENTE" (
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

CREATE OR REPLACE EDITIONABLE PROCEDURE "SP_REGISTRAR_DETALLE_COMPRA" (
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

CREATE OR REPLACE EDITIONABLE PROCEDURE "SP_REGISTRAR_DETALLE_VENTA" (
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

CREATE OR REPLACE EDITIONABLE PROCEDURE "SP_VENTA_TRANSACCION" (
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
