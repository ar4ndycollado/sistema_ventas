# models/proveedor_model.py
# MODELO: consultas a la tabla PROVEEDORES

from models.conexion import obtener_conexion


def listar():
    proveedores = []
    with obtener_conexion() as conexion:
        with conexion.cursor() as cursor:
            cursor.execute("""
                SELECT id_proveedor, nombre, nit, direccion, telefono
                FROM PROVEEDORES
                ORDER BY nombre
            """)
            for fila in cursor.fetchall():
                proveedores.append({
                    "id_proveedor": fila[0],
                    "nombre": fila[1],
                    "nit": fila[2],
                    "direccion": fila[3],
                    "telefono": fila[4]
                })
    return proveedores


def obtener(id_proveedor):
    proveedor = None
    with obtener_conexion() as conexion:
        with conexion.cursor() as cursor:
            cursor.execute("""
                SELECT id_proveedor, nombre, nit, direccion, telefono
                FROM PROVEEDORES
                WHERE id_proveedor = :id_proveedor
            """, {"id_proveedor": id_proveedor})
            fila = cursor.fetchone()
            if fila is not None:
                proveedor = {
                    "id_proveedor": fila[0],
                    "nombre": fila[1],
                    "nit": fila[2],
                    "direccion": fila[3],
                    "telefono": fila[4]
                }
    return proveedor


def registrar(proveedor):
    with obtener_conexion() as conexion:
        with conexion.cursor() as cursor:
            cursor.execute("""
                INSERT INTO PROVEEDORES (id_proveedor, nombre, nit, direccion, telefono)
                VALUES (SEQ_PROVEEDOR.NEXTVAL, :nombre, :nit, :direccion, :telefono)
            """, {
                "nombre": proveedor["nombre"],
                "nit": proveedor["nit"],
                "direccion": proveedor["direccion"],
                "telefono": proveedor["telefono"]
            })
        conexion.commit()


def actualizar(id_proveedor, proveedor):
    with obtener_conexion() as conexion:
        with conexion.cursor() as cursor:
            cursor.execute("""
                UPDATE PROVEEDORES
                SET nombre = :nombre,
                    nit = :nit,
                    direccion = :direccion,
                    telefono = :telefono
                WHERE id_proveedor = :id_proveedor
            """, {
                "nombre": proveedor["nombre"],
                "nit": proveedor["nit"],
                "direccion": proveedor["direccion"],
                "telefono": proveedor["telefono"],
                "id_proveedor": id_proveedor
            })
        conexion.commit()


def eliminar(id_proveedor):
    with obtener_conexion() as conexion:
        with conexion.cursor() as cursor:
            cursor.execute("DELETE FROM PROVEEDORES WHERE id_proveedor = :id_proveedor",
                        {"id_proveedor": id_proveedor})
        conexion.commit()