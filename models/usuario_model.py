# models/usuario_model.py
# MODELO: consultas relacionadas con los usuarios y sus roles.
# Tablas: USUARIO, ROL y USUARIO_ROL (asociativa que resuelve la relación M:N).

from models.conexion import obtener_conexion
import oracledb


def buscar_usuario(nombre_usuario):
    """Devuelve los datos del usuario o None si no existe.
    Incluye el hash de la contraseña para que el login lo compare."""
    # Esta función y obtener_roles() abren y cierran la conexión a mano
    # (sin "with"); el resultado es el mismo
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

    # JOIN con ROL para obtener el nombre (ADMINISTRADOR, CAJERO...) en lugar del número
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

def listar():
    """Usuarios con sus roles en una sola columna (LISTAGG)."""
    usuarios = []
    with obtener_conexion() as conexion:
        with conexion.cursor() as cursor:
            # LISTAGG une los roles de cada usuario en un texto: "ADMINISTRADOR, CAJERO".
            # LEFT JOIN para que aparezca también un usuario sin roles.
            cursor.execute("""
                SELECT u.id_usuario,
                    u.usuario,
                    u.estado,
                    LISTAGG(r.nombre_rol, ', ') WITHIN GROUP (ORDER BY r.nombre_rol) AS roles
                FROM USUARIO u
                LEFT JOIN USUARIO_ROL ur ON u.id_usuario = ur.id_usuario
                LEFT JOIN ROL r          ON ur.id_rol = r.id_rol
                GROUP BY u.id_usuario, u.usuario, u.estado
                ORDER BY u.usuario
            """)
            for fila in cursor.fetchall():
                usuarios.append({
                    "id_usuario": fila[0],
                    "usuario": fila[1],
                    "estado": fila[2],
                    "roles": fila[3]
                })
    return usuarios


def obtener(id_usuario):
    """Datos del usuario y la lista de IDs de sus roles."""
    usuario = None
    with obtener_conexion() as conexion:
        with conexion.cursor() as cursor:
            cursor.execute("""
                SELECT id_usuario, usuario, estado
                FROM USUARIO
                WHERE id_usuario = :id_usuario
            """, {"id_usuario": id_usuario})
            fila = cursor.fetchone()

            if fila is not None:
                usuario = {
                    "id_usuario": fila[0],
                    "usuario": fila[1],
                    "estado": fila[2],
                    "roles": []
                }
                # Segunda consulta: los IDs de sus roles, para marcar las casillas del formulario
                cursor.execute("SELECT id_rol FROM USUARIO_ROL WHERE id_usuario = :id_usuario",
                            {"id_usuario": id_usuario})
                for fila_rol in cursor.fetchall():
                    usuario["roles"].append(fila_rol[0])
    return usuario


def listar_roles():
    """Catálogo de roles para mostrar las casillas del formulario."""
    roles = []
    with obtener_conexion() as conexion:
        with conexion.cursor() as cursor:
            cursor.execute("SELECT id_rol, nombre_rol FROM ROL ORDER BY nombre_rol")
            for fila in cursor.fetchall():
                roles.append({"id_rol": fila[0], "nombre_rol": fila[1]})
    return roles


def registrar(nombre_usuario, password_encriptada, ids_roles):
    """Crea el usuario y le asigna sus roles en UNA sola transacción."""
    conexion = obtener_conexion()
    cursor = conexion.cursor()

    try:
        # Se pide el ID antes porque se necesita también para USUARIO_ROL
        cursor.execute("SELECT SEQ_USUARIO.NEXTVAL FROM DUAL")
        id_usuario = cursor.fetchone()[0]

        # 1. El usuario, activo desde el inicio
        cursor.execute("""
            INSERT INTO USUARIO (id_usuario, usuario, password, estado)
            VALUES (:id_usuario, :usuario, :password, 'A')
        """, {"id_usuario": id_usuario, "usuario": nombre_usuario, "password": password_encriptada})

        # 2. Una fila en USUARIO_ROL por cada rol marcado
        for id_rol in ids_roles:
            cursor.execute("INSERT INTO USUARIO_ROL (id_usuario, id_rol) VALUES (:id_usuario, :id_rol)",
                        {"id_usuario": id_usuario, "id_rol": id_rol})

        conexion.commit()
        return id_usuario

    except oracledb.DatabaseError:
        # Ej.: nombre de usuario repetido (UNIQUE) → no se crea ni el usuario ni sus roles
        conexion.rollback()
        raise

    finally:
        cursor.close()
        conexion.close()


def actualizar(id_usuario, nombre_usuario, password_encriptada, ids_roles):
    """Actualiza el usuario y reemplaza sus roles en UNA sola transacción.
    Si password_encriptada es None, la contraseña no se cambia."""
    conexion = obtener_conexion()
    cursor = conexion.cursor()

    try:
        cursor.execute("UPDATE USUARIO SET usuario = :usuario WHERE id_usuario = :id_usuario",
                    {"usuario": nombre_usuario, "id_usuario": id_usuario})

        if password_encriptada is not None:
            cursor.execute("UPDATE USUARIO SET password = :password WHERE id_usuario = :id_usuario",
                        {"password": password_encriptada, "id_usuario": id_usuario})

        # Reemplazar los roles: se borran los anteriores y se insertan los nuevos
        cursor.execute("DELETE FROM USUARIO_ROL WHERE id_usuario = :id_usuario",
                    {"id_usuario": id_usuario})

        for id_rol in ids_roles:
            cursor.execute("INSERT INTO USUARIO_ROL (id_usuario, id_rol) VALUES (:id_usuario, :id_rol)",
                        {"id_usuario": id_usuario, "id_rol": id_rol})

        conexion.commit()

    except oracledb.DatabaseError:
        conexion.rollback()
        raise

    finally:
        cursor.close()
        conexion.close()


def cambiar_estado(id_usuario, nuevo_estado):
    """Activa ('A') o desactiva ('I'). Un usuario inactivo no puede iniciar sesión."""
    with obtener_conexion() as conexion:
        with conexion.cursor() as cursor:
            cursor.execute("UPDATE USUARIO SET estado = :estado WHERE id_usuario = :id_usuario",
                        {"estado": nuevo_estado, "id_usuario": id_usuario})
        conexion.commit()

