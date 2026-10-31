# controllers/compras_controller.py
# CONTROLADOR: compras con varios productos (carrito).
# Flujo: 1) se agregan productos al carrito (guardado en la sesión, aún no en Oracle);
#        2) al presionar "Registrar", compra_model.registrar() guarda todo
#           en una sola transacción: encabezado + detalles + stock + Kardex.

from flask import Blueprint, render_template, request, redirect, url_for, flash, session
import oracledb
from models import compra_model, producto_model, proveedor_model
from models.errores import obtener_mensaje_error

compras_bp = Blueprint("compras", __name__, url_prefix="/compras")


def obtener_carrito():
    """Devuelve la lista de productos del carrito guardada en la sesión.
    Cada usuario tiene su propio carrito porque cada uno tiene su propia sesión."""
    # La primera vez el carrito no existe: se crea vacío
    if "carrito_compra" not in session:
        session["carrito_compra"] = []
    return session["carrito_compra"]


def calcular_total(carrito):
    """Suma los subtotales de las líneas del carrito (solo para mostrarlo en pantalla;
    el total oficial lo calcula Oracle al registrar)."""
    total = 0
    for linea in carrito:
        total = total + linea["subtotal"]
    return total


@compras_bp.route("/")
def lista():
    compras = compra_model.listar()
    return render_template("compras/lista.html", compras=compras)


@compras_bp.route("/nueva")
def nueva():
    # Pantalla de la compra en proceso: carrito actual + listas para elegir
    carrito = obtener_carrito()
    return render_template(
        "compras/nueva.html",
        carrito=carrito,
        total=calcular_total(carrito),
        productos=producto_model.listar_activos(),
        proveedores=proveedor_model.listar()
    )


@compras_bp.route("/agregar", methods=["POST"])
def agregar():
    """Agrega un producto al carrito. Todavía no se guarda nada en Oracle."""
    # int()/float() fallan con ValueError si el campo está vacío o no es número
    try:
        id_producto = int(request.form["id_producto"])
        cantidad = int(request.form["cantidad"])
        precio_costo = float(request.form["precio_costo"])
    except ValueError:
        flash("Seleccione un producto e ingrese cantidad y precio válidos.", "error")
        return redirect(url_for("compras.nueva"))

    if cantidad <= 0 or precio_costo <= 0:
        flash("La cantidad y el precio de costo deben ser mayores a cero.", "error")
        return redirect(url_for("compras.nueva"))

    producto = producto_model.obtener(id_producto)
    if producto is None or producto["estado"] != "A":
        flash("El producto no existe o está inactivo.", "error")
        return redirect(url_for("compras.nueva"))

    carrito = obtener_carrito()

    # Si el producto ya está en el carrito, solo se suma la cantidad
    # (y se usa el último precio de costo escrito)
    encontrado = False
    for linea in carrito:
        if linea["id_producto"] == id_producto:
            linea["cantidad"] = linea["cantidad"] + cantidad
            linea["precio_costo"] = precio_costo
            linea["subtotal"] = linea["cantidad"] * precio_costo
            encontrado = True

    if not encontrado:
        carrito.append({
            "id_producto": id_producto,
            "nombre": producto["nombre"],
            "cantidad": cantidad,
            "precio_costo": precio_costo,
            "subtotal": cantidad * precio_costo
        })

    session.modified = True   # avisar a Flask que la sesión cambió
    return redirect(url_for("compras.nueva"))


@compras_bp.route("/quitar/<int:indice>", methods=["POST"])
def quitar(indice):
    # indice = posición de la línea en el carrito (0 = primera)
    carrito = obtener_carrito()
    if 0 <= indice < len(carrito):
        carrito.pop(indice)
        session.modified = True
    return redirect(url_for("compras.nueva"))


@compras_bp.route("/cancelar", methods=["POST"])
def cancelar():
    # Basta con borrar el carrito de la sesión: en Oracle no se había guardado nada
    session.pop("carrito_compra", None)
    flash("Compra cancelada.", "exito")
    return redirect(url_for("compras.lista"))


@compras_bp.route("/registrar", methods=["POST"])
def registrar():
    carrito = obtener_carrito()

    if len(carrito) == 0:
        flash("Agregue al menos un producto a la compra.", "error")
        return redirect(url_for("compras.nueva"))

    id_proveedor = request.form.get("id_proveedor", "")
    if id_proveedor == "":
        flash("Seleccione el proveedor.", "error")
        return redirect(url_for("compras.nueva"))

    try:
        # Se guarda todo junto; la compra queda a nombre del usuario conectado
        id_compra = compra_model.registrar(int(id_proveedor), session["id_usuario"], carrito)
        # Compra guardada: se vacía el carrito
        session.pop("carrito_compra", None)
        flash("Compra #" + str(id_compra) + " registrada. Se actualizó el stock y el Kardex.", "exito")
        return redirect(url_for("compras.detalle", id_compra=id_compra))
    except oracledb.DatabaseError as e:
        # El carrito se conserva para que el usuario pueda corregir
        flash("La compra NO se registró: " + obtener_mensaje_error(e), "error")
        return redirect(url_for("compras.nueva"))


@compras_bp.route("/detalle/<int:id_compra>")
def detalle(id_compra):
    compra = compra_model.obtener(id_compra)
    if compra is None:
        flash("La compra no existe.", "error")
        return redirect(url_for("compras.lista"))

    lineas = compra_model.obtener_detalle(id_compra)
    return render_template("compras/detalle.html", compra=compra, lineas=lineas)