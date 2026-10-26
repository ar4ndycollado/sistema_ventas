# controllers/clientes_controller.py
# CONTROLADOR: gestión de clientes

from flask import Blueprint, render_template, request, redirect, url_for, flash
import oracledb
from models import cliente_model
from models.errores import obtener_mensaje_error

clientes_bp = Blueprint("clientes", __name__, url_prefix="/clientes")

CLIENTE_VACIO = {"nombre": "", "direccion": "", "telefono": "", "correo": ""}


def leer_formulario():
    return {
        "nombre": request.form["nombre"].strip(),
        "direccion": request.form["direccion"].strip(),
        "telefono": request.form["telefono"].strip(),
        "correo": request.form["correo"].strip().lower()
    }


def validar(cliente):
    errores = []
    if cliente["nombre"] == "":
        errores.append("El nombre es obligatorio.")
    if cliente["telefono"] != "" and not cliente["telefono"].isdigit():
        errores.append("El teléfono solo debe contener números.")
    if cliente["correo"] != "" and "@" not in cliente["correo"]:
        errores.append("El correo no tiene un formato válido.")
    return errores


@clientes_bp.route("/")
def lista():
    clientes = cliente_model.listar()
    return render_template("clientes/lista.html", clientes=clientes)


@clientes_bp.route("/nuevo", methods=["GET", "POST"])
def nuevo():
    if request.method == "GET":
        return render_template("clientes/formulario.html", cliente=CLIENTE_VACIO, es_nuevo=True)

    cliente = leer_formulario()
    errores = validar(cliente)

    if len(errores) > 0:
        for error in errores:
            flash(error, "error")
        return render_template("clientes/formulario.html", cliente=cliente, es_nuevo=True)

    try:
        cliente_model.registrar(cliente)
        flash("Cliente registrado correctamente.", "exito")
        return redirect(url_for("clientes.lista"))
    except oracledb.DatabaseError as e:
        flash(obtener_mensaje_error(e), "error")
        return render_template("clientes/formulario.html", cliente=cliente, es_nuevo=True)


@clientes_bp.route("/editar/<int:id_cliente>", methods=["GET", "POST"])
def editar(id_cliente):
    if request.method == "GET":
        cliente = cliente_model.obtener(id_cliente)
        if cliente is None:
            flash("El cliente no existe.", "error")
            return redirect(url_for("clientes.lista"))
        return render_template("clientes/formulario.html", cliente=cliente, es_nuevo=False)

    cliente = leer_formulario()
    errores = validar(cliente)

    if len(errores) > 0:
        for error in errores:
            flash(error, "error")
        return render_template("clientes/formulario.html", cliente=cliente, es_nuevo=False)

    try:
        cliente_model.actualizar(id_cliente, cliente)
        flash("Cliente actualizado correctamente.", "exito")
        return redirect(url_for("clientes.lista"))
    except oracledb.DatabaseError as e:
        flash(obtener_mensaje_error(e), "error")
        return render_template("clientes/formulario.html", cliente=cliente, es_nuevo=False)


@clientes_bp.route("/eliminar/<int:id_cliente>", methods=["POST"])
def eliminar(id_cliente):
    try:
        cliente_model.eliminar(id_cliente)
        flash("Cliente eliminado correctamente.", "exito")
    except oracledb.DatabaseError as e:
        flash(obtener_mensaje_error(e), "error")
    return redirect(url_for("clientes.lista"))