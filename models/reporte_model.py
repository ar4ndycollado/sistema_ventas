# models/reporte_model.py
# MODELO: consultas para reportes (agregación, GROUP BY, HAVING, subconsultas y vistas).
# Casi todos los reportes cuentan solo ventas ACTIVAS (estado = 'A'):
# una venta anulada no es un ingreso real.

from models.conexion import obtener_conexion


def indicadores_ventas():
    """Agregación condicional: indicadores de las ventas ACTIVAS y conteo de anuladas."""
    with obtener_conexion() as conexion:
        with conexion.cursor() as cursor:
            # COUNT, SUM, AVG, MAX y MIN en una sola consulta. El CASE deja pasar
            # solo las ventas activas; las anuladas se cuentan en la última columna.
            # NVL(…, 0) devuelve 0 en lugar de NULL si todavía no hay ventas.
            cursor.execute("""
                SELECT COUNT(CASE WHEN estado = 'A' THEN 1 END),
                    NVL(SUM(CASE WHEN estado = 'A' THEN total END), 0),
                    NVL(AVG(CASE WHEN estado = 'A' THEN total END), 0),
                    NVL(MAX(CASE WHEN estado = 'A' THEN total END), 0),
                    NVL(MIN(CASE WHEN estado = 'A' THEN total END), 0),
                    COUNT(CASE WHEN estado = 'N' THEN 1 END)
                FROM VENTAS
            """)
            fila = cursor.fetchone()
            return {
                "cantidad": fila[0],
                "total": fila[1],
                "promedio": fila[2],
                "maxima": fila[3],
                "minima": fila[4],
                "anuladas": fila[5]
            }


def valor_inventario():
    """Cuánto vale el inventario de productos activos: a precio de costo y a precio de venta.
    La diferencia entre ambos es la ganancia esperada si se vendiera todo."""
    with obtener_conexion() as conexion:
        with conexion.cursor() as cursor:
            cursor.execute("""
                SELECT COUNT(id_producto),
                    NVL(SUM(stock), 0),
                       NVL(SUM(stock * precio_compra), 0),
                       NVL(SUM(stock * precio_venta), 0)
                FROM PRODUCTOS
                WHERE estado = 'A'
            """)
            fila = cursor.fetchone()
            return {
                "productos": fila[0],
                "unidades": fila[1],
                "valor_costo": fila[2],
                "valor_venta": fila[3]
            }


def ventas_por_cliente(monto_minimo):
    """GROUP BY + HAVING: clientes cuyo total comprado supera el monto indicado."""
    clientes = []
    with obtener_conexion() as conexion:
        with conexion.cursor() as cursor:
            # WHERE filtra filas ANTES de agrupar (solo ventas activas);
            # HAVING filtra los grupos DESPUÉS de sumar (total del cliente >= mínimo)
            cursor.execute("""
                SELECT c.nombre,
                    COUNT(v.id_venta),
                    SUM(v.total),
                    MAX(v.fecha)
                FROM CLIENTES c
                JOIN VENTAS v ON c.id_cliente = v.id_cliente
                WHERE v.estado = 'A'
                GROUP BY c.id_cliente, c.nombre
                HAVING SUM(v.total) >= :monto_minimo
                ORDER BY SUM(v.total) DESC
            """, {"monto_minimo": monto_minimo})
            for fila in cursor.fetchall():
                clientes.append({
                    "cliente": fila[0],
                    "compras": fila[1],
                    "total": fila[2],
                    "ultima_compra": fila[3].strftime("%d/%m/%Y")   # fecha → texto día/mes/año
                })
    return clientes



