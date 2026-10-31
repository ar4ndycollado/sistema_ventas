# models/errores.py
# Convierte los errores de Oracle en mensajes comprensibles para el usuario.
# Los controladores lo usan así:
#     except oracledb.DatabaseError as e:
#         flash(obtener_mensaje_error(e), "error")


def obtener_mensaje_error(excepcion):
    # La excepción trae un objeto con el código ORA (número) y el mensaje completo
    error = excepcion.args[0]
    codigo = error.code

    # ORA-00001: se violó una restricción UNIQUE o PRIMARY KEY
    if codigo == 1:
        return "Ya existe un registro con ese dato. Verifique que no esté duplicado."

    # ORA-02292: se intentó borrar un registro que otra tabla usa (FK)
    if codigo == 2292:
        return "No se puede eliminar porque el registro está siendo utilizado en otras operaciones."

    # ORA-02291: se guardó una FK que apunta a un registro inexistente
    if codigo == 2291:
        return "El registro relacionado no existe."

    # ORA-01400: se dejó vacía una columna NOT NULL
    if codigo == 1400:
        return "Faltan datos obligatorios."

    # ORA-02290: no se cumplió una restricción CHECK
    if codigo == 2290:
        return "Un dato no cumple con las reglas permitidas."

    # Errores propios creados con RAISE_APPLICATION_ERROR (-20000 a -20999)
    # en los procedimientos: su mensaje ya está escrito para el usuario
    if 20000 <= codigo <= 20999:
        primera_linea = error.message.split("\n")[0]       # "ORA-20004: Stock insuficiente..."
        return primera_linea.split(": ", 1)[1]              # "Stock insuficiente..."

    # Cualquier otro error se muestra tal como lo devuelve Oracle
    return "Error en la base de datos: " + error.message
