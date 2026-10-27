# controllers/ventas_controller.py
# CONTROLADOR: ventas con varios productos y varios métodos de pago

from flask import Blueprint, render_template, request, redirect, url_for, flash, session
import oracledb
from models import venta_model, producto_model, cliente_model, caja_model
from models.errores import obtener_mensaje_error
import config
from controllers.seguridad import tiene_rol
from werkzeug.security import check_password_hash
from models import usuario_model

ventas_bp = Blueprint("ventas", __name__, url_prefix="/ventas")


# ===== Datos de la venta en curso (guardados en la sesión) =====

def obtener_carrito():
    if "carrito_venta" not in session:
        session["carrito_venta"] = []
    return session["carrito_venta"]


def obtener_pagos():
    if "pagos_venta" not in session:
        session["pagos_venta"] = []
    return session["pagos_venta"]


def calcular_total(carrito):
    total = 0
    for linea in carrito:
        total = total + linea["subtotal"]
    return round(total, 2)


def calcular_pagado(pagos):
    pagado = 0
    for pago in pagos:
        pagado = pagado + pago["monto"]
    return round(pagado, 2)


def limpiar_venta():
    session.pop("carrito_venta", None)
    session.pop("pagos_venta", None)
    session.pop("cotizacion_venta", None)


# ===== Lista y pantalla de venta =====

@ventas_bp.route("/")
def lista():
    ventas = venta_model.listar()
    return render_template("ventas/lista.html", ventas=ventas)


@ventas_bp.route("/nueva")
def nueva():
    carrito = obtener_carrito()
    pagos = obtener_pagos()
    total = calcular_total(carrito)
    pagado = calcular_pagado(pagos)

    return render_template(
        "ventas/nueva.html",
        carrito=carrito,
        pagos=pagos,
        total=total,
        pagado=pagado,
        pendiente=round(total - pagado, 2),
        productos=producto_model.listar_activos(),
        clientes=cliente_model.listar(),
        metodos=venta_model.listar_metodos_pago(),
        apertura=caja_model.obtener_apertura_activa(session["id_usuario"]),
        cotizacion=session.get("cotizacion_venta")
    )