def productos_mas_vendidos():
    """Top 5 de productos por unidades vendidas. Usa la vista VW_VENTAS_POR_PRODUCTO,
    que ya suma las ventas activas por producto."""
    productos = []
    with obtener_conexion() as conexion:
        with conexion.cursor() as cursor:
            cursor.execute("""
                SELECT nombre, unidades_vendidas, total_vendido
                FROM VW_VENTAS_POR_PRODUCTO
                ORDER BY unidades_vendidas DESC
                FETCH FIRST 5 ROWS ONLY
            """)
            for fila in cursor.fetchall():
                productos.append({
                    "nombre": fila[0],
                    "unidades": fila[1],
                    "total": fila[2]
                })
    return productos


def productos_sin_ventas():
    """Subconsulta: productos que no aparecen en ninguna venta ACTIVA."""
    productos = []
    with obtener_conexion() as conexion:
        with conexion.cursor() as cursor:
            # La subconsulta (entre paréntesis) devuelve los productos que sí se vendieron;
            # NOT IN se queda con los que no están en esa lista
            cursor.execute("""
                SELECT id_producto, nombre, stock, estado
                FROM PRODUCTOS
                WHERE id_producto NOT IN (SELECT d.id_producto
                                            FROM DETALLE_VENTA d
                                            JOIN VENTAS v ON d.id_venta = v.id_venta
                                        WHERE v.estado = 'A')
                ORDER BY nombre
            """)
            for fila in cursor.fetchall():
                productos.append({
                    "id_producto": fila[0],
                    "nombre": fila[1],
                    "stock": fila[2],
                    "estado": fila[3]
                })
    return productos


def ventas_por_usuario():
    """Cantidad, total y promedio vendido por cada usuario (GROUP BY)."""
    usuarios = []
    with obtener_conexion() as conexion:
        with conexion.cursor() as cursor:
            cursor.execute("""
                SELECT u.usuario,
                    COUNT(v.id_venta),
                    SUM(v.total),
                    AVG(v.total)
                FROM USUARIO u
                JOIN VENTAS v ON u.id_usuario = v.id_usuario
                WHERE v.estado = 'A'
                GROUP BY u.usuario
                ORDER BY SUM(v.total) DESC
            """)
            for fila in cursor.fetchall():
                usuarios.append({
                    "usuario": fila[0],
                    "ventas": fila[1],
                    "total": fila[2],
                    "promedio": fila[3]
                })
    return usuarios


def ventas_por_mes():
    """Cantidad y total de ventas por mes, del más antiguo al más reciente."""
    meses = []
    with obtener_conexion() as conexion:
        with conexion.cursor() as cursor:
            # TO_CHAR(fecha, 'YYYY-MM') convierte cada fecha en su mes (ej. '2026-10')
            # para agrupar todas las ventas de ese mes
            cursor.execute("""
                SELECT TO_CHAR(fecha, 'YYYY-MM') AS mes,
                    COUNT(id_venta),
                    SUM(total)
                FROM VENTAS
                WHERE estado = 'A'
                GROUP BY TO_CHAR(fecha, 'YYYY-MM')
                ORDER BY mes
            """)
            for fila in cursor.fetchall():
                meses.append({
                    "mes": fila[0],
                    "ventas": fila[1],
                    "total": fila[2]
                })
    return meses

def ventas_por_metodo():
    """Cuánto se cobró con cada método de pago (solo ventas activas)."""
    metodos = []
    with obtener_conexion() as conexion:
        with conexion.cursor() as cursor:
            # JOIN con VENTAS solo para poder filtrar por el estado de la venta
            cursor.execute("""
                SELECT m.nombre,
                    COUNT(p.id_pago),
                    SUM(p.monto)
                FROM PAGO_VENTA p
                JOIN METODO_PAGO m ON p.id_metodo = m.id_metodo
                JOIN VENTAS v      ON p.id_venta = v.id_venta
                WHERE v.estado = 'A'
                GROUP BY m.nombre
                ORDER BY SUM(p.monto) DESC
            """)
            for fila in cursor.fetchall():
                metodos.append({
                    "metodo": fila[0],
                    "pagos": fila[1],
                    "total": fila[2]
                })
    return metodos