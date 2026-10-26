# models/caja_model.py
# MODELO: cajas, aperturas y cierres

from models.conexion import obtener_conexion


def obtener_apertura_activa(id_usuario):
    """Devuelve la apertura de caja abierta del usuario, o None si no tiene."""
    apertura = None
    with obtener_conexion() as conexion:
        with conexion.cursor() as cursor:
            cursor.execute("""
                SELECT a.id_apertura, c.nombre, a.monto_inicial, a.monto_esperado,
                    TO_CHAR(a.fecha_apertura, 'DD/MM/YYYY HH24:MI')
                FROM APERTURA_CAJA a
                JOIN CAJA c ON a.id_caja = c.id_caja
                WHERE a.id_usuario = :id_usuario
                AND a.estado = 'A'
                ORDER BY a.fecha_apertura DESC
                FETCH FIRST 1 ROWS ONLY
            """, {"id_usuario": id_usuario})
            fila = cursor.fetchone()
            if fila is not None:
                apertura = {
                    "id_apertura": fila[0],
                    "caja": fila[1],
                    "monto_inicial": fila[2],
                    "monto_esperado": fila[3],
                    "fecha_apertura": fila[4]
                }
    return apertura


def resumen_apertura(id_apertura):
    """Datos completos de una apertura, con cantidad y total de ventas."""
    resumen = None
    with obtener_conexion() as conexion:
        with conexion.cursor() as cursor:
            cursor.execute("""
                SELECT a.id_apertura, c.nombre, a.id_usuario, u.usuario,
                    TO_CHAR(a.fecha_apertura, 'DD/MM/YYYY HH24:MI'),
                    TO_CHAR(a.fecha_cierre, 'DD/MM/YYYY HH24:MI'),
                    a.monto_inicial, a.monto_esperado, a.monto_contado,
                    a.diferencia, a.estado,
                    (SELECT COUNT(*) FROM VENTAS v WHERE v.id_apertura = a.id_apertura),
                    (SELECT NVL(SUM(v.total), 0) FROM VENTAS v WHERE v.id_apertura = a.id_apertura)
                FROM APERTURA_CAJA a
                JOIN CAJA c    ON a.id_caja = c.id_caja
                JOIN USUARIO u ON a.id_usuario = u.id_usuario
                WHERE a.id_apertura = :id_apertura
            """, {"id_apertura": id_apertura})
            fila = cursor.fetchone()
            if fila is not None:
                resumen = {
                    "id_apertura": fila[0],
                    "caja": fila[1],
                    "id_usuario": fila[2],
                    "usuario": fila[3],
                    "fecha_apertura": fila[4],
                    "fecha_cierre": fila[5],
                    "monto_inicial": fila[6],
                    "monto_esperado": fila[7],
                    "monto_contado": fila[8],
                    "diferencia": fila[9],
                    "estado": fila[10],
                    "cantidad_ventas": fila[11],
                    "total_ventas": fila[12]
                }
    return resumen


def ventas_de_apertura(id_apertura):
    ventas = []
    with obtener_conexion() as conexion:
        with conexion.cursor() as cursor:
            cursor.execute("""
                SELECT v.id_venta, TO_CHAR(v.fecha, 'DD/MM/YYYY HH24:MI'), c.nombre, v.total
                FROM VENTAS v
                JOIN CLIENTES c ON v.id_cliente = c.id_cliente
                WHERE v.id_apertura = :id_apertura
                ORDER BY v.id_venta
            """, {"id_apertura": id_apertura})
            for fila in cursor.fetchall():
                ventas.append({
                    "id_venta": fila[0],
                    "fecha": fila[1],
                    "cliente": fila[2],
                    "total": fila[3]
                })
    return ventas


