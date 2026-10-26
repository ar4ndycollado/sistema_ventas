# controllers/ventas_controller.py
# CONTROLADOR: ventas con varios productos (carrito)

from flask import Blueprint, render_template, request, redirect, url_for, flash, session
import oracledb
from models import venta_model, producto_model, cliente_model, caja_model
from models.errores import obtener_mensaje_error

ventas_bp = Blueprint("ventas", __name__, url_prefix="/ventas")


def obtener_carrito():
    if "carrito_venta" not in session:
        session["carrito_venta"] = []
    return session["carrito_venta"]


def calcular_total(carrito):
    total = 0
    for linea in carrito:
        total = total + linea["subtotal"]
    return total


@ventas_bp.route("/")
def lista():
    ventas = venta_model.listar()
    return render_template("ventas/lista.html", ventas=ventas)


@ventas_bp.route("/nueva")
def nueva():
    carrito = obtener_carrito()
    return render_template(
        "ventas/nueva.html",
        carrito=carrito,
        total=calcular_total(carrito),
        productos=producto_model.listar_activos(),
        clientes=cliente_model.listar(),
        apertura=caja_model.obtener_apertura_activa(session["id_usuario"])
    )


@ventas_bp.route("/agregar", methods=["POST"])
def agregar():
    try:
        id_producto = int(request.form["id_producto"])
        cantidad = int(request.form["cantidad"])
    except ValueError:
        flash("Seleccione un producto e ingrese una cantidad válida.", "error")
        return redirect(url_for("ventas.nueva"))

    if cantidad <= 0:
        flash("La cantidad debe ser mayor a cero.", "error")
        return redirect(url_for("ventas.nueva"))

    producto = producto_model.obtener(id_producto)
    if producto is None or producto["estado"] != "A":
        flash("El producto no existe o está inactivo.", "error")
        return redirect(url_for("ventas.nueva"))

    carrito = obtener_carrito()

    # Buscar si el producto ya está en el carrito
    linea_existente = None
    for linea in carrito:
        if linea["id_producto"] == id_producto:
            linea_existente = linea

    cantidad_total = cantidad
    if linea_existente is not None:
        cantidad_total = linea_existente["cantidad"] + cantidad

    # Primera revisión de stock (Oracle vuelve a validarlo al registrar)
    if cantidad_total > producto["stock"]:
        flash("Stock insuficiente de " + producto["nombre"] + ". Disponible: " +
            str(producto["stock"]) + ", solicitado: " + str(cantidad_total) + ".", "error")
        return redirect(url_for("ventas.nueva"))

    precio = producto["precio_venta"]

    if linea_existente is not None:
        linea_existente["cantidad"] = cantidad_total
        linea_existente["subtotal"] = cantidad_total * precio
    else:
        carrito.append({
            "id_producto": id_producto,
            "nombre": producto["nombre"],
            "cantidad": cantidad,
            "precio_venta": precio,
            "subtotal": cantidad * precio
        })

    session.modified = True
    return redirect(url_for("ventas.nueva"))


@ventas_bp.route("/quitar/<int:indice>", methods=["POST"])
def quitar(indice):
    carrito = obtener_carrito()
    if 0 <= indice < len(carrito):
        carrito.pop(indice)
        session.modified = True
    return redirect(url_for("ventas.nueva"))


@ventas_bp.route("/cancelar", methods=["POST"])
def cancelar():
    session.pop("carrito_venta", None)
    flash("Venta cancelada.", "exito")
    return redirect(url_for("ventas.lista"))


@ventas_bp.route("/registrar", methods=["POST"])
def registrar():
    carrito = obtener_carrito()

    if len(carrito) == 0:
        flash("Agregue al menos un producto a la venta.", "error")
        return redirect(url_for("ventas.nueva"))

    id_cliente = request.form.get("id_cliente", "")
    if id_cliente == "":
        flash("Seleccione el cliente.", "error")
        return redirect(url_for("ventas.nueva"))

    try:
        id_venta = venta_model.registrar(int(id_cliente), session["id_usuario"], carrito)
        session.pop("carrito_venta", None)
        flash("Venta #" + str(id_venta) + " registrada. Se actualizó el stock, el Kardex y la caja.", "exito")
        return redirect(url_for("ventas.detalle", id_venta=id_venta))
    except oracledb.DatabaseError as e:
        flash("La venta NO se registró: " + obtener_mensaje_error(e), "error")
        return redirect(url_for("ventas.nueva"))


@ventas_bp.route("/detalle/<int:id_venta>")
def detalle(id_venta):
    venta = venta_model.obtener(id_venta)
    if venta is None:
        flash("La venta no existe.", "error")
        return redirect(url_for("ventas.lista"))

    lineas = venta_model.obtener_detalle(id_venta)
    return render_template("ventas/detalle.html", venta=venta, lineas=lineas)