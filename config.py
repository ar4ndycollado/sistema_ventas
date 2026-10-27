# config.py
# Datos de conexión a la base de datos Oracle

DB_USUARIO = "sistema_ventas"
DB_PASSWORD = "12345"
DB_DSN = "localhost:1521/xepdb1"

# Clave que usa Flask para los mensajes entre páginas (puede ser cualquier texto)
SECRET_KEY = "clave_secreta_sistema_ventas"

# Datos que aparecen en el recibo
NEGOCIO = {
    "nombre": "Eden Store",
    "direccion": "16 calle, 4-63 zona 4 Santa Cruz del Quiche",
    "telefono": "59560379",
    "nit": "11228369-1"
}