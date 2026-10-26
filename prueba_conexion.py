# prueba_conexion.py
# Archivo temporal para verificar que Python se conecta a Oracle

from models.conexion import obtener_conexion

conexion = obtener_conexion()
cursor = conexion.cursor()

cursor.execute("SELECT id_producto, nombre, stock FROM PRODUCTOS ORDER BY id_producto")
productos = cursor.fetchall()

print("Conexión exitosa. Productos encontrados:")
for producto in productos:
    print(producto[0], "-", producto[1], "- Stock:", producto[2])

cursor.close()
conexion.close()