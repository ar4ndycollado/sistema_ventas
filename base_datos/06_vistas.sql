-- Vistas
-- Generado desde el esquema SISTEMA_VENTAS (Oracle 21c XE)

CREATE OR REPLACE FORCE EDITIONABLE VIEW "VW_ANULACIONES_VENTA" ("ID_VENTA", "FECHA", "FECHA_ANULACION", "VENDEDOR", "ANULADO_POR", "AUTORIZADO_POR", "CLIENTE", "TOTAL", "MOTIVO_ANULACION", "ID_APERTURA") AS 
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

CREATE OR REPLACE FORCE EDITIONABLE VIEW "VW_INCIDENCIAS_CAJA" ("ID_APERTURA", "ID_USUARIO", "USUARIO", "CAJA", "FECHA_CIERRE", "TIPO", "MONTO", "OBSERVACION_CIERRE", "ID_VALE", "ESTADO_VALE") AS 
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

CREATE OR REPLACE FORCE EDITIONABLE VIEW "VW_PRODUCTOS_BAJO_STOCK" ("ID_PRODUCTO", "PRODUCTO", "STOCK", "STOCK_MINIMO") AS 
  SELECT id_producto,
       nombre AS producto,
       stock,
       stock_minimo
FROM PRODUCTOS
WHERE stock <= stock_minimo;

CREATE OR REPLACE FORCE EDITIONABLE VIEW "VW_RESUMEN_VENTAS" ("ID_VENTA", "FECHA", "CLIENTE", "USUARIO", "TOTAL", "ESTADO") AS 
  SELECT v.id_venta,
       TO_CHAR(v.fecha, 'DD/MM/YYYY') AS fecha,
       c.nombre  AS cliente,
       u.usuario AS usuario,
       v.total,
       v.estado
FROM VENTAS v
INNER JOIN CLIENTES c ON v.id_cliente = c.id_cliente
INNER JOIN USUARIO u  ON v.id_usuario = u.id_usuario;

CREATE OR REPLACE FORCE EDITIONABLE VIEW "VW_SANCIONES_MES" ("MES", "USUARIO", "FALTANTES", "MONTO_FALTANTE", "ANULACIONES", "TOTAL_INCIDENCIAS", "SANCION_SUGERIDA") AS 
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

CREATE OR REPLACE FORCE EDITIONABLE VIEW "VW_VENTAS_POR_PRODUCTO" ("ID_PRODUCTO", "NOMBRE", "UNIDADES_VENDIDAS", "TOTAL_VENDIDO") AS 
  SELECT p.id_producto,
       p.nombre,
       SUM(d.cantidad)  AS unidades_vendidas,
       SUM(d.subtotal)  AS total_vendido
FROM DETALLE_VENTA d
JOIN VENTAS v    ON d.id_venta = v.id_venta
JOIN PRODUCTOS p ON d.id_producto = p.id_producto
WHERE v.estado = 'A'
GROUP BY p.id_producto, p.nombre;
