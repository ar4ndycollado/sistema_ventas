# app.py
# Punto de inicio de la aplicación

from flask import Flask, session, request, redirect, url_for, flash
import config

from controllers.caja_controller import caja_bp
from controllers.cotizaciones_controller import cotizaciones_bp
from controllers.ventas_controller import ventas_bp
from controllers.compras_controller import compras_bp
from controllers.productos_controller import productos_bp
from controllers.clientes_controller import clientes_bp
from controllers.proveedores_controller import proveedores_bp
from controllers.inicio_controller import inicio_bp
from controllers.auth_controller import auth_bp
from controllers.seguridad import tiene_permiso, tiene_rol

app = Flask(__name__)
app.secret_key = config.SECRET_KEY

# Registrar los controladores (cada módulo nuevo se agrega aquí)
app.register_blueprint(inicio_bp)
app.register_blueprint(auth_bp)
app.register_blueprint(clientes_bp)
app.register_blueprint(proveedores_bp)
app.register_blueprint(productos_bp)
app.register_blueprint(compras_bp)
app.register_blueprint(ventas_bp)
app.register_blueprint(cotizaciones_bp)
app.register_blueprint(caja_bp)


@app.before_request
def verificar_acceso():
    """Se ejecuta ANTES de cada página: protege todo el sistema."""

    # Páginas que no necesitan sesión: el login y los archivos CSS
    if request.endpoint is None or request.endpoint == "static" or request.blueprint == "auth":
        return

    # Si no ha iniciado sesión, enviarlo al login
    if "id_usuario" not in session:
        return redirect(url_for("auth.login"))

    # Si su rol no tiene permiso para este módulo, bloquearlo
    if not tiene_permiso(request.blueprint):
        flash("No tiene permiso para acceder a ese módulo.", "error")
        return redirect(url_for("inicio.inicio"))


@app.context_processor
def funciones_para_vistas():
    """Permite usar estas funciones dentro de las plantillas HTML."""
    return {"tiene_permiso": tiene_permiso, "tiene_rol": tiene_rol}


if __name__ == "__main__":
    app.run(debug=True)