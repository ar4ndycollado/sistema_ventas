-- Funciones
-- Generado desde el esquema SISTEMA_VENTAS (Oracle 21c XE)

CREATE OR REPLACE EDITIONABLE FUNCTION "FN_EFECTIVO_APERTURA" (
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

CREATE OR REPLACE EDITIONABLE FUNCTION "FN_STOCK_PRODUCTO" (
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
