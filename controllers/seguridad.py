# controllers/seguridad.py
# Define qué roles pueden acceder a cada módulo de la aplicación.
# Lo usan app.py (para bloquear páginas) y las plantillas (para armar el menú).

from flask import session

TODOS = ["ADMINISTRADOR", "VENDEDOR", "CAJERO", "BODEGUERO"]

# Llave: nombre del Blueprint (módulo). Valor: roles que pueden entrar.
# Para dar o quitar acceso a un rol basta con cambiar esta tabla.
PERMISOS = {
    "inicio":       TODOS,
    "clientes":     ["ADMINISTRADOR", "VENDEDOR", "CAJERO"],
    "proveedores":  ["ADMINISTRADOR", "BODEGUERO"],
    "productos":    ["ADMINISTRADOR", "BODEGUERO", "VENDEDOR"],
    "compras":      ["ADMINISTRADOR", "BODEGUERO"],
    "ventas":       ["ADMINISTRADOR", "VENDEDOR", "CAJERO"],
    "cotizaciones": ["ADMINISTRADOR", "VENDEDOR"],
    "caja":         ["ADMINISTRADOR", "CAJERO", "VENDEDOR"],
    "kardex":       ["ADMINISTRADOR", "BODEGUERO"],
    "reportes":     ["ADMINISTRADOR"],
    "usuarios":     ["ADMINISTRADOR"],
}


def tiene_permiso(modulo):
    """Revisa si alguno de los roles del usuario conectado puede usar el módulo."""
    # Los roles se guardaron en la sesión al iniciar sesión (auth_controller.py)
    roles_usuario = session.get("roles", [])
    # Un módulo que no está en PERMISOS no lo puede usar nadie
    roles_permitidos = PERMISOS.get(modulo, [])

    # Basta con que UNO de sus roles esté permitido (un usuario puede tener varios)
    for rol in roles_usuario:
        if rol in roles_permitidos:
            return True

    return False

def tiene_rol(roles_permitidos):
    """Revisa si el usuario conectado tiene alguno de los roles indicados.
    Se usa para acciones dentro de un módulo, por ejemplo: solo el
    ADMINISTRADOR modifica precios o ve las ventas de todos."""
    roles_usuario = session.get("roles", [])

    for rol in roles_usuario:
        if rol in roles_permitidos:
            return True

    return False
