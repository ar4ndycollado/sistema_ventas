# models/compra_model.py
# MODELO: compras (encabezado) y detalle de compras.
# Relación maestro–detalle: una fila en COMPRAS y una fila en DETALLE_COMPRA
# por cada producto comprado.

import oracledb
from models.conexion import obtener_conexion


def listar():
    """Todas las compras, la más reciente primero, con cuántos productos tiene cada una."""
    compras = []
    with obtener_conexion() as conexion:
        with conexion.cursor() as cursor:
            # JOIN entre COMPRAS, PROVEEDORES, USUARIO y DETALLE_COMPRA.
            # COUNT + GROUP BY cuenta las líneas de detalle de cada compra.
            cursor.execute("""
                SELECT c.id_compra,
                    TO_CHAR(c.fecha, 'DD/MM/YYYY HH24:MI'),
                    p.nombre,
                    u.usuario,
                    COUNT(d.id_detalle_compra),
                    c.total
                FROM COMPRAS c
                JOIN PROVEEDORES p ON c.id_proveedor = p.id_proveedor
                JOIN USUARIO u     ON c.id_usuario = u.id_usuario
                LEFT JOIN DETALLE_COMPRA d ON c.id_compra = d.id_compra
                GROUP BY c.id_compra, c.fecha, p.nombre, u.usuario, c.total
                ORDER BY c.id_compra DESC
            """)
            for fila in cursor.fetchall():
                compras.append({
                    "id_compra": fila[0],
                    "fecha": fila[1],
                    "proveedor": fila[2],
                    "usuario": fila[3],
                    "productos": fila[4],
                    "total": fila[5]
                })
    return compras


def obtener(id_compra):
    """Encabezado de una compra (proveedor, usuario y total), o None si no existe."""
    compra = None
    with obtener_conexion() as conexion:
        with conexion.cursor() as cursor:
            cursor.execute("""
                SELECT c.id_compra, TO_CHAR(c.fecha, 'DD/MM/YYYY HH24:MI'),
                    p.nombre, p.nit, u.usuario, c.total
                FROM COMPRAS c
                JOIN PROVEEDORES p ON c.id_proveedor = p.id_proveedor
                JOIN USUARIO u     ON c.id_usuario = u.id_usuario
                WHERE c.id_compra = :id_compra
            """, {"id_compra": id_compra})
            fila = cursor.fetchone()
            if fila is not None:
                compra = {
                    "id_compra": fila[0],
                    "fecha": fila[1],
                    "proveedor": fila[2],
                    "nit": fila[3],
                    "usuario": fila[4],
                    "total": fila[5]
                }
    return compra


def obtener_detalle(id_compra):
    """Productos de una compra (las filas de DETALLE_COMPRA)."""
    lineas = []
    with obtener_conexion() as conexion:
        with conexion.cursor() as cursor:
            cursor.execute("""
                SELECT d.id_producto, p.nombre, d.cantidad, d.precio_costo, d.subtotal
                FROM DETALLE_COMPRA d
                JOIN PRODUCTOS p ON d.id_producto = p.id_producto
                WHERE d.id_compra = :id_compra
                ORDER BY d.id_detalle_compra
            """, {"id_compra": id_compra})
            for fila in cursor.fetchall():
                lineas.append({
                    "id_producto": fila[0],
                    "nombre": fila[1],
                    "cantidad": fila[2],
                    "precio_costo": fila[3],
                    "subtotal": fila[4]
                })
    return lineas


def registrar(id_proveedor, id_usuario, lineas):
    """Registra la compra completa en UNA sola transacción.
    Si cualquier producto falla, se deshace todo con ROLLBACK."""
    # Aquí no se usa "with" porque se necesita controlar a mano
    # el commit/rollback y cerrar todo en el "finally"
    conexion = obtener_conexion()
    cursor = conexion.cursor()

    try:
        # Obtener el número de la nueva compra
        cursor.execute("SELECT SEQ_COMPRA.NEXTVAL FROM DUAL")
        id_compra = cursor.fetchone()[0]

        # 1. Encabezado (maestro). El total empieza en 0:
        #    el procedimiento lo va sumando con cada producto
        cursor.execute("""
            INSERT INTO COMPRAS (id_compra, fecha, total, id_proveedor, id_usuario)
            VALUES (:id_compra, SYSDATE, 0, :id_proveedor, :id_usuario)
        """, {"id_compra": id_compra, "id_proveedor": id_proveedor, "id_usuario": id_usuario})

        # 2. Detalle: un procedimiento por cada producto del carrito.
        #    SP_AGREGAR_DETALLE_COMPRA valida el producto, inserta el detalle,
        #    sube el stock, suma al total de la compra y registra la ENTRADA
        #    en el Kardex. NO hace COMMIT: eso lo decide este código.
        for linea in lineas:
            cursor.callproc("SP_AGREGAR_DETALLE_COMPRA", [
                id_compra,
                linea["id_producto"],
                linea["cantidad"],
                linea["precio_costo"]
            ])

        # 3. Todo salió bien: confirmar la compra completa
        conexion.commit()
        return id_compra

    except oracledb.DatabaseError:
        # Algo falló: deshacer TODO (encabezado, detalles, stock y Kardex)
        conexion.rollback()
        # "raise" vuelve a lanzar el error para que el controlador muestre el mensaje
        raise

    finally:
        # Se ejecuta siempre, haya error o no
        cursor.close()
        conexion.close()