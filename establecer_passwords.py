# establecer_passwords.py
# Asigna contraseñas encriptadas a los usuarios de prueba.
# Se ejecuta una sola vez (o cuando se quiera reiniciar las contraseñas).

from werkzeug.security import generate_password_hash
from models.conexion import obtener_conexion
import config

# La lista de (usuario, contraseña) está en config.py, que no se sube a GitHub
conexion = obtener_conexion()
cursor = conexion.cursor()

for nombre, password in config.PASSWORDS_PRUEBA:
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