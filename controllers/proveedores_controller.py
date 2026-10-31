# controllers/proveedores_controller.py
# CONTROLADOR: gestión de proveedores (listar, registrar, editar y eliminar).
# Funciona igual que clientes_controller.py, pero con NIT en lugar de correo.

from flask import Blueprint, render_template, request, redirect, url_for, flash
import oracledb
from models import proveedor_model
from models.errores import obtener_mensaje_error

# url_prefix: todas las rutas de este archivo empiezan con /proveedores
proveedores_bp = Blueprint("proveedores", __name__, url_prefix="/proveedores")

# Datos en blanco para mostrar el formulario de un proveedor nuevo
PROVEEDOR_VACIO = {"nombre": "", "nit": "", "direccion": "", "telefono": ""}


def leer_formulario():
    """Toma los campos del formulario y los limpia (el NIT se guarda en mayúsculas)."""
    return {
        "nombre": request.form["nombre"].strip(),
        "nit": request.form["nit"].strip().upper(),
        "direccion": request.form["direccion"].strip(),
        "telefono": request.form["telefono"].strip()
    }


def validar(proveedor):
    """Devuelve la lista de errores encontrados. Lista vacía = datos correctos."""
    errores = []
    if proveedor["nombre"] == "":
        errores.append("El nombre es obligatorio.")
    if proveedor["nit"] == "":
        errores.append("El NIT es obligatorio.")
    if proveedor["telefono"] != "" and not proveedor["telefono"].isdigit():
        errores.append("El teléfono solo debe contener números.")
    if proveedor["direccion"] == "":
        errores.append("La dirección es obligatoria.")
    if proveedor["telefono"] == "":
        errores.append("El teléfono es obligatorio.")
    return errores


@proveedores_bp.route("/")
def lista():
    proveedores = proveedor_model.listar()
    return render_template("proveedores/lista.html", proveedores=proveedores)


@proveedores_bp.route("/nuevo", methods=["GET", "POST"])
def nuevo():
    # GET: mostrar el formulario vacío
    if request.method == "GET":
        return render_template("proveedores/formulario.html", proveedor=PROVEEDOR_VACIO, es_nuevo=True)

    # POST: leer y validar lo que escribió el usuario
    proveedor = leer_formulario()
    errores = validar(proveedor)

    # Si hay errores se vuelve a mostrar el formulario con los datos escritos
    if len(errores) > 0:
        for error in errores:
            flash(error, "error")
        return render_template("proveedores/formulario.html", proveedor=proveedor, es_nuevo=True)

    try:
        proveedor_model.registrar(proveedor)
        flash("Proveedor registrado correctamente.", "exito")
        return redirect(url_for("proveedores.lista"))
    except oracledb.DatabaseError as e:
        # Por ejemplo, ORA-00001 si el NIT ya existe (UNIQUE)
        flash(obtener_mensaje_error(e), "error")
        return render_template("proveedores/formulario.html", proveedor=proveedor, es_nuevo=True)


@proveedores_bp.route("/editar/<int:id_proveedor>", methods=["GET", "POST"])
def editar(id_proveedor):
    # GET: cargar el proveedor desde la base para llenar el formulario
    if request.method == "GET":
        proveedor = proveedor_model.obtener(id_proveedor)
        if proveedor is None:
            flash("El proveedor no existe.", "error")
            return redirect(url_for("proveedores.lista"))
        return render_template("proveedores/formulario.html", proveedor=proveedor, es_nuevo=False)

    # POST: mismo proceso que en "nuevo", pero se actualiza en lugar de insertar
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


# Solo acepta POST para que no se pueda borrar con un simple enlace
@proveedores_bp.route("/eliminar/<int:id_proveedor>", methods=["POST"])
def eliminar(id_proveedor):
    try:
        proveedor_model.eliminar(id_proveedor)
        flash("Proveedor eliminado correctamente.", "exito")
    except oracledb.DatabaseError as e:
        # Si el proveedor tiene compras, la FK lo impide (ORA-02292)
        flash(obtener_mensaje_error(e), "error")
    return redirect(url_for("proveedores.lista"))
