# controllers/productos_controller.py
# CONTROLADOR: gestión de productos y existencias.
# El VENDEDOR puede entrar al módulo (PERMISOS), pero solo para consultar;
# crear, editar, activar/desactivar y ver la auditoría exige ROLES_EDICION.
# El stock nunca se edita aquí: solo cambia con compras, ventas y anulaciones.

from flask import Blueprint, render_template, request, redirect, url_for, flash, session
import oracledb
from models import producto_model
from models.errores import obtener_mensaje_error
from controllers.seguridad import tiene_rol

productos_bp = Blueprint("productos", __name__, url_prefix="/productos")

# Roles que pueden crear, editar o desactivar productos
ROLES_EDICION = ["ADMINISTRADOR", "BODEGUERO"]

# Valores iniciales del formulario de un producto nuevo
PRODUCTO_VACIO = {"nombre": "", "precio_compra": "", "precio_venta": "",
                "stock_minimo": 5, "stock": 0}


def leer_formulario():
    """Toma los campos del formulario como texto; validar() los convierte a número."""
    return {
        "nombre": request.form["nombre"].strip(),
        "precio_compra": request.form["precio_compra"].strip(),
        "precio_venta": request.form["precio_venta"].strip(),
        "stock_minimo": request.form["stock_minimo"].strip()
    }


def validar(producto):
    """Valida los datos y convierte los números. Devuelve la lista de errores."""
    errores = []

    if producto["nombre"] == "":
        errores.append("El nombre es obligatorio.")

    # float() lanza ValueError si el texto no es un número (por ejemplo "abc")
    try:
        producto["precio_compra"] = float(producto["precio_compra"])
        producto["precio_venta"] = float(producto["precio_venta"])

        if producto["precio_compra"] <= 0 or producto["precio_venta"] <= 0:
            errores.append("Los precios deben ser mayores a cero.")
        # Regla RN-07 (también la garantiza un CHECK en Oracle)
        elif producto["precio_venta"] < producto["precio_compra"]:
            errores.append("El precio de venta no puede ser menor al precio de compra.")
    except ValueError:
        errores.append("Los precios deben ser números válidos.")

    try:
        producto["stock_minimo"] = int(producto["stock_minimo"])
        if producto["stock_minimo"] < 0:
            errores.append("El stock mínimo no puede ser negativo.")
    except ValueError:
        errores.append("El stock mínimo debe ser un número entero.")

    return errores


def sin_permiso_edicion():
    """Respuesta común cuando un rol de solo consulta intenta modificar."""
    flash("Su rol solo permite consultar productos.", "error")
    return redirect(url_for("productos.lista"))


@productos_bp.route("/")
def lista():
    # El filtro llega en la URL: /productos/?filtro=bajo muestra solo los de bajo stock
    filtro = request.args.get("filtro", "todos")

    if filtro == "bajo":
        productos = producto_model.listar_bajo_stock()
    else:
        productos = producto_model.listar()

    return render_template("productos/lista.html", productos=productos, filtro=filtro)


@productos_bp.route("/nuevo", methods=["GET", "POST"])
def nuevo():
    if not tiene_rol(ROLES_EDICION):
        return sin_permiso_edicion()

    if request.method == "GET":
        return render_template("productos/formulario.html", producto=PRODUCTO_VACIO, es_nuevo=True)

    producto = leer_formulario()
    errores = validar(producto)

    if len(errores) > 0:
        for error in errores:
            flash(error, "error")
        producto["stock"] = 0   # el formulario muestra el stock; uno nuevo siempre tiene 0
        return render_template("productos/formulario.html", producto=producto, es_nuevo=True)

    try:
        producto_model.registrar(producto)
        flash("Producto registrado correctamente. Su stock inicial es 0; aumentará al registrar una compra.", "exito")
        return redirect(url_for("productos.lista"))
    except oracledb.DatabaseError as e:
        flash(obtener_mensaje_error(e), "error")
        producto["stock"] = 0
        return render_template("productos/formulario.html", producto=producto, es_nuevo=True)


@productos_bp.route("/editar/<int:id_producto>", methods=["GET", "POST"])
def editar(id_producto):
    if not tiene_rol(ROLES_EDICION):
        return sin_permiso_edicion()

    producto_actual = producto_model.obtener(id_producto)
    if producto_actual is None:
        flash("El producto no existe.", "error")
        return redirect(url_for("productos.lista"))

    if request.method == "GET":
        return render_template("productos/formulario.html", producto=producto_actual, es_nuevo=False)

    producto = leer_formulario()
    errores = validar(producto)
    producto["stock"] = producto_actual["stock"]   # solo para mostrarlo en el formulario

    if len(errores) > 0:
        for error in errores:
            flash(error, "error")
        return render_template("productos/formulario.html", producto=producto, es_nuevo=False)

    try:
        # Se envía el usuario para que el trigger TRG_AUDITORIA_PRECIO sepa quién cambió el precio
        producto_model.actualizar(id_producto, producto, session["usuario"])
        flash("Producto actualizado correctamente.", "exito")
        return redirect(url_for("productos.lista"))
    except oracledb.DatabaseError as e:
        flash(obtener_mensaje_error(e), "error")
        return render_template("productos/formulario.html", producto=producto, es_nuevo=False)


@productos_bp.route("/estado/<int:id_producto>", methods=["POST"])
def cambiar_estado(id_producto):
    if not tiene_rol(ROLES_EDICION):
        return sin_permiso_edicion()

    producto = producto_model.obtener(id_producto)
    if producto is None:
        flash("El producto no existe.", "error")
        return redirect(url_for("productos.lista"))

    # Un producto con historial no se elimina: se desactiva (RN-08).
    # El botón alterna el estado: A (activo) <-> I (inactivo).
    if producto["estado"] == "A":
        nuevo_estado = "I"
        mensaje = "Producto desactivado. Ya no podrá venderse."
    else:
        nuevo_estado = "A"
        mensaje = "Producto activado nuevamente."

    try:
        producto_model.cambiar_estado(id_producto, nuevo_estado)
        flash(mensaje, "exito")
    except oracledb.DatabaseError as e:
        flash(obtener_mensaje_error(e), "error")

    return redirect(url_for("productos.lista"))


@productos_bp.route("/auditoria")
def auditoria():
    if not tiene_rol(ROLES_EDICION):
        return sin_permiso_edicion()

    # Historial de cambios de precio que registra el trigger TRG_AUDITORIA_PRECIO
    registros = producto_model.listar_auditoria()
    return render_template("productos/auditoria.html", registros=registros)