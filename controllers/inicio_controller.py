# controllers/inicio_controller.py
# Controlador de la página principal: muestra un resumen según el rol del usuario

from flask import Blueprint, render_template, session

from controllers.seguridad import tiene_permiso, tiene_rol
from models import inicio_model, caja_model, producto_model

# Un Blueprint es un "grupo de rutas". Cada módulo (clientes, productos, ventas...)
# tendrá su propio Blueprint en su propio archivo.
inicio_bp = Blueprint("inicio", __name__)


@inicio_bp.route("/")
def inicio():
    # Cada dato se consulta solo si el usuario tiene acceso a ese módulo.
    # None = no mostrar esa tarjeta (la plantilla revisa cada valor).
    ventas_hoy = None
    apertura = None
    bajo_stock = None

    if tiene_permiso("ventas"):
        # El administrador ve las ventas de toda la tienda; los demás, solo las suyas
        if tiene_rol(["ADMINISTRADOR"]):
            ventas_hoy = inicio_model.ventas_de_hoy()
        else:
            ventas_hoy = inicio_model.ventas_de_hoy(session["id_usuario"])

    if tiene_permiso("caja"):
        apertura = caja_model.obtener_apertura_activa(session["id_usuario"])

    if tiene_permiso("productos"):
        bajo_stock = producto_model.listar_bajo_stock()

    return render_template(
        "inicio.html",
        ventas_hoy=ventas_hoy,
        apertura=apertura,
        bajo_stock=bajo_stock
    )
