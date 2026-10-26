# controllers/seguridad.py
# Define qué roles pueden acceder a cada módulo de la aplicación

from flask import session

TODOS = ["ADMINISTRADOR", "VENDEDOR", "CAJERO", "BODEGUERO"]

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
    roles_usuario = session.get("roles", [])
    roles_permitidos = PERMISOS.get(modulo, [])

    for rol in roles_usuario:
        if rol in roles_permitidos:
            return True

    return False

def tiene_rol(roles_permitidos):
    """Revisa si el usuario conectado tiene alguno de los roles indicados."""
    roles_usuario = session.get("roles", [])

    for rol in roles_usuario:
        if rol in roles_permitidos:
            return True

    return False