# controllers/proveedores_controller.py
# CONTROLADOR: gestión de proveedores

from flask import Blueprint, render_template, request, redirect, url_for, flash
import oracledb
from models import proveedor_model
from models.errores import obtener_mensaje_error

proveedores_bp = Blueprint("proveedores", __name__, url_prefix="/proveedores")

PROVEEDOR_VACIO = {"nombre": "", "nit": "", "direccion": "", "telefono": ""}


def leer_formulario():
    return {
        "nombre": request.form["nombre"].strip(),
        "nit": request.form["nit"].strip().upper(),
        "direccion": request.form["direccion"].strip(),
        "telefono": request.form["telefono"].strip()
    }


def validar(proveedor):
    errores = []
    if proveedor["nombre"] == "":
        errores.append("El nombre es obligatorio.")
    if proveedor["nit"] == "":
        errores.append("El NIT es obligatorio.")
    if proveedor["telefono"] != "" and not proveedor["telefono"].isdigit():
        errores.append("El teléfono solo debe contener números.")
    return errores


@proveedores_bp.route("/")
def lista():
    proveedores = proveedor_model.listar()
    return render_template("proveedores/lista.html", proveedores=proveedores)


@proveedores_bp.route("/nuevo", methods=["GET", "POST"])
def nuevo():
    if request.method == "GET":
        return render_template("proveedores/formulario.html", proveedor=PROVEEDOR_VACIO, es_nuevo=True)

    proveedor = leer_formulario()
    errores = validar(proveedor)

    if len(errores) > 0:
        for error in errores:
            flash(error, "error")
        return render_template("proveedores/formulario.html", proveedor=proveedor, es_nuevo=True)

    try:
        proveedor_model.registrar(proveedor)
        flash("Proveedor registrado correctamente.", "exito")
        return redirect(url_for("proveedores.lista"))
    except oracledb.DatabaseError as e:
        flash(obtener_mensaje_error(e), "error")
        return render_template("proveedores/formulario.html", proveedor=proveedor, es_nuevo=True)


@proveedores_bp.route("/editar/<int:id_proveedor>", methods=["GET", "POST"])
def editar(id_proveedor):
    if request.method == "GET":
        proveedor = proveedor_model.obtener(id_proveedor)
        if proveedor is None:
            flash("El proveedor no existe.", "error")
            return redirect(url_for("proveedores.lista"))
        return render_template("proveedores/formulario.html", proveedor=proveedor, es_nuevo=False)

    proveedor = leer_formulario()
    errores = validar(proveedor)

    if len(errores) > 0:
        for error in errores:
            flash(error, "error")
        return render_template("proveedores/formulario.html", proveedor=proveedor, es_nuevo=False)

    try:
        proveedor_model.actualizar(id_proveedor, proveedor)
        flash("Proveedor actualizado correctamente.", "exito")
        return redirect(url_for("proveedores.lista"))
    except oracledb.DatabaseError as e:
        flash(obtener_mensaje_error(e), "error")
        return render_template("proveedores/formulario.html", proveedor=proveedor, es_nuevo=False)


@proveedores_bp.route("/eliminar/<int:id_proveedor>", methods=["POST"])
def eliminar(id_proveedor):
    try:
        proveedor_model.eliminar(id_proveedor)
        flash("Proveedor eliminado correctamente.", "exito")
    except oracledb.DatabaseError as e:
        flash(obtener_mensaje_error(e), "error")
    return redirect(url_for("proveedores.lista"))