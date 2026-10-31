# models/cliente_model.py
# MODELO: consultas a la tabla CLIENTES.
# Cada función abre su conexión, ejecuta el SQL con variables de enlace (:nombre)
# para evitar inyección SQL y devuelve diccionarios para las plantillas.

from models.conexion import obtener_conexion


def listar():
    """Devuelve todos los clientes ordenados por nombre."""
    clientes = []
    with obtener_conexion() as conexion:
        with conexion.cursor() as cursor:
            cursor.execute("""
                SELECT id_cliente, nombre, direccion, telefono, correo
                FROM CLIENTES
                ORDER BY nombre
            """)
            # Cada fila llega como tupla; se convierte en diccionario por nombre de columna
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
    """Devuelve un cliente, o None si no existe."""
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
    # Usa el procedimiento almacenado del Lab 3 (SP_REGISTRAR_CLIENTE).
    # El procedimiento toma el ID de la secuencia y hace su propio COMMIT,
    # por eso aquí no se llama a conexion.commit().
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
        # Sin commit el cambio se perdería al cerrar la conexión
        conexion.commit()


def eliminar(id_cliente):
    # Si el cliente tiene ventas o cotizaciones, Oracle lanza ORA-02292 (FK)
    # y el controlador muestra el mensaje; no se borra nada.
    with obtener_conexion() as conexion:
        with conexion.cursor() as cursor:
            cursor.execute("DELETE FROM CLIENTES WHERE id_cliente = :id_cliente",
                        {"id_cliente": id_cliente})
        conexion.commit()
