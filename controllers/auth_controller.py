# controllers/auth_controller.py
# CONTROLADOR: inicio y cierre de sesión

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

    # Validar usuario y contraseña
    if usuario is None or not check_password_hash(usuario["password"], password):
        flash("Usuario o contraseña incorrectos.", "error")
        return render_template("login.html")

    # Validar que esté activo
    if usuario["estado"] != "A":
        flash("El usuario se encuentra inactivo. Contacte al administrador.", "error")
        return render_template("login.html")

    # Validar que tenga al menos un rol
    roles = usuario_model.obtener_roles(usuario["id_usuario"])
    if len(roles) == 0:
        flash("El usuario no tiene un rol asignado.", "error")
        return render_template("login.html")

    # Todo correcto: guardar los datos en la sesión
    session["id_usuario"] = usuario["id_usuario"]
    session["usuario"] = usuario["usuario"]
    session["roles"] = roles

    return redirect(url_for("inicio.inicio"))


@auth_bp.route("/logout")
def logout():
    session.clear()
    flash("Sesión cerrada correctamente.", "exito")
    return redirect(url_for("auth.login"))