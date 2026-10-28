# config.example.py
# Plantilla de config.py. Cópiela con el nombre config.py y escriba sus datos.
# config.py NO se sube a GitHub porque contiene contraseñas.

# Datos de conexión a la base de datos Oracle
DB_USUARIO = "sistema_ventas"
DB_PASSWORD = "escriba_aqui_la_contraseña"
DB_DSN = "localhost:1521/xepdb1"

# Clave que usa Flask para firmar la sesión (use un texto largo y difícil de adivinar)
SECRET_KEY = "escriba_aqui_una_clave_secreta"

# Datos que aparecen en el recibo
NEGOCIO = {
    "nombre": "TecnoMax",
    "direccion": "Dirección del negocio",
    "telefono": "00000000",
    "nit": "0000000-0"
}

# Contraseñas de los usuarios de prueba (las usa establecer_passwords.py)
# Las contraseñas están en el encabezado del script SQL.
PASSWORDS_PRUEBA = [
    ("admin_marta", "contraseña"),
    ("cajero1", "contraseña"),
    ("vendedor2", "contraseña"),
    ("bodega_lab", "contraseña"),
    ("usuario_inactivo", "contraseña"),
]
