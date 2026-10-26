# models/errores.py
# Convierte los errores de Oracle en mensajes comprensibles para el usuario


def obtener_mensaje_error(excepcion):
    error = excepcion.args[0]
    codigo = error.code

    if codigo == 1:
        return "Ya existe un registro con ese dato. Verifique que no esté duplicado."

    if codigo == 2292:
        return "No se puede eliminar porque el registro está siendo utilizado en otras operaciones."

    if codigo == 2291:
        return "El registro relacionado no existe."

    if codigo == 1400:
        return "Faltan datos obligatorios."

    if codigo == 2290:
        return "Un dato no cumple con las reglas permitidas."

    # Errores propios creados con RAISE_APPLICATION_ERROR (-20000 a -20999)
    if 20000 <= codigo <= 20999:
        primera_linea = error.message.split("\n")[0]       # "ORA-20004: Stock insuficiente..."
        return primera_linea.split(": ", 1)[1]              # "Stock insuficiente..."

    return "Error en la base de datos: " + error.message