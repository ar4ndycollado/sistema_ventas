-- Triggers
-- Generado desde el esquema SISTEMA_VENTAS (Oracle 21c XE)

CREATE OR REPLACE EDITIONABLE TRIGGER "TRG_AUDITORIA_PRECIO" 
AFTER UPDATE OF precio_venta ON PRODUCTOS
FOR EACH ROW
 WHEN (OLD.precio_venta <> NEW.precio_venta) BEGIN
    INSERT INTO AUDITORIA_PRODUCTO (id_auditoria, id_producto, precio_anterior,
                                    precio_nuevo, usuario, fecha, tipo_operacion)
    VALUES (SEQ_AUDITORIA_PRODUCTO.NEXTVAL, :OLD.id_producto, :OLD.precio_venta,
            :NEW.precio_venta,
            NVL(SYS_CONTEXT('USERENV', 'CLIENT_IDENTIFIER'), USER),
            SYSDATE, 'UPDATE PRECIO');
END TRG_AUDITORIA_PRECIO;

/
ALTER TRIGGER "TRG_AUDITORIA_PRECIO" ENABLE;

CREATE OR REPLACE EDITIONABLE TRIGGER "TRG_VALE_FALTANTE" 
AFTER UPDATE OF estado ON APERTURA_CAJA
FOR EACH ROW
 WHEN (OLD.estado = 'A' AND NEW.estado = 'C' AND NEW.diferencia < 0) BEGIN
    INSERT INTO VALE_DESCUENTO (id_vale, id_apertura, monto, estado, fecha_emision)
    VALUES (SEQ_VALE.NEXTVAL, :NEW.id_apertura, ABS(:NEW.diferencia), 'P', SYSDATE);
END TRG_VALE_FALTANTE;

/
ALTER TRIGGER "TRG_VALE_FALTANTE" ENABLE;
