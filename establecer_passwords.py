# establecer_passwords.py
# Asigna contraseñas encriptadas a los usuarios de prueba.
# Se ejecuta una sola vez (o cuando se quiera reiniciar las contraseñas).

from werkzeug.security import generate_password_hash
from models.conexion import obtener_conexion

# Lista de (usuario, contraseña en texto normal)
usuarios = [
    ("admin_marta", "admin123"),
    ("cajero1", "cajero123"),
    ("vendedor2", "vendedor123"),
    ("bodega_lab", "bodega123"),
    ("usuario_inactivo", "inactivo123"),
]

conexion = obtener_conexion()
cursor = conexion.cursor()

for nombre, password in usuarios:
    password_encriptada = generate_password_hash(password)

    cursor.execute(
        "UPDATE USUARIO SET password = :password WHERE usuario = :usuario",
        {"password": password_encriptada, "usuario": nombre}
    )

    if cursor.rowcount == 1:
        print("Contraseña actualizada para:", nombre)
    else:
        print("No se encontró el usuario:", nombre)

conexion.commit()
cursor.close()
conexion.close()