# controllers/usuarios_controller.py
# CONTROLADOR: gestión de usuarios y roles (solo ADMINISTRADOR).
# Un usuario puede tener varios roles (tabla asociativa USUARIO_ROL, RN-02).
# Los usuarios no se eliminan: se desactivan, porque tienen ventas, cajas y
# otros registros que los referencian (RN-08).

from flask import Blueprint, render_template, request, redirect, url_for, flash, session
from werkzeug.security import generate_password_hash
import oracledb
from models import usuario_model, caja_model
from models.errores import obtener_mensaje_error

usuarios_bp = Blueprint("usuarios", __name__, url_prefix="/usuarios")


def leer_formulario():
    """Lee el formulario. "roles" llega como una lista con los IDs de las casillas marcadas."""
    ids_roles = []
    for id_texto in request.form.getlist("roles"):   # casillas marcadas
        ids_roles.append(int(id_texto))

    return {
        "usuario": request.form["usuario"].strip().lower(),
        "password": request.form["password"],
        "confirmar": request.form["confirmar"],
        "roles": ids_roles
    }


def validar(datos, es_nuevo):
    """Devuelve la lista de errores. es_nuevo indica si se está creando o editando."""
    errores = []

    if datos["usuario"] == "":
        errores.append("El nombre de usuario es obligatorio.")
    elif " " in datos["usuario"]:
        errores.append("El nombre de usuario no debe tener espacios.")

    # En un usuario nuevo la contraseña es obligatoria; al editar es opcional
    if es_nuevo or datos["password"] != "":
        if len(datos["password"]) < 6:
            errores.append("La contraseña debe tener al menos 6 caracteres.")
        elif datos["password"] != datos["confirmar"]:
            errores.append("Las contraseñas no coinciden.")

    if len(datos["roles"]) == 0:
        errores.append("Seleccione al menos un rol.")

    return errores


def id_rol_administrador(roles):
    """Busca en el catálogo de roles el ID del rol ADMINISTRADOR."""
    for rol in roles:
        if rol["nombre_rol"] == "ADMINISTRADOR":
            return rol["id_rol"]
    return None


@usuarios_bp.route("/")
def lista():
    return render_template("usuarios/lista.html", usuarios=usuario_model.listar())


@usuarios_bp.route("/nuevo", methods=["GET", "POST"])
def nuevo():
    roles = usuario_model.listar_roles()

    if request.method == "GET":
        usuario = {"usuario": "", "roles": []}
        return render_template("usuarios/formulario.html", usuario=usuario, roles=roles, es_nuevo=True)

    datos = leer_formulario()
    errores = validar(datos, True)

    if len(errores) > 0:
        for error in errores:
            flash(error, "error")
        return render_template("usuarios/formulario.html", usuario=datos, roles=roles, es_nuevo=True)

    try:
        # La contraseña se cifra aquí (hash); Oracle nunca recibe el texto original
        usuario_model.registrar(datos["usuario"], generate_password_hash(datos["password"]), datos["roles"])
        flash("Usuario " + datos["usuario"] + " creado correctamente.", "exito")
        return redirect(url_for("usuarios.lista"))
    except oracledb.DatabaseError as e:
        flash(obtener_mensaje_error(e), "error")
        return render_template("usuarios/formulario.html", usuario=datos, roles=roles, es_nuevo=True)


@usuarios_bp.route("/editar/<int:id_usuario>", methods=["GET", "POST"])
def editar(id_usuario):
    roles = usuario_model.listar_roles()
    usuario_actual = usuario_model.obtener(id_usuario)

    if usuario_actual is None:
        flash("El usuario no existe.", "error")
        return redirect(url_for("usuarios.lista"))

    if request.method == "GET":
        return render_template("usuarios/formulario.html", usuario=usuario_actual, roles=roles, es_nuevo=False)

    datos = leer_formulario()
    errores = validar(datos, False)

    # Un administrador no puede quitarse a sí mismo el rol de administrador
    # (evita que el sistema se quede sin nadie que lo administre)
    if id_usuario == session["id_usuario"] and id_rol_administrador(roles) not in datos["roles"]:
        errores.append("No puede quitarse a sí mismo el rol de administrador.")

    if len(errores) > 0:
        for error in errores:
            flash(error, "error")
        return render_template("usuarios/formulario.html", usuario=datos, roles=roles, es_nuevo=False)

    # Contraseña vacía al editar = conservar la actual (None le indica eso al modelo)
    password_encriptada = None
    if datos["password"] != "":
        password_encriptada = generate_password_hash(datos["password"])

    try:
        # Los roles se guardan en la sesión al iniciar sesión; por eso el
        # cambio se nota hasta que el usuario vuelva a entrar
        usuario_model.actualizar(id_usuario, datos["usuario"], password_encriptada, datos["roles"])
        flash("Usuario actualizado. Los cambios de rol se aplican la próxima vez que inicie sesión.", "exito")
        return redirect(url_for("usuarios.lista"))
    except oracledb.DatabaseError as e:
        flash(obtener_mensaje_error(e), "error")
        return render_template("usuarios/formulario.html", usuario=datos, roles=roles, es_nuevo=False)


@usuarios_bp.route("/estado/<int:id_usuario>", methods=["POST"])
def cambiar_estado(id_usuario):
    usuario = usuario_model.obtener(id_usuario)
    if usuario is None:
        flash("El usuario no existe.", "error")
        return redirect(url_for("usuarios.lista"))

    # Para desactivar se revisa: que no sea uno mismo y que no tenga una caja abierta
    if usuario["estado"] == "A":
        if id_usuario == session["id_usuario"]:
            flash("No puede desactivar su propio usuario.", "error")
            return redirect(url_for("usuarios.lista"))

        if caja_model.obtener_apertura_activa(id_usuario) is not None:
            flash("No se puede desactivar: el usuario tiene una caja abierta.", "error")
            return redirect(url_for("usuarios.lista"))

        nuevo_estado = "I"
        mensaje = "Usuario desactivado. Ya no podrá iniciar sesión."
    else:
        nuevo_estado = "A"
        mensaje = "Usuario activado nuevamente."

    try:
        usuario_model.cambiar_estado(id_usuario, nuevo_estado)
        flash(mensaje, "exito")
    except oracledb.DatabaseError as e:
        flash(obtener_mensaje_error(e), "error")

    return redirect(url_for("usuarios.lista"))