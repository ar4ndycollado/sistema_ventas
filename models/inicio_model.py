# models/inicio_model.py
# MODELO: datos del resumen que se muestra en la página de inicio

from models.conexion import obtener_conexion


def ventas_de_hoy(id_usuario=None):
    """Cantidad y total de las ventas ACTIVAS de hoy.
    Si se envía id_usuario, solo cuenta las ventas de ese usuario."""
    with obtener_conexion() as conexion:
        with conexion.cursor() as cursor:
            # TRUNC quita la hora de la fecha: compara solo el día.
            # "(:id_usuario IS NULL OR ...)" hace opcional el filtro por usuario.
            cursor.execute("""
                SELECT COUNT(*), NVL(SUM(total), 0)
                FROM VENTAS
                WHERE estado = 'A'
                AND TRUNC(fecha) = TRUNC(SYSDATE)
                AND (:id_usuario IS NULL OR id_usuario = :id_usuario)
            """, {"id_usuario": id_usuario})
            fila = cursor.fetchone()
            return {"cantidad": fila[0], "total": fila[1]}
