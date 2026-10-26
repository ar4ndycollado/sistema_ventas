# models/usuario_model.py
# MODELO: consultas relacionadas con los usuarios y sus roles

from models.conexion import obtener_conexion


def buscar_usuario(nombre_usuario):
    """Devuelve los datos del usuario o None si no existe."""
    conexion = obtener_conexion()
    cursor = conexion.cursor()

    cursor.execute("""
        SELECT id_usuario, usuario, password, estado
        FROM USUARIO
        WHERE usuario = :usuario
    """, {"usuario": nombre_usuario})

    fila = cursor.fetchone()
    usuario = None

    if fila is not None:
        usuario = {
            "id_usuario": fila[0],
            "usuario": fila[1],
            "password": fila[2],
            "estado": fila[3]
        }

    cursor.close()
    conexion.close()
    return usuario


def obtener_roles(id_usuario):
    """Devuelve una lista con los nombres de los roles del usuario."""
    conexion = obtener_conexion()
    cursor = conexion.cursor()

    cursor.execute("""
        SELECT r.nombre_rol
        FROM USUARIO_ROL ur
        JOIN ROL r ON ur.id_rol = r.id_rol
        WHERE ur.id_usuario = :id_usuario
    """, {"id_usuario": id_usuario})

    roles = []
    for fila in cursor.fetchall():
        roles.append(fila[0])

    cursor.close()
    conexion.close()
    return roles