def cajas_disponibles():
    """Cajas activas que no están abiertas por nadie."""
    cajas = []
    with obtener_conexion() as conexion:
        with conexion.cursor() as cursor:
            cursor.execute("""
                SELECT c.id_caja, c.nombre
                FROM CAJA c
                WHERE c.estado = 'A'
                AND NOT EXISTS (SELECT 1 FROM APERTURA_CAJA a
                                WHERE a.id_caja = c.id_caja AND a.estado = 'A')
                ORDER BY c.nombre
            """)
            for fila in cursor.fetchall():
                cajas.append({"id_caja": fila[0], "nombre": fila[1]})
    return cajas


def abrir(id_caja, id_usuario, monto_inicial):
    with obtener_conexion() as conexion:
        with conexion.cursor() as cursor:
            id_apertura_var = cursor.var(int)
            cursor.callproc("SP_ABRIR_CAJA", [id_caja, id_usuario, monto_inicial, id_apertura_var])
            return id_apertura_var.getvalue()


def cerrar(id_apertura, id_usuario, monto_contado):
    with obtener_conexion() as conexion:
        with conexion.cursor() as cursor:
            cursor.callproc("SP_CERRAR_CAJA", [id_apertura, id_usuario, monto_contado])


def historial(id_usuario=None):
    """Todas las aperturas (si id_usuario es None) o solo las del usuario indicado."""
    aperturas = []
    with obtener_conexion() as conexion:
        with conexion.cursor() as cursor:
            cursor.execute("""
                SELECT a.id_apertura, c.nombre, u.usuario,
                    TO_CHAR(a.fecha_apertura, 'DD/MM/YYYY HH24:MI'),
                    TO_CHAR(a.fecha_cierre, 'DD/MM/YYYY HH24:MI'),
                    a.monto_inicial, a.monto_esperado, a.monto_contado,
                    a.diferencia, a.estado
                FROM APERTURA_CAJA a
                JOIN CAJA c    ON a.id_caja = c.id_caja
                JOIN USUARIO u ON a.id_usuario = u.id_usuario
                WHERE (:id_usuario IS NULL OR a.id_usuario = :id_usuario)
                ORDER BY a.id_apertura DESC
            """, {"id_usuario": id_usuario})
            for fila in cursor.fetchall():
                aperturas.append({
                    "id_apertura": fila[0],
                    "caja": fila[1],
                    "usuario": fila[2],
                    "fecha_apertura": fila[3],
                    "fecha_cierre": fila[4],
                    "monto_inicial": fila[5],
                    "monto_esperado": fila[6],
                    "monto_contado": fila[7],
                    "diferencia": fila[8],
                    "estado": fila[9]
                })
    return aperturas


def listar_cajas():
    """Catálogo de cajas, indicando quién la tiene abierta (si alguien)."""
    cajas = []
    with obtener_conexion() as conexion:
        with conexion.cursor() as cursor:
            cursor.execute("""
                SELECT c.id_caja, c.nombre, c.estado,
                    (SELECT u.usuario
                        FROM APERTURA_CAJA a
                        JOIN USUARIO u ON a.id_usuario = u.id_usuario
                        WHERE a.id_caja = c.id_caja AND a.estado = 'A'
                        FETCH FIRST 1 ROWS ONLY) AS en_uso_por
                FROM CAJA c
                ORDER BY c.id_caja
            """)
            for fila in cursor.fetchall():
                cajas.append({
                    "id_caja": fila[0],
                    "nombre": fila[1],
                    "estado": fila[2],
                    "en_uso_por": fila[3]
                })
    return cajas


def registrar_caja(nombre):
    with obtener_conexion() as conexion:
        with conexion.cursor() as cursor:
            cursor.execute("""
                INSERT INTO CAJA (id_caja, nombre, estado)
                VALUES (SEQ_CAJA.NEXTVAL, :nombre, 'A')
            """, {"nombre": nombre})
        conexion.commit()


def cambiar_estado_caja(id_caja, nuevo_estado):
    with obtener_conexion() as conexion:
        with conexion.cursor() as cursor:
            cursor.execute("UPDATE CAJA SET estado = :estado WHERE id_caja = :id_caja",
                        {"estado": nuevo_estado, "id_caja": id_caja})
        conexion.commit()

