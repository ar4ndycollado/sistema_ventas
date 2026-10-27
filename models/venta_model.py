# models/venta_model.py
# MODELO: ventas (encabezado) y detalle de ventas

import oracledb
from models.conexion import obtener_conexion


def listar():
    ventas = []
    with obtener_conexion() as conexion:
        with conexion.cursor() as cursor:
            # Se usa la vista VW_RESUMEN_VENTAS
            cursor.execute("""
                SELECT id_venta, fecha, cliente, usuario, total, estado
                FROM VW_RESUMEN_VENTAS
                ORDER BY id_venta DESC
            """)
            for fila in cursor.fetchall():
                ventas.append({
                    "id_venta": fila[0],
                    "fecha": fila[1],
                    "cliente": fila[2],
                    "usuario": fila[3],
                    "total": fila[4],
                    "estado": fila[5]
                })
    return ventas


def obtener(id_venta):
    venta = None
    with obtener_conexion() as conexion:
        with conexion.cursor() as cursor:
            cursor.execute("""
                SELECT v.id_venta, TO_CHAR(v.fecha, 'DD/MM/YYYY HH24:MI'),
                    c.nombre, c.correo, u.usuario, v.id_apertura, v.id_cotizacion, v.total,
                    v.estado, TO_CHAR(v.fecha_anulacion, 'DD/MM/YYYY HH24:MI'),
                    ua.usuario, v.motivo_anulacion,
                    c.direccion, c.telefono, a.estado
                FROM VENTAS v
                JOIN CLIENTES c      ON v.id_cliente = c.id_cliente
                JOIN USUARIO u       ON v.id_usuario = u.id_usuario
                JOIN APERTURA_CAJA a ON v.id_apertura = a.id_apertura
                LEFT JOIN USUARIO ua ON v.id_usuario_anula = ua.id_usuario
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
                    "total": fila[7],
                    "estado": fila[8],
                    "fecha_anulacion": fila[9],
                    "anulado_por": fila[10],
                    "motivo_anulacion": fila[11],
                    "direccion": fila[12],
                    "telefono": fila[13],
                    "caja_abierta": fila[14] == "A"
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


def registrar(id_cliente, id_usuario, lineas, pagos, id_cotizacion=None):
    """Registra la venta completa (productos y pagos) en UNA sola transacción."""
    conexion = obtener_conexion()
    cursor = conexion.cursor()

    try:
        id_venta_var = cursor.var(int)

        # 1. Encabezado: valida cliente, usuario activo, caja abierta y cotización
        cursor.callproc("SP_CREAR_VENTA", [id_cliente, id_usuario, id_cotizacion, id_venta_var])
        id_venta = id_venta_var.getvalue()

        # 2. Detalle: un procedimiento por cada producto
        for linea in lineas:
            cursor.callproc("SP_AGREGAR_DETALLE_VENTA", [
                id_venta,
                linea["id_producto"],
                linea["cantidad"]
            ])

        # 3. Pagos: un procedimiento por cada pago
        for pago in pagos:
            cursor.callproc("SP_AGREGAR_PAGO_VENTA", [
                id_venta,
                pago["id_metodo"],
                pago["monto"],
                pago["referencia"],
                pago["monto_recibido"]
            ])

        # 4. Valida que los pagos cubran el total y actualiza la caja
        cursor.callproc("SP_FINALIZAR_VENTA", [id_venta])

        conexion.commit()
        return id_venta

    except oracledb.DatabaseError:
        conexion.rollback()
        raise

    finally:
        cursor.close()
        conexion.close()

def listar_metodos_pago():
    metodos = []
    with obtener_conexion() as conexion:
        with conexion.cursor() as cursor:
            cursor.execute("""
                SELECT id_metodo, nombre, afecta_caja, requiere_referencia
                FROM METODO_PAGO
                WHERE estado = 'A'
                ORDER BY id_metodo
            """)
            for fila in cursor.fetchall():
                metodos.append({
                    "id_metodo": fila[0],
                    "nombre": fila[1],
                    "es_efectivo": fila[2] == "S",
                    "requiere_referencia": fila[3] == "S"
                })
    return metodos


def obtener_pagos(id_venta):
    pagos = []
    with obtener_conexion() as conexion:
        with conexion.cursor() as cursor:
            cursor.execute("""
                SELECT m.nombre, p.monto, p.referencia, p.monto_recibido
                FROM PAGO_VENTA p
                JOIN METODO_PAGO m ON p.id_metodo = m.id_metodo
                WHERE p.id_venta = :id_venta
                ORDER BY p.id_pago
            """, {"id_venta": id_venta})
            for fila in cursor.fetchall():
                cambio = None
                if fila[3] is not None:
                    cambio = fila[3] - fila[1]      # el cambio se calcula, no se guarda
                pagos.append({
                    "metodo": fila[0],
                    "monto": fila[1],
                    "referencia": fila[2],
                    "monto_recibido": fila[3],
                    "cambio": cambio
                })
    return pagos

def anular(id_venta, id_usuario, motivo):
    """SP_ANULAR_VENTA devuelve el stock, registra el Kardex y ajusta la caja (con COMMIT propio)."""
    with obtener_conexion() as conexion:
        with conexion.cursor() as cursor:
            cursor.callproc("SP_ANULAR_VENTA", [id_venta, id_usuario, motivo])