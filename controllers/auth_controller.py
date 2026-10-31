# controllers/auth_controller.py
# CONTROLADOR: inicio y cierre de sesión.
# Es el único módulo que no exige sesión (app.py lo deja pasar).

from flask import Blueprint, render_template, request, redirect, url_for, session, flash
from werkzeug.security import check_password_hash
from models import usuario_model

auth_bp = Blueprint("auth", __name__)


@auth_bp.route("/login", methods=["GET", "POST"])
def login():
    # GET: solo mostrar el formulario
    if request.method == "GET":
        return render_template("login.html")

    # POST: el usuario envió el formulario
    nombre = request.form["usuario"].strip()
    password = request.form["password"]

    # Validar campos obligatorios
    if nombre == "" or password == "":
        flash("Ingrese su usuario y contraseña.", "error")
        return render_template("login.html")

    usuario = usuario_model.buscar_usuario(nombre)

    # Validar usuario y contraseña.
    # En la base solo se guarda el hash; check_password_hash cifra lo escrito
    # y lo compara con ese hash. El mensaje es el mismo en ambos casos para
    # no revelar si el usuario existe.
    if usuario is None or not check_password_hash(usuario["password"], password):
        flash("Usuario o contraseña incorrectos.", "error")
        return render_template("login.html")

    # Validar que esté activo (regla RN-01: un usuario inactivo no entra)
    if usuario["estado"] != "A":
        flash("El usuario se encuentra inactivo. Contacte al administrador.", "error")
        return render_template("login.html")

    # Validar que tenga al menos un rol (sin rol no podría usar ningún módulo)
    roles = usuario_model.obtener_roles(usuario["id_usuario"])
    if len(roles) == 0:
        flash("El usuario no tiene un rol asignado.", "error")
        return render_template("login.html")

    # Todo correcto: guardar los datos en la sesión.
    # La sesión es una cookie firmada; app.py la revisa en cada página.
    session["id_usuario"] = usuario["id_usuario"]
    session["usuario"] = usuario["usuario"]
    session["roles"] = roles

    return redirect(url_for("inicio.inicio"))


@auth_bp.route("/logout")
def logout():
    # Borrar todos los datos de la sesión (también los carritos)
    session.clear()
    flash("Sesión cerrada correctamente.", "exito")
    return redirect(url_for("auth.login"))
