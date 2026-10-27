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
    "direccion": "6a. Avenida 10-25, Zona 1, Guatemala",
    "telefono": "2222-3333",
    "nit": "1234567-8"
}