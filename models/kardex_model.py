# models/kardex_model.py
# MODELO: consultas al Kardex (entradas y salidas de inventario)

from models.conexion import obtener_conexion


def listar(id_producto=None, tipo=None):
    """Movimientos del Kardex. Los filtros son opcionales (None = todos)."""
    movimientos = []
    with obtener_conexion() as conexion:
        with conexion.cursor() as cursor:
            # JOIN entre KARDEX, PRODUCTOS y USUARIO.
            # "(:id_producto IS NULL OR ...)" hace el filtro opcional:
            # si llega None, la condición siempre es verdadera y trae todo.
            cursor.execute("""
                SELECT k.id_kardex,
                    TO_CHAR(k.fecha, 'DD/MM/YYYY HH24:MI'),
                    p.nombre,
                    k.tipo_movimiento,
                    k.tipo_documento,
                    k.referencia,
                    k.cantidad_entrada,
                    k.cantidad_salida,
                    k.existencia_final,
                    u.usuario
                FROM KARDEX k
                JOIN PRODUCTOS p     ON k.id_producto = p.id_producto
                LEFT JOIN USUARIO u  ON k.id_usuario = u.id_usuario
                WHERE (:id_producto IS NULL OR k.id_producto = :id_producto)
                AND (:tipo IS NULL OR k.tipo_movimiento = :tipo)
                ORDER BY k.fecha DESC, k.id_kardex DESC
            """, {"id_producto": id_producto, "tipo": tipo})

            for fila in cursor.fetchall():
                movimientos.append({
                    "id_kardex": fila[0],
                    "fecha": fila[1],
                    "producto": fila[2],
                    "tipo": fila[3],
                    "documento": fila[4],
                    "referencia": fila[5],
                    "entrada": fila[6],
                    "salida": fila[7],
                    "existencia": fila[8],
                    "usuario": fila[9]
                })
    return movimientos


def resumen_por_tipo():
    """Cantidad de movimientos y unidades por tipo (ENTRADA / SALIDA)."""
    # Se inicia en cero por si todavía no hay movimientos de algún tipo
    resumen = {"ENTRADA": {"movimientos": 0, "unidades": 0},
            "SALIDA": {"movimientos": 0, "unidades": 0}}
    with obtener_conexion() as conexion:
        with conexion.cursor() as cursor:
            cursor.execute("""
                SELECT tipo_movimiento,
                    COUNT(*),
                    SUM(cantidad_entrada + cantidad_salida)
                FROM KARDEX
                GROUP BY tipo_movimiento
            """)
            for fila in cursor.fetchall():
                resumen[fila[0]] = {"movimientos": fila[1], "unidades": fila[2]}
    return resumen


def resumen_producto(id_producto):
    """Totales de entradas y salidas de un producto, y su stock actual."""
    with obtener_conexion() as conexion:
        with conexion.cursor() as cursor:
            # LEFT JOIN para que también salga un producto sin movimientos (totales en 0).
            # Permite comparar el total de entradas y salidas con el stock actual.
            cursor.execute("""
                SELECT p.nombre,
                    p.stock,
                    NVL(SUM(k.cantidad_entrada), 0),
                    NVL(SUM(k.cantidad_salida), 0)
                FROM PRODUCTOS p
                LEFT JOIN KARDEX k ON p.id_producto = k.id_producto
                WHERE p.id_producto = :id_producto
                GROUP BY p.nombre, p.stock
            """, {"id_producto": id_producto})
            fila = cursor.fetchone()
            if fila is None:
                return None
            return {
                "nombre": fila[0],
                "stock": fila[1],
                "entradas": fila[2],
                "salidas": fila[3]
            }