# ===== Productos =====

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

    linea_existente = None
    for linea in carrito:
        if linea["id_producto"] == id_producto:
            linea_existente = linea

    cantidad_total = cantidad
    if linea_existente is not None:
        cantidad_total = linea_existente["cantidad"] + cantidad

    if cantidad_total > producto["stock"]:
        flash("Stock insuficiente de " + producto["nombre"] + ". Disponible: " +
            str(producto["stock"]) + ", solicitado: " + str(cantidad_total) + ".", "error")
        return redirect(url_for("ventas.nueva"))

    precio = producto["precio_venta"]

    if linea_existente is not None:
        linea_existente["cantidad"] = cantidad_total
        linea_existente["subtotal"] = round(cantidad_total * precio, 2)
    else:
        carrito.append({
            "id_producto": id_producto,
            "nombre": producto["nombre"],
            "cantidad": cantidad,
            "precio_venta": precio,
            "subtotal": round(cantidad * precio, 2)
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


# ===== Pagos =====

@ventas_bp.route("/agregar-pago", methods=["POST"])
def agregar_pago():
    try:
        id_metodo = int(request.form["id_metodo"])
        monto = round(float(request.form["monto"]), 2)
    except ValueError:
        flash("Seleccione el método de pago e ingrese un monto válido.", "error")
        return redirect(url_for("ventas.nueva"))

    # Buscar el método elegido en el catálogo
    metodo = None
    for opcion in venta_model.listar_metodos_pago():
        if opcion["id_metodo"] == id_metodo:
            metodo = opcion

    if metodo is None:
        flash("El método de pago no es válido.", "error")
        return redirect(url_for("ventas.nueva"))

    pagos = obtener_pagos()
    pendiente = round(calcular_total(obtener_carrito()) - calcular_pagado(pagos), 2)

    if monto <= 0:
        flash("El monto del pago debe ser mayor a cero.", "error")
        return redirect(url_for("ventas.nueva"))

    if monto > pendiente:
        flash("El pago (Q" + "%.2f" % monto + ") supera el saldo pendiente (Q" + "%.2f" % pendiente + ").", "error")
        return redirect(url_for("ventas.nueva"))

    referencia = request.form.get("referencia", "").strip()
    monto_recibido = None
    cambio = None

    if metodo["es_efectivo"]:
        referencia = ""   # el efectivo no lleva referencia
        recibido_texto = request.form.get("monto_recibido", "").strip()
        if recibido_texto != "":
            try:
                monto_recibido = round(float(recibido_texto), 2)
            except ValueError:
                flash("El efectivo recibido no es un número válido.", "error")
                return redirect(url_for("ventas.nueva"))
            if monto_recibido < monto:
                flash("El efectivo recibido no cubre el monto del pago.", "error")
                return redirect(url_for("ventas.nueva"))
            cambio = round(monto_recibido - monto, 2)

    elif metodo["requiere_referencia"] and referencia == "":
        flash("El pago con " + metodo["nombre"] + " requiere el número de autorización o referencia.", "error")
        return redirect(url_for("ventas.nueva"))

    pagos.append({
        "id_metodo": id_metodo,
        "metodo": metodo["nombre"],
        "monto": monto,
        "referencia": referencia if referencia != "" else None,
        "monto_recibido": monto_recibido,
        "cambio": cambio
    })
    session.modified = True
    return redirect(url_for("ventas.nueva"))


@ventas_bp.route("/quitar-pago/<int:indice>", methods=["POST"])
def quitar_pago(indice):
    pagos = obtener_pagos()
    if 0 <= indice < len(pagos):
        pagos.pop(indice)
        session.modified = True
    return redirect(url_for("ventas.nueva"))


# ===== Cancelar y registrar =====

@ventas_bp.route("/cancelar", methods=["POST"])
def cancelar():
    limpiar_venta()
    flash("Venta cancelada.", "exito")
    return redirect(url_for("ventas.lista"))


@ventas_bp.route("/registrar", methods=["POST"])
def registrar():
    carrito = obtener_carrito()
    pagos = obtener_pagos()
    cotizacion = session.get("cotizacion_venta")

    if len(carrito) == 0:
        flash("Agregue al menos un producto a la venta.", "error")
        return redirect(url_for("ventas.nueva"))

    # Si la venta viene de una cotización, el cliente es el de la cotización
    if cotizacion is not None:
        id_cliente = cotizacion["id_cliente"]
        id_cotizacion = cotizacion["id_cotizacion"]
    else:
        id_cliente_texto = request.form.get("id_cliente", "")
        if id_cliente_texto == "":
            flash("Seleccione el cliente.", "error")
            return redirect(url_for("ventas.nueva"))
        id_cliente = int(id_cliente_texto)
        id_cotizacion = None

    total = calcular_total(carrito)
    pagado = calcular_pagado(pagos)

    if len(pagos) == 0 or pagado != total:
        flash("Los pagos (Q" + "%.2f" % pagado + ") deben cubrir exactamente el total (Q" + "%.2f" % total + ").", "error")
        return redirect(url_for("ventas.nueva"))

    try:
        id_venta = venta_model.registrar(id_cliente, session["id_usuario"], carrito, pagos, id_cotizacion)
        limpiar_venta()
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

    return render_template(
        "ventas/detalle.html",
        venta=venta,
        lineas=venta_model.obtener_detalle(id_venta),
        pagos=venta_model.obtener_pagos(id_venta)
    )

# ===== Anulación y recibo =====

# ===== Anulación con autorización de administrador =====

def validar_autorizador():
    """Si el usuario conectado es ADMINISTRADOR, se autoriza a sí mismo.
    Si no, verifica el usuario y la contraseña del administrador escritos en el formulario.
    Devuelve el id del autorizador, o None si la autorización no es válida."""

    if tiene_rol(["ADMINISTRADOR"]):
        return session["id_usuario"]

    nombre = request.form.get("autoriza_usuario", "").strip()
    password = request.form.get("autoriza_password", "")

    if nombre == "" or password == "":
        return None

    autorizador = usuario_model.buscar_usuario(nombre)
    if autorizador is None or autorizador["estado"] != "A":
        return None

    if not check_password_hash(autorizador["password"], password):
        return None

    if "ADMINISTRADOR" not in usuario_model.obtener_roles(autorizador["id_usuario"]):
        return None

    return autorizador["id_usuario"]


@ventas_bp.route("/anular/<int:id_venta>", methods=["POST"])
def anular(id_venta):
    motivo = request.form.get("motivo", "").strip()
    if len(motivo) < 5:
        flash("Indique el motivo de la anulación (mínimo 5 caracteres).", "error")
        return redirect(url_for("ventas.detalle", id_venta=id_venta))

    id_autoriza = validar_autorizador()
    if id_autoriza is None:
        # Mensaje genérico: no revela si falló el usuario, la contraseña o el rol
        flash("Autorización rechazada: credenciales de administrador no válidas.", "error")
        return redirect(url_for("ventas.detalle", id_venta=id_venta))

    try:
        venta_model.anular(id_venta, session["id_usuario"], id_autoriza, motivo)
        flash("Venta #" + str(id_venta) + " anulada. Se devolvió el stock y se ajustó la caja.", "exito")
    except oracledb.DatabaseError as e:
        flash("No se pudo anular: " + obtener_mensaje_error(e), "error")

    return redirect(url_for("ventas.detalle", id_venta=id_venta))


@ventas_bp.route("/recibo/<int:id_venta>")
def recibo(id_venta):
    venta = venta_model.obtener(id_venta)
    if venta is None:
        flash("La venta no existe.", "error")
        return redirect(url_for("ventas.lista"))

    return render_template(
        "ventas/recibo.html",
        venta=venta,
        lineas=venta_model.obtener_detalle(id_venta),
        pagos=venta_model.obtener_pagos(id_venta),
        negocio=config.NEGOCIO
    )