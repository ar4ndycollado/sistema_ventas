# models/conexion.py
# Se encarga únicamente de abrir la conexión con Oracle

import oracledb
import config


def obtener_conexion():
    conexion = oracledb.connect(
        user=config.DB_USUARIO,
        password=config.DB_PASSWORD,
        dsn=config.DB_DSN
    )
    return conexion