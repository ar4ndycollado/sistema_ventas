# models/producto_model.py
# MODELO: consultas a la tabla PRODUCTOS y a su auditoría

from models.conexion import obtener_conexion


def clasificar(stock, stock_minimo):
    """Misma regla del cursor de la Actividad 8 del Lab 3."""
    if stock == 0:
        return "AGOTADO"
    elif stock <= stock_minimo:
        return "STOCK BAJO"
    else:
        return "DISPONIBLE"


def listar():
    productos = []
    with obtener_conexion() as conexion:
        with conexion.cursor() as cursor:
            # Se usa la función FN_STOCK_PRODUCTO creada en el Lab 3
            cursor.execute("""
                SELECT id_producto, nombre, precio_compra, precio_venta,
                    FN_STOCK_PRODUCTO(id_producto) AS stock,
                    stock_minimo, estado
                FROM PRODUCTOS
                ORDER BY nombre
            """)
            for fila in cursor.fetchall():
                productos.append({
                    "id_producto": fila[0],
                    "nombre": fila[1],
                    "precio_compra": fila[2],
                    "precio_venta": fila[3],
                    "stock": fila[4],
                    "stock_minimo": fila[5],
                    "estado": fila[6],
                    "clasificacion": clasificar(fila[4], fila[5])
                })
    return productos


def listar_bajo_stock():
    productos = []
    with obtener_conexion() as conexion:
        with conexion.cursor() as cursor:
            # La vista VW_PRODUCTOS_BAJO_STOCK (Lab 2) indica QUÉ productos tienen bajo stock;
            # los demás datos se toman de la tabla PRODUCTOS
            cursor.execute("""
                SELECT p.id_producto, p.nombre, p.precio_compra, p.precio_venta,
                    p.stock, p.stock_minimo, p.estado
                FROM VW_PRODUCTOS_BAJO_STOCK v
                JOIN PRODUCTOS p ON v.id_producto = p.id_producto
                ORDER BY p.stock
            """)
            for fila in cursor.fetchall():
                productos.append({
                    "id_producto": fila[0],
                    "nombre": fila[1],
                    "precio_compra": fila[2],
                    "precio_venta": fila[3],
                    "stock": fila[4],
                    "stock_minimo": fila[5],
                    "estado": fila[6],
                    "clasificacion": clasificar(fila[4], fila[5])
                })
    return productos


def obtener(id_producto):
    producto = None
    with obtener_conexion() as conexion:
        with conexion.cursor() as cursor:
            cursor.execute("""
                SELECT id_producto, nombre, precio_compra, precio_venta,
                    stock, stock_minimo, estado
                FROM PRODUCTOS
                WHERE id_producto = :id_producto
            """, {"id_producto": id_producto})
            fila = cursor.fetchone()
            if fila is not None:
                producto = {
                    "id_producto": fila[0],
                    "nombre": fila[1],
                    "precio_compra": fila[2],
                    "precio_venta": fila[3],
                    "stock": fila[4],
                    "stock_minimo": fila[5],
                    "estado": fila[6]
                }
    return producto


def registrar(producto):
    with obtener_conexion() as conexion:
        with conexion.cursor() as cursor:
            # El stock inicia en 0: solo aumentará mediante compras
            cursor.execute("""
                INSERT INTO PRODUCTOS (id_producto, nombre, precio_compra, precio_venta,
                                    stock, stock_minimo, estado, fecha_registro)
                VALUES (SEQ_PRODUCTO.NEXTVAL, :nombre, :precio_compra, :precio_venta,
                        0, :stock_minimo, 'A', SYSDATE)
            """, {
                "nombre": producto["nombre"],
                "precio_compra": producto["precio_compra"],
                "precio_venta": producto["precio_venta"],
                "stock_minimo": producto["stock_minimo"]
            })
        conexion.commit()


def actualizar(id_producto, producto, usuario_app):
    with obtener_conexion() as conexion:
        # Enviar a Oracle el usuario de la aplicación (lo lee el trigger de auditoría)
        conexion.client_identifier = usuario_app

        with conexion.cursor() as cursor:
            # El stock NO se modifica aquí
            cursor.execute("""
                UPDATE PRODUCTOS
                SET nombre = :nombre,
                    precio_compra = :precio_compra,
                    precio_venta = :precio_venta,
                    stock_minimo = :stock_minimo
                WHERE id_producto = :id_producto
            """, {
                "nombre": producto["nombre"],
                "precio_compra": producto["precio_compra"],
                "precio_venta": producto["precio_venta"],
                "stock_minimo": producto["stock_minimo"],
                "id_producto": id_producto
            })
        conexion.commit()


def cambiar_estado(id_producto, nuevo_estado):
    with obtener_conexion() as conexion:
        with conexion.cursor() as cursor:
            cursor.execute("""
                UPDATE PRODUCTOS SET estado = :estado
                WHERE id_producto = :id_producto
            """, {"estado": nuevo_estado, "id_producto": id_producto})
        conexion.commit()


def listar_auditoria():
    registros = []
    with obtener_conexion() as conexion:
        with conexion.cursor() as cursor:
            cursor.execute("""
                SELECT a.id_auditoria, p.nombre, a.precio_anterior, a.precio_nuevo,
                    a.usuario, TO_CHAR(a.fecha, 'DD/MM/YYYY HH24:MI'), a.tipo_operacion
                FROM AUDITORIA_PRODUCTO a
                JOIN PRODUCTOS p ON a.id_producto = p.id_producto
                ORDER BY a.id_auditoria DESC
            """)
            for fila in cursor.fetchall():
                registros.append({
                    "id_auditoria": fila[0],
                    "producto": fila[1],
                    "precio_anterior": fila[2],
                    "precio_nuevo": fila[3],
                    "usuario": fila[4],
                    "fecha": fila[5],
                    "tipo_operacion": fila[6]
                })
    return registros

def listar_activos():
    productos = []
    with obtener_conexion() as conexion:
        with conexion.cursor() as cursor:
            cursor.execute("""
                SELECT id_producto, nombre, precio_compra, precio_venta, stock
                FROM PRODUCTOS
                WHERE estado = 'A'
                ORDER BY nombre
            """)
            for fila in cursor.fetchall():
                productos.append({
                    "id_producto": fila[0],
                    "nombre": fila[1],
                    "precio_compra": fila[2],
                    "precio_venta": fila[3],
                    "stock": fila[4]
                })
    return productos