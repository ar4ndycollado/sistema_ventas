# models/reporte_model.py
# MODELO: consultas para reportes (agregación, GROUP BY, HAVING, subconsultas y vistas)

from models.conexion import obtener_conexion


def indicadores_ventas():
    """Funciones de agregación sobre todas las ventas."""
    with obtener_conexion() as conexion:
        with conexion.cursor() as cursor:
            cursor.execute("""
                SELECT COUNT(id_venta),
                    NVL(SUM(total), 0),
                    NVL(AVG(total), 0),
                    NVL(MAX(total), 0),
                    NVL(MIN(total), 0)
                FROM VENTAS
            """)
            fila = cursor.fetchone()
            return {
                "cantidad": fila[0],
                "total": fila[1],
                "promedio": fila[2],
                "maxima": fila[3],
                "minima": fila[4]
            }


def valor_inventario():
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
            cursor.execute("""
                SELECT c.nombre,
                    COUNT(v.id_venta),
                    SUM(v.total),
                    MAX(v.fecha)
                FROM CLIENTES c
                JOIN VENTAS v ON c.id_cliente = v.id_cliente
                GROUP BY c.id_cliente, c.nombre
                HAVING SUM(v.total) >= :monto_minimo
                ORDER BY SUM(v.total) DESC
            """, {"monto_minimo": monto_minimo})
            for fila in cursor.fetchall():
                clientes.append({
                    "cliente": fila[0],
                    "compras": fila[1],
                    "total": fila[2],
                    "ultima_compra": fila[3].strftime("%d/%m/%Y")
                })
    return clientes


def productos_mas_vendidos():
    """Usa la vista VW_VENTAS_POR_PRODUCTO."""
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
    """Subconsulta: productos que nunca aparecen en DETALLE_VENTA."""
    productos = []
    with obtener_conexion() as conexion:
        with conexion.cursor() as cursor:
            cursor.execute("""
                SELECT id_producto, nombre, stock, estado
                FROM PRODUCTOS
                WHERE id_producto NOT IN (SELECT DISTINCT id_producto FROM DETALLE_VENTA)
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
    """GROUP BY por usuario: cantidad, total y promedio de sus ventas."""
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
    """GROUP BY por mes (funciones de fecha TO_CHAR)."""
    meses = []
    with obtener_conexion() as conexion:
        with conexion.cursor() as cursor:
            cursor.execute("""
                SELECT TO_CHAR(fecha, 'YYYY-MM') AS mes,
                    COUNT(id_venta),
                    SUM(total)
                FROM VENTAS
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