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
    """Datos de una apertura: ventas activas, efectivo, anuladas, cierre y vale."""
    resumen = None
    with obtener_conexion() as conexion:
        with conexion.cursor() as cursor:
            cursor.execute("""
                SELECT a.id_apertura, c.nombre, a.id_usuario, u.usuario,
                    TO_CHAR(a.fecha_apertura, 'DD/MM/YYYY HH24:MI'),
                    TO_CHAR(a.fecha_cierre, 'DD/MM/YYYY HH24:MI'),
                    a.monto_inicial, a.monto_esperado, a.monto_contado,
                    a.diferencia, a.estado,
                    (SELECT COUNT(*) FROM VENTAS v
                    WHERE v.id_apertura = a.id_apertura AND v.estado = 'A'),
                    (SELECT NVL(SUM(v.total), 0) FROM VENTAS v
                    WHERE v.id_apertura = a.id_apertura AND v.estado = 'A'),
                    FN_EFECTIVO_APERTURA(a.id_apertura),
                    (SELECT COUNT(*) FROM VENTAS v
                    WHERE v.id_apertura = a.id_apertura AND v.estado = 'N'),
                    a.observacion_cierre,
                    (SELECT vd.id_vale FROM VALE_DESCUENTO vd WHERE vd.id_apertura = a.id_apertura)
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
                    "total_ventas": fila[12],
                    "efectivo": fila[13],
                    "anuladas": fila[14],
                    "observacion": fila[15],
                    "id_vale": fila[16]
                }
    return resumen


def ventas_de_apertura(id_apertura):
    ventas = []
    with obtener_conexion() as conexion:
        with conexion.cursor() as cursor:
            cursor.execute("""
                SELECT v.id_venta, TO_CHAR(v.fecha, 'DD/MM/YYYY HH24:MI'), c.nombre, v.total, v.estado
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
                    "total": fila[3],
                    "estado": fila[4]
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


def cerrar(id_apertura, id_usuario, monto_contado, observacion):
    with obtener_conexion() as conexion:
        with conexion.cursor() as cursor:
            cursor.callproc("SP_CERRAR_CAJA", [id_apertura, id_usuario, monto_contado, observacion])


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

# ===== Incidencias (faltantes y sobrantes) =====

def listar_incidencias(mes):
    """Incidencias del mes indicado ('YYYY-MM'), desde la vista VW_INCIDENCIAS_CAJA."""
    incidencias = []
    with obtener_conexion() as conexion:
        with conexion.cursor() as cursor:
            cursor.execute("""
                SELECT id_apertura, usuario, caja,
                    TO_CHAR(fecha_cierre, 'DD/MM/YYYY HH24:MI'),
                    tipo, monto, observacion_cierre, id_vale, estado_vale
                FROM VW_INCIDENCIAS_CAJA
                WHERE TO_CHAR(fecha_cierre, 'YYYY-MM') = :mes
                ORDER BY fecha_cierre DESC
            """, {"mes": mes})
            for fila in cursor.fetchall():
                incidencias.append({
                    "id_apertura": fila[0],
                    "usuario": fila[1],
                    "caja": fila[2],
                    "fecha": fila[3],
                    "tipo": fila[4],
                    "monto": fila[5],
                    "observacion": fila[6],
                    "id_vale": fila[7],
                    "estado_vale": fila[8]
                })
    return incidencias


def resumen_incidencias(mes):
    """Por usuario: cantidad y monto de faltantes y sobrantes del mes (GROUP BY)."""
    resumen = []
    with obtener_conexion() as conexion:
        with conexion.cursor() as cursor:
            cursor.execute("""
                SELECT usuario,
                    COUNT(CASE WHEN tipo = 'FALTANTE' THEN 1 END),
                    NVL(SUM(CASE WHEN tipo = 'FALTANTE' THEN monto END), 0),
                    COUNT(CASE WHEN tipo = 'SOBRANTE' THEN 1 END),
                    NVL(SUM(CASE WHEN tipo = 'SOBRANTE' THEN monto END), 0)
                FROM VW_INCIDENCIAS_CAJA
                WHERE TO_CHAR(fecha_cierre, 'YYYY-MM') = :mes
                GROUP BY usuario
                ORDER BY 2 DESC, 3 DESC
            """, {"mes": mes})
            for fila in cursor.fetchall():
                resumen.append({
                    "usuario": fila[0],
                    "faltantes": fila[1],
                    "monto_faltantes": fila[2],
                    "sobrantes": fila[3],
                    "monto_sobrantes": fila[4]
                })
    return resumen


# ===== Vales de descuento =====

def listar_vales(estado=None):
    vales = []
    with obtener_conexion() as conexion:
        with conexion.cursor() as cursor:
            cursor.execute("""
                SELECT v.id_vale, u.usuario, c.nombre, v.id_apertura, v.monto, v.estado,
                    TO_CHAR(v.fecha_emision, 'DD/MM/YYYY'),
                    TO_CHAR(v.fecha_aplicacion, 'DD/MM/YYYY'),
                    v.motivo_anulacion
                FROM VALE_DESCUENTO v
                JOIN APERTURA_CAJA a ON v.id_apertura = a.id_apertura
                JOIN USUARIO u       ON a.id_usuario = u.id_usuario
                JOIN CAJA c          ON a.id_caja = c.id_caja
                WHERE (:estado IS NULL OR v.estado = :estado)
                ORDER BY v.id_vale DESC
            """, {"estado": estado})
            for fila in cursor.fetchall():
                vales.append({
                    "id_vale": fila[0],
                    "usuario": fila[1],
                    "caja": fila[2],
                    "id_apertura": fila[3],
                    "monto": fila[4],
                    "estado": fila[5],
                    "fecha_emision": fila[6],
                    "fecha_aplicacion": fila[7],
                    "motivo_anulacion": fila[8]
                })
    return vales


def pendientes_por_usuario():
    """Total de vales pendientes por usuario: lo que se descontará a fin de mes."""
    pendientes = []
    with obtener_conexion() as conexion:
        with conexion.cursor() as cursor:
            cursor.execute("""
                SELECT u.usuario, COUNT(v.id_vale), SUM(v.monto)
                FROM VALE_DESCUENTO v
                JOIN APERTURA_CAJA a ON v.id_apertura = a.id_apertura
                JOIN USUARIO u       ON a.id_usuario = u.id_usuario
                WHERE v.estado = 'P'
                GROUP BY u.usuario
                ORDER BY SUM(v.monto) DESC
            """)
            for fila in cursor.fetchall():
                pendientes.append({
                    "usuario": fila[0],
                    "vales": fila[1],
                    "total": fila[2]
                })
    return pendientes


def aplicar_vales_mes(mes):
    with obtener_conexion() as conexion:
        with conexion.cursor() as cursor:
            cantidad_var = cursor.var(int)
            cursor.callproc("SP_APLICAR_VALES_MES", [mes, cantidad_var])
            return cantidad_var.getvalue()


def anular_vale(id_vale, motivo):
    """Anula un vale pendiente. Devuelve True si se anuló."""
    with obtener_conexion() as conexion:
        with conexion.cursor() as cursor:
            cursor.execute("""
                UPDATE VALE_DESCUENTO
                SET estado = 'N',
                    motivo_anulacion = :motivo
            WHERE id_vale = :id_vale
            AND estado = 'P'
            """, {"motivo": motivo, "id_vale": id_vale})
            anulado = cursor.rowcount == 1
        conexion.commit()
    return anulado

def listar_anulaciones(mes):
    """Ventas anuladas en el mes indicado, desde la vista VW_ANULACIONES_VENTA."""
    anulaciones = []
    with obtener_conexion() as conexion:
        with conexion.cursor() as cursor:
            cursor.execute("""
                SELECT id_venta, TO_CHAR(fecha_anulacion, 'DD/MM/YYYY HH24:MI'),
                    vendedor, anulado_por, cliente, total, motivo_anulacion
                FROM VW_ANULACIONES_VENTA
                WHERE TO_CHAR(fecha_anulacion, 'YYYY-MM') = :mes
                ORDER BY fecha_anulacion DESC
            """, {"mes": mes})
            for fila in cursor.fetchall():
                anulaciones.append({
                    "id_venta": fila[0],
                    "fecha": fila[1],
                    "vendedor": fila[2],
                    "anulado_por": fila[3],
                    "cliente": fila[4],
                    "total": fila[5],
                    "motivo": fila[6]
                })
    return anulaciones


def sanciones_mes(mes):
    """Incidencias sancionables por usuario en el mes, desde la vista VW_SANCIONES_MES."""
    sanciones = []
    with obtener_conexion() as conexion:
        with conexion.cursor() as cursor:
            cursor.execute("""
                SELECT usuario, faltantes, monto_faltante, anulaciones,
                    total_incidencias, sancion_sugerida
                FROM VW_SANCIONES_MES
                WHERE mes = :mes
                ORDER BY total_incidencias DESC, monto_faltante DESC
            """, {"mes": mes})
            for fila in cursor.fetchall():
                sanciones.append({
                    "usuario": fila[0],
                    "faltantes": fila[1],
                    "monto_faltante": fila[2],
                    "anulaciones": fila[3],
                    "total": fila[4],
                    "sancion": fila[5]
                })
    return sanciones


def listar_politica():
    politica = []
    with obtener_conexion() as conexion:
        with conexion.cursor() as cursor:
            cursor.execute("""
                SELECT minimo_incidencias, sancion
                FROM POLITICA_SANCION
                ORDER BY minimo_incidencias
            """)
            for fila in cursor.fetchall():
                politica.append({"minimo": fila[0], "sancion": fila[1]})
    return politica