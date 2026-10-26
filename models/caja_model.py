# models/caja_model.py
# MODELO: caja y aperturas (se completará en el Paso 9)

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