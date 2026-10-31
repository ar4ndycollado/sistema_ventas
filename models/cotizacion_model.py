# models/cotizacion_model.py
# MODELO: cotizaciones y su detalle (NO afectan el inventario)

import oracledb
from models.conexion import obtener_conexion


def caducar_vencidas():
    """Llama al procedimiento que marca como 'C' las cotizaciones vencidas.
    SP_CADUCAR_COTIZACIONES cambia a 'C' las abiertas cuya fecha de
    vencimiento ya pasó, y hace su propio COMMIT."""
    with obtener_conexion() as conexion:
        with conexion.cursor() as cursor:
            cursor.callproc("SP_CADUCAR_COTIZACIONES")


def listar():
    """Todas las cotizaciones, la más reciente primero."""
    cotizaciones = []
    with obtener_conexion() as conexion:
        with conexion.cursor() as cursor:
            cursor.execute("""
                SELECT c.id_cotizacion,
                    TO_CHAR(c.fecha, 'DD/MM/YYYY'),
                    TO_CHAR(c.fecha_vencimiento, 'DD/MM/YYYY'),
                    cl.nombre,
                    u.usuario,
                    c.total,
                    c.estado
                FROM COTIZACION c
                JOIN CLIENTES cl ON c.id_cliente = cl.id_cliente
                JOIN USUARIO u   ON c.id_usuario = u.id_usuario
                ORDER BY c.id_cotizacion DESC
            """)
            for fila in cursor.fetchall():
                cotizaciones.append({
                    "id_cotizacion": fila[0],
                    "fecha": fila[1],
                    "vencimiento": fila[2],
                    "cliente": fila[3],
                    "usuario": fila[4],
                    "total": fila[5],
                    "estado": fila[6]
                })
    return cotizaciones


def obtener(id_cotizacion):
    """Encabezado de una cotización, o None si no existe."""
    cotizacion = None
    with obtener_conexion() as conexion:
        with conexion.cursor() as cursor:
            # La subconsulta busca la venta generada a partir de esta cotización (si existe)
            cursor.execute("""
                SELECT c.id_cotizacion,
                    TO_CHAR(c.fecha, 'DD/MM/YYYY HH24:MI'),
                    TO_CHAR(c.fecha_vencimiento, 'DD/MM/YYYY'),
                    c.id_cliente, cl.nombre, u.usuario, c.total, c.estado,
                    (SELECT MAX(v.id_venta) FROM VENTAS v
                        WHERE v.id_cotizacion = c.id_cotizacion) AS id_venta
                FROM COTIZACION c
                JOIN CLIENTES cl ON c.id_cliente = cl.id_cliente
                JOIN USUARIO u   ON c.id_usuario = u.id_usuario
                WHERE c.id_cotizacion = :id_cotizacion
            """, {"id_cotizacion": id_cotizacion})
            fila = cursor.fetchone()
            if fila is not None:
                cotizacion = {
                    "id_cotizacion": fila[0],
                    "fecha": fila[1],
                    "vencimiento": fila[2],
                    "id_cliente": fila[3],
                    "cliente": fila[4],
                    "usuario": fila[5],
                    "total": fila[6],
                    "estado": fila[7],
                    "id_venta": fila[8]
                }
    return cotizacion


def obtener_detalle(id_cotizacion):
    """Productos de la cotización con el precio cotizado y el stock de hoy
    (el detalle muestra si todavía alcanza la existencia para venderla)."""
    lineas = []
    with obtener_conexion() as conexion:
        with conexion.cursor() as cursor:
            cursor.execute("""
                SELECT d.id_producto, p.nombre, d.cantidad, d.precio, d.subtotal, p.stock
                FROM DETALLE_COTIZACION d
                JOIN PRODUCTOS p ON d.id_producto = p.id_producto
                WHERE d.id_cotizacion = :id_cotizacion
                ORDER BY d.id_detalle_cotizacion
            """, {"id_cotizacion": id_cotizacion})
            for fila in cursor.fetchall():
                lineas.append({
                    "id_producto": fila[0],
                    "nombre": fila[1],
                    "cantidad": fila[2],
                    "precio": fila[3],
                    "subtotal": fila[4],
                    "stock_actual": fila[5]
                })
    return lineas


def registrar(id_cliente, id_usuario, dias_validez, lineas):
    """Registra la cotización y su detalle en una sola transacción.
    NO toca PRODUCTOS.stock ni KARDEX."""
    conexion = obtener_conexion()
    cursor = conexion.cursor()

    try:
        # Pedir primero el número a la secuencia para usarlo en el encabezado y en los detalles
        cursor.execute("SELECT SEQ_COTIZACION.NEXTVAL FROM DUAL")
        id_cotizacion = cursor.fetchone()[0]

        # 1. Encabezado: vence en "dias" a partir de hoy; total en 0 y estado 'A' (abierta)
        cursor.execute("""
            INSERT INTO COTIZACION (id_cotizacion, id_cliente, id_usuario, fecha,
                                    fecha_vencimiento, total, estado)
            VALUES (:id_cotizacion, :id_cliente, :id_usuario, SYSDATE,
                    TRUNC(SYSDATE) + :dias, 0, 'A')
        """, {"id_cotizacion": id_cotizacion, "id_cliente": id_cliente,
            "id_usuario": id_usuario, "dias": dias_validez})

        # 2. Detalle: el precio se toma del catálogo de productos.
        #    INSERT ... SELECT copia el precio_venta directo de PRODUCTOS;
        #    si el producto está inactivo, el SELECT no devuelve filas y no se inserta nada.
        for linea in lineas:
            cursor.execute("""
                INSERT INTO DETALLE_COTIZACION (id_detalle_cotizacion, id_cotizacion,
                                                id_producto, cantidad, precio, subtotal)
                SELECT SEQ_DETALLE_COTIZACION.NEXTVAL, :id_cotizacion, id_producto,
                       :cantidad, precio_venta, :cantidad * precio_venta
                FROM PRODUCTOS
                WHERE id_producto = :id_producto
                AND estado = 'A'
            """, {"id_cotizacion": id_cotizacion, "cantidad": linea["cantidad"],
                "id_producto": linea["id_producto"]})

            # rowcount = 0 → no se insertó la línea; se cancela toda la cotización
            if cursor.rowcount == 0:
                raise ValueError("El producto " + linea["nombre"] + " no existe o está inactivo.")

        # 3. Total de la cotización = suma de los subtotales (subconsulta)
        cursor.execute("""
            UPDATE COTIZACION
            SET total = (SELECT SUM(subtotal) FROM DETALLE_COTIZACION
                            WHERE id_cotizacion = :id_cotizacion)
            WHERE id_cotizacion = :id_cotizacion
        """, {"id_cotizacion": id_cotizacion})

        conexion.commit()
        return id_cotizacion

    except (oracledb.DatabaseError, ValueError):
        # Cualquier error deshace el encabezado y las líneas ya insertadas
        conexion.rollback()
        raise

    finally:
        cursor.close()
        conexion.close()