# controllers/clientes_controller.py
# CONTROLADOR: gestión de clientes (listar, registrar, editar y eliminar).
# Recibe los datos del formulario, los valida y llama al modelo (cliente_model),
# que es el único que habla con Oracle.

from flask import Blueprint, render_template, request, redirect, url_for, flash
import oracledb
from models import cliente_model
from models.errores import obtener_mensaje_error

# url_prefix: todas las rutas de este archivo empiezan con /clientes
clientes_bp = Blueprint("clientes", __name__, url_prefix="/clientes")

# Datos en blanco para mostrar el formulario de un cliente nuevo
CLIENTE_VACIO = {"nombre": "", "direccion": "", "telefono": "", "correo": ""}


def leer_formulario():
    """Toma los campos del formulario y los limpia (quita espacios; correo en minúsculas)."""
    return {
        "nombre": request.form["nombre"].strip(),
        "direccion": request.form["direccion"].strip(),
        "telefono": request.form["telefono"].strip(),
        "correo": request.form["correo"].strip().lower()
    }


def validar(cliente):
    """Devuelve la lista de errores encontrados. Lista vacía = datos correctos.
    Se valida aquí para dar mensajes claros antes de llegar a Oracle."""
    errores = []
    if cliente["nombre"] == "":
        errores.append("El nombre es obligatorio.")
    if cliente["telefono"] != "" and not cliente["telefono"].isdigit():
        errores.append("El teléfono solo debe contener números.")
    if cliente["correo"] != "" and "@" not in cliente["correo"]:
        errores.append("El correo no tiene un formato válido.")
    if cliente["direccion"] == "":
        errores.append("La dirección es obligatoria.")
    if cliente["telefono"] == "":
        errores.append("El teléfono es obligatorio.")
    return errores




@clientes_bp.route("/")
def lista():
    clientes = cliente_model.listar()
    return render_template("clientes/lista.html", clientes=clientes)


@clientes_bp.route("/nuevo", methods=["GET", "POST"])
def nuevo():
    # GET: mostrar el formulario vacío
    if request.method == "GET":
        return render_template("clientes/formulario.html", cliente=CLIENTE_VACIO, es_nuevo=True)

    # POST: leer y validar lo que escribió el usuario
    cliente = leer_formulario()
    errores = validar(cliente)

    # Si hay errores se vuelve a mostrar el formulario con los datos escritos
    if len(errores) > 0:
        for error in errores:
            flash(error, "error")
        return render_template("clientes/formulario.html", cliente=cliente, es_nuevo=True)

    try:
        cliente_model.registrar(cliente)
        flash("Cliente registrado correctamente.", "exito")
        return redirect(url_for("clientes.lista"))
    except oracledb.DatabaseError as e:
        # Por ejemplo, ORA-00001 si el correo ya está registrado (UNIQUE)
        flash(obtener_mensaje_error(e), "error")
        return render_template("clientes/formulario.html", cliente=cliente, es_nuevo=True)


@clientes_bp.route("/editar/<int:id_cliente>", methods=["GET", "POST"])
def editar(id_cliente):
    # GET: cargar el cliente desde la base para llenar el formulario
    if request.method == "GET":
        cliente = cliente_model.obtener(id_cliente)
        if cliente is None:
            flash("El cliente no existe.", "error")
            return redirect(url_for("clientes.lista"))
        return render_template("clientes/formulario.html", cliente=cliente, es_nuevo=False)

    # POST: mismo proceso que en "nuevo", pero se actualiza en lugar de insertar
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


# Solo acepta POST (botón con formulario) para que no se pueda borrar con un simple enlace
@clientes_bp.route("/eliminar/<int:id_cliente>", methods=["POST"])
def eliminar(id_cliente):
    try:
        cliente_model.eliminar(id_cliente)
        flash("Cliente eliminado correctamente.", "exito")
    except oracledb.DatabaseError as e:
        # Si el cliente tiene ventas o cotizaciones, la FK lo impide (ORA-02292)
        flash(obtener_mensaje_error(e), "error")
    return redirect(url_for("clientes.lista"))
