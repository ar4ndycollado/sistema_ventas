# controllers/inicio_controller.py
# Controlador de la página principal

from flask import Blueprint, render_template

# Un Blueprint es un "grupo de rutas". Cada módulo (clientes, productos, ventas...)
# tendrá su propio Blueprint en su propio archivo.
inicio_bp = Blueprint("inicio", __name__)


@inicio_bp.route("/")
def inicio():
    return render_template("inicio.html")