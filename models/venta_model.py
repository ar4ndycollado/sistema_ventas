# models/venta_model.py
# MODELO: ventas (encabezado) y detalle de ventas

import oracledb
from models.conexion import obtener_conexion


def listar():
    ventas = []
    with obtener_conexion() as conexion:
        with conexion.cursor() as cursor:
            # Se usa la vista VW_RESUMEN_VENTAS creada en el Lab 2
            cursor.execute("""
                SELECT id_venta, fecha, cliente, usuario, total
                FROM VW_RESUMEN_VENTAS
                ORDER BY id_venta DESC
            """)
            for fila in cursor.fetchall():
                ventas.append({
                    "id_venta": fila[0],
                    "fecha": fila[1],
                    "cliente": fila[2],
                    "usuario": fila[3],
                    "total": fila[4]
                })
    return ventas


def obtener(id_venta):
    venta = None
    with obtener_conexion() as conexion:
        with conexion.cursor() as cursor:
            cursor.execute("""
                SELECT v.id_venta, TO_CHAR(v.fecha, 'DD/MM/YYYY HH24:MI'),
                       c.nombre, c.correo, u.usuario, v.id_apertura, v.id_cotizacion, v.total
                FROM VENTAS v
                JOIN CLIENTES c ON v.id_cliente = c.id_cliente
                JOIN USUARIO u  ON v.id_usuario = u.id_usuario
                WHERE v.id_venta = :id_venta
            """, {"id_venta": id_venta})
            fila = cursor.fetchone()
            if fila is not None:
                venta = {
                    "id_venta": fila[0],
                    "fecha": fila[1],
                    "cliente": fila[2],
                    "correo": fila[3],
                    "usuario": fila[4],
                    "id_apertura": fila[5],
                    "id_cotizacion": fila[6],
                    "total": fila[7]
                }
    return venta


def obtener_detalle(id_venta):
    lineas = []
    with obtener_conexion() as conexion:
        with conexion.cursor() as cursor:
            cursor.execute("""
                SELECT d.id_producto, p.nombre, d.cantidad, d.precio_venta, d.subtotal
                FROM DETALLE_VENTA d
                JOIN PRODUCTOS p ON d.id_producto = p.id_producto
                WHERE d.id_venta = :id_venta
                ORDER BY d.id_detalle_venta
            """, {"id_venta": id_venta})
            for fila in cursor.fetchall():
                lineas.append({
                    "id_producto": fila[0],
                    "nombre": fila[1],
                    "cantidad": fila[2],
                    "precio_venta": fila[3],
                    "subtotal": fila[4]
                })
    return lineas


def registrar(id_cliente, id_usuario, lineas, id_cotizacion=None):
    """Registra la venta completa en UNA sola transacción.
    Si cualquier validación o producto falla, se deshace todo con ROLLBACK."""
    conexion = obtener_conexion()
    cursor = conexion.cursor()

    try:
        # Variable donde Oracle devolverá el número de venta (parámetro OUT)
        id_venta_var = cursor.var(int)

        # 1. Encabezado: valida cliente, usuario activo y caja abierta
        cursor.callproc("SP_CREAR_VENTA", [id_cliente, id_usuario, id_cotizacion, id_venta_var])
        id_venta = id_venta_var.getvalue()

        # 2. Detalle: un procedimiento por cada producto del carrito
        for linea in lineas:
            cursor.callproc("SP_AGREGAR_DETALLE_VENTA", [
                id_venta,
                linea["id_producto"],
                linea["cantidad"]
            ])

        # 3. Operación de caja
        cursor.callproc("SP_FINALIZAR_VENTA", [id_venta])

        # 4. Todo salió bien: confirmar la venta completa
        conexion.commit()
        return id_venta

    except oracledb.DatabaseError:
        # Algo falló: deshacer TODO (venta, detalles, stock, Kardex, caja)
        conexion.rollback()
        raise

    finally:
        cursor.close()
        conexion.close()