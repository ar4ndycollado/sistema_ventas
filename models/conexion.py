# models/conexion.py
# Se encarga únicamente de abrir la conexión con Oracle.
# Todos los modelos la usan así:
#     with obtener_conexion() as conexion:
# El "with" cierra la conexión automáticamente al terminar, aunque ocurra un error.

import oracledb
import config


def obtener_conexion():
    """Abre una conexión nueva con el esquema SISTEMA_VENTAS.
    python-oracledb trabaja en modo "thin": no necesita instalar el cliente de Oracle."""
    conexion = oracledb.connect(
        user=config.DB_USUARIO,        # usuario de la base (sistema_ventas)
        password=config.DB_PASSWORD,   # está en config.py, que no se sube a GitHub
        dsn=config.DB_DSN              # servidor:puerto/servicio, ej. localhost:1521/xepdb1
    )
    return conexion
