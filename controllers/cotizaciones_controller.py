# controllers/cotizaciones_controller.py
# CONTROLADOR: cotizaciones (carrito) y conversión a venta

from flask import Blueprint, render_template, request, redirect, url_for, flash, session
import oracledb
from models import cotizacion_model, producto_model, cliente_model
from models.errores import obtener_mensaje_error
from controllers.seguridad import tiene_permiso

cotizaciones_bp = Blueprint("cotizaciones", __name__, url_prefix="/cotizaciones")


def obtener_carrito():
    if "carrito_cotizacion" not in session:
        session["carrito_cotizacion"] = []
    return session["carrito_cotizacion"]


def calcular_total(carrito):
    total = 0
    for linea in carrito:
        total = total + linea["subtotal"]
    return total


@cotizaciones_bp.route("/")
def lista():
    # Antes de mostrar la lista, marcar como caducadas las que ya vencieron
    cotizacion_model.caducar_vencidas()
    cotizaciones = cotizacion_model.listar()
    return render_template("cotizaciones/lista.html", cotizaciones=cotizaciones)


@cotizaciones_bp.route("/nueva")
def nueva():
    carrito = obtener_carrito()
    return render_template(
        "cotizaciones/nueva.html",
        carrito=carrito,
        total=calcular_total(carrito),
        productos=producto_model.listar_activos(),
        clientes=cliente_model.listar()
    )


@cotizaciones_bp.route("/agregar", methods=["POST"])
def agregar():
    try:
        id_producto = int(request.form["id_producto"])
        cantidad = int(request.form["cantidad"])
    except ValueError:
        flash("Seleccione un producto e ingrese una cantidad válida.", "error")
        return redirect(url_for("cotizaciones.nueva"))

    if cantidad <= 0:
        flash("La cantidad debe ser mayor a cero.", "error")
        return redirect(url_for("cotizaciones.nueva"))

    producto = producto_model.obtener(id_producto)
    if producto is None or producto["estado"] != "A":
        flash("El producto no existe o está inactivo.", "error")
        return redirect(url_for("cotizaciones.nueva"))

    carrito = obtener_carrito()
    precio = producto["precio_venta"]

    encontrado = False
    for linea in carrito:
        if linea["id_producto"] == id_producto:
            linea["cantidad"] = linea["cantidad"] + cantidad
            linea["subtotal"] = linea["cantidad"] * precio
            encontrado = True

    if not encontrado:
        carrito.append({
            "id_producto": id_producto,
            "nombre": producto["nombre"],
            "cantidad": cantidad,
            "precio": precio,
            "subtotal": cantidad * precio
        })

    session.modified = True
    return redirect(url_for("cotizaciones.nueva"))


@cotizaciones_bp.route("/quitar/<int:indice>", methods=["POST"])
def quitar(indice):
    carrito = obtener_carrito()
    if 0 <= indice < len(carrito):
        carrito.pop(indice)
        session.modified = True
    return redirect(url_for("cotizaciones.nueva"))


@cotizaciones_bp.route("/cancelar", methods=["POST"])
def cancelar():
    session.pop("carrito_cotizacion", None)
    flash("Cotización cancelada.", "exito")
    return redirect(url_for("cotizaciones.lista"))


@cotizaciones_bp.route("/registrar", methods=["POST"])
def registrar():
    carrito = obtener_carrito()

    if len(carrito) == 0:
        flash("Agregue al menos un producto a la cotización.", "error")
        return redirect(url_for("cotizaciones.nueva"))

    id_cliente = request.form.get("id_cliente", "")
    if id_cliente == "":
        flash("Seleccione el cliente.", "error")
        return redirect(url_for("cotizaciones.nueva"))

    try:
        dias = int(request.form.get("dias_validez", "15"))
    except ValueError:
        dias = 0

    if dias <= 0 or dias > 90:
        flash("Los días de validez deben estar entre 1 y 90.", "error")
        return redirect(url_for("cotizaciones.nueva"))

    try:
        id_cotizacion = cotizacion_model.registrar(int(id_cliente), session["id_usuario"], dias, carrito)
        session.pop("carrito_cotizacion", None)
        flash("Cotización #" + str(id_cotizacion) + " registrada. El inventario no fue modificado.", "exito")
        return redirect(url_for("cotizaciones.detalle", id_cotizacion=id_cotizacion))
    except oracledb.DatabaseError as e:
        flash("La cotización NO se registró: " + obtener_mensaje_error(e), "error")
    except ValueError as e:
        flash("La cotización NO se registró: " + str(e), "error")

    return redirect(url_for("cotizaciones.nueva"))


@cotizaciones_bp.route("/detalle/<int:id_cotizacion>")
def detalle(id_cotizacion):
    cotizacion = cotizacion_model.obtener(id_cotizacion)
    if cotizacion is None:
        flash("La cotización no existe.", "error")
        return redirect(url_for("cotizaciones.lista"))

    lineas = cotizacion_model.obtener_detalle(id_cotizacion)
    return render_template("cotizaciones/detalle.html", cotizacion=cotizacion, lineas=lineas)


@cotizaciones_bp.route("/convertir/<int:id_cotizacion>", methods=["POST"])
def convertir(id_cotizacion):
    if not tiene_permiso("ventas"):
        flash("Su rol no puede registrar ventas.", "error")
        return redirect(url_for("cotizaciones.detalle", id_cotizacion=id_cotizacion))
    
    cotizacion_model.caducar_vencidas()

    cotizacion = cotizacion_model.obtener(id_cotizacion)
    if cotizacion is None:
        flash("La cotización no existe.", "error")
        return redirect(url_for("cotizaciones.lista"))

    if cotizacion["estado"] != "A":
        flash("Solo se pueden convertir cotizaciones abiertas.", "error")
        return redirect(url_for("cotizaciones.detalle", id_cotizacion=id_cotizacion))

    # Cargar los productos de la cotización en el carrito de venta, con el precio vigente
    carrito = []
    for linea in cotizacion_model.obtener_detalle(id_cotizacion):
        producto = producto_model.obtener(linea["id_producto"])
        precio = producto["precio_venta"]
        carrito.append({
            "id_producto": linea["id_producto"],
            "nombre": linea["nombre"],
            "cantidad": linea["cantidad"],
            "precio_venta": precio,
            "subtotal": round(linea["cantidad"] * precio, 2)
        })

    session["carrito_venta"] = carrito
    session["pagos_venta"] = []
    session["cotizacion_venta"] = {
        "id_cotizacion": id_cotizacion,
        "id_cliente": cotizacion["id_cliente"],
        "cliente": cotizacion["cliente"]
    }

    flash("Cotización #" + str(id_cotizacion) + " cargada. Registre los pagos para completar la venta.", "exito")
    return redirect(url_for("ventas.nueva"))