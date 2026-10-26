# models/cliente_model.py
# MODELO: consultas a la tabla CLIENTES

from models.conexion import obtener_conexion


def listar():
    clientes = []
    with obtener_conexion() as conexion:
        with conexion.cursor() as cursor:
            cursor.execute("""
                SELECT id_cliente, nombre, direccion, telefono, correo
                FROM CLIENTES
                ORDER BY nombre
            """)
            for fila in cursor.fetchall():
                clientes.append({
                    "id_cliente": fila[0],
                    "nombre": fila[1],
                    "direccion": fila[2],
                    "telefono": fila[3],
                    "correo": fila[4]
                })
    return clientes


def obtener(id_cliente):
    cliente = None
    with obtener_conexion() as conexion:
        with conexion.cursor() as cursor:
            cursor.execute("""
                SELECT id_cliente, nombre, direccion, telefono, correo
                FROM CLIENTES
                WHERE id_cliente = :id_cliente
            """, {"id_cliente": id_cliente})
            fila = cursor.fetchone()
            if fila is not None:
                cliente = {
                    "id_cliente": fila[0],
                    "nombre": fila[1],
                    "direccion": fila[2],
                    "telefono": fila[3],
                    "correo": fila[4]
                }
    return cliente


def registrar(cliente):
    # Usa el procedimiento almacenado del Lab 3
    with obtener_conexion() as conexion:
        with conexion.cursor() as cursor:
            cursor.callproc("SP_REGISTRAR_CLIENTE", [
                cliente["nombre"],
                cliente["direccion"],
                cliente["telefono"],
                cliente["correo"]
            ])


def actualizar(id_cliente, cliente):
    with obtener_conexion() as conexion:
        with conexion.cursor() as cursor:
            cursor.execute("""
                UPDATE CLIENTES
                SET nombre = :nombre,
                    direccion = :direccion,
                    telefono = :telefono,
                    correo = :correo
                WHERE id_cliente = :id_cliente
            """, {
                "nombre": cliente["nombre"],
                "direccion": cliente["direccion"],
                "telefono": cliente["telefono"],
                "correo": cliente["correo"],
                "id_cliente": id_cliente
            })
        conexion.commit()


def eliminar(id_cliente):
    with obtener_conexion() as conexion:
        with conexion.cursor() as cursor:
            cursor.execute("DELETE FROM CLIENTES WHERE id_cliente = :id_cliente",
                        {"id_cliente": id_cliente})
        conexion.commit()