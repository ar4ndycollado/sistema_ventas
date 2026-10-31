# establecer_passwords.py
# Asigna contraseñas encriptadas a los usuarios de prueba.
# Se ejecuta una sola vez (o cuando se quiera reiniciar las contraseñas):
#     python establecer_passwords.py

from werkzeug.security import generate_password_hash
from models.conexion import obtener_conexion
import config

# La lista de (usuario, contraseña) está en config.py, que no se sube a GitHub
conexion = obtener_conexion()
cursor = conexion.cursor()

for nombre, password in config.PASSWORDS_PRUEBA:
    # Se guarda el hash (scrypt), nunca la contraseña en texto plano
    password_encriptada = generate_password_hash(password)

    cursor.execute(
        "UPDATE USUARIO SET password = :password WHERE usuario = :usuario",
        {"password": password_encriptada, "usuario": nombre}
    )

    # rowcount indica cuántas filas cambió el UPDATE: 1 = el usuario existe
    if cursor.rowcount == 1:
        print("Contraseña actualizada para:", nombre)
    else:
        print("No se encontró el usuario:", nombre)

# Confirmar todos los cambios juntos
conexion.commit()
cursor.close()
conexion.close()
