# app.py
# Punto de inicio de la aplicación.
# Crea la aplicación Flask, registra los módulos (Blueprints) y protege todas
# las páginas: nadie entra sin iniciar sesión ni a un módulo que su rol no permite.
# Para ejecutarla: python app.py  →  http://127.0.0.1:5000

from flask import Flask, session, request, redirect, url_for, flash
import config

# Cada controlador es un Blueprint: un grupo de rutas de un solo módulo
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
from controllers.kardex_controller import kardex_bp
from controllers.reportes_controller import reportes_bp
from controllers.usuarios_controller import usuarios_bp

app = Flask(__name__)

# La clave secreta firma la cookie de la sesión: sin ella no se puede usar "session"
app.secret_key = config.SECRET_KEY

# Registrar los controladores (cada módulo nuevo se agrega aquí).
# El nombre del Blueprint (por ejemplo "clientes") es el mismo que se usa
# en PERMISOS de controllers/seguridad.py para decidir quién puede entrar.
app.register_blueprint(inicio_bp)
app.register_blueprint(auth_bp)
app.register_blueprint(clientes_bp)
app.register_blueprint(proveedores_bp)
app.register_blueprint(productos_bp)
app.register_blueprint(compras_bp)
app.register_blueprint(ventas_bp)
app.register_blueprint(cotizaciones_bp)
app.register_blueprint(caja_bp)
app.register_blueprint(kardex_bp)
app.register_blueprint(reportes_bp)
app.register_blueprint(usuarios_bp)


@app.before_request
def verificar_acceso():
    """Se ejecuta ANTES de cada página: protege todo el sistema."""

    # Páginas que no necesitan sesión: el login y los archivos CSS
    if request.endpoint is None or request.endpoint == "static" or request.blueprint == "auth":
        return

    # Si no ha iniciado sesión, enviarlo al login
    if "id_usuario" not in session:
        return redirect(url_for("auth.login"))

    # Si su rol no tiene permiso para este módulo, bloquearlo.
    # request.blueprint es el módulo de la página pedida (por ejemplo "ventas").
    if not tiene_permiso(request.blueprint):
        flash("No tiene permiso para acceder a ese módulo.", "error")
        return redirect(url_for("inicio.inicio"))

    # Si no se devuelve nada, Flask continúa y muestra la página pedida


@app.context_processor
def funciones_para_vistas():
    """Permite usar estas funciones dentro de las plantillas HTML.
    Así base.html muestra en el menú solo los módulos permitidos."""
    return {"tiene_permiso": tiene_permiso, "tiene_rol": tiene_rol}


if __name__ == "__main__":
    # debug=True recarga la app al guardar cambios y muestra los errores detallados
    app.run(debug=True)
