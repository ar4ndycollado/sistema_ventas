# controllers/ventas_controller.py
# CONTROLADOR: ventas con varios productos y varios métodos de pago.
# Flujo de una venta:
#   1) Se agregan productos al carrito y pagos a la lista (ambos en la sesión).
#   2) Al presionar "Registrar", venta_model.registrar() guarda todo en Oracle
#      en una sola transacción (encabezado, detalles, pagos, stock, Kardex y caja).
#   3) Si algo falla en Oracle (por ejemplo, stock insuficiente), se hace
#      ROLLBACK y no queda nada a medias; el carrito se conserva para corregir.
# También incluye el detalle, el recibo y la anulación con autorización.

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
    """Productos de la venta en curso (se crea vacío la primera vez)."""
    if "carrito_venta" not in session:
        session["carrito_venta"] = []
    return session["carrito_venta"]


def obtener_pagos():
    """Pagos agregados a la venta en curso (se crea vacía la primera vez)."""
    if "pagos_venta" not in session:
        session["pagos_venta"] = []
    return session["pagos_venta"]


def calcular_total(carrito):
    """Suma de los subtotales. round(…, 2) evita decimales raros de float (ej. 674.9999)."""
    total = 0
    for linea in carrito:
        total = total + linea["subtotal"]
    return round(total, 2)


def calcular_pagado(pagos):
    """Suma de los montos de todos los pagos agregados."""
    pagado = 0
    for pago in pagos:
        pagado = pagado + pago["monto"]
    return round(pagado, 2)


def limpiar_venta():
    """Borra de la sesión todo lo de la venta en curso (al registrar o cancelar)."""
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
        # Si el usuario no tiene caja abierta, la pantalla avisa que no puede vender
        apertura=caja_model.obtener_apertura_activa(session["id_usuario"]),
        # Si la venta viene de una cotización, aquí están sus datos (si no, None)
        cotizacion=session.get("cotizacion_venta")
    )


# ===== Productos =====

@ventas_bp.route("/agregar", methods=["POST"])
def agregar():
    """Agrega un producto al carrito revisando el stock disponible."""
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

    # La cantidad a revisar es lo que ya había en el carrito + lo nuevo
    cantidad_total = cantidad
    if linea_existente is not None:
        cantidad_total = linea_existente["cantidad"] + cantidad

    # Primera revisión de stock, solo para avisar pronto al usuario.
    # La revisión definitiva la hace SP_AGREGAR_DETALLE_VENTA al registrar,
    # porque otro cajero pudo vender el mismo producto mientras tanto.
    if cantidad_total > producto["stock"]:
        flash("Stock insuficiente de " + producto["nombre"] + ". Disponible: " +
            str(producto["stock"]) + ", solicitado: " + str(cantidad_total) + ".", "error")
        return redirect(url_for("ventas.nueva"))

    # El precio sale del catálogo; el usuario no puede escribirlo (RN-11)
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

    # Se modificó una lista DENTRO de la sesión: hay que avisarle a Flask
    # para que guarde el cambio en la cookie
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
    """Agrega un pago. Una venta puede pagarse con varios (ej. tarjeta + efectivo)."""
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

    # Saldo pendiente = total de la venta - lo que ya se pagó
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

    # Reglas por método de pago (RN-13):
    # - Efectivo: sin referencia; puede registrar cuánto entregó el cliente para dar cambio.
    # - Tarjeta y transferencia: exigen número de autorización o referencia.
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
            # Ej.: paga Q300 en efectivo, entrega Q500 → cambio Q200
            cambio = round(monto_recibido - monto, 2)

    elif metodo["requiere_referencia"] and referencia == "":
        flash("El pago con " + metodo["nombre"] + " requiere el número de autorización o referencia.", "error")
        return redirect(url_for("ventas.nueva"))

    pagos.append({
        "id_metodo": id_metodo,
        "metodo": metodo["nombre"],
        "monto": monto,
        "referencia": referencia if referencia != "" else None,   # vacío → NULL en Oracle
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

    # Los pagos deben sumar exactamente el total (RN-12).
    # Oracle lo vuelve a comprobar en SP_FINALIZAR_VENTA.
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
        # El modelo ya hizo ROLLBACK; el carrito sigue en la sesión para corregir.
        # Ej.: "Stock insuficiente de Proyector Full HD. Disponible: 2" (ORA-20004)
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

# ===== Anulación con autorización de administrador =====
# Un cajero o vendedor puede solicitar la anulación, pero necesita que un
# ADMINISTRADOR escriba su usuario y contraseña en el formulario (RN-22).

def validar_autorizador():
    """Si el usuario conectado es ADMINISTRADOR, se autoriza a sí mismo.
    Si no, verifica el usuario y la contraseña del administrador escritos en el formulario.
    Devuelve el id del autorizador, o None si la autorización no es válida."""

    if tiene_rol(["ADMINISTRADOR"]):
        return session["id_usuario"]

    # Las mismas revisiones del login: existe, está activo, contraseña correcta y es ADMINISTRADOR
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
        # Se guarda quién solicitó (usuario conectado) y quién autorizó (administrador).
        # Oracle rechaza la anulación si la caja de esa venta ya se cerró (RN-22).
        venta_model.anular(id_venta, session["id_usuario"], id_autoriza, motivo)
        flash("Venta #" + str(id_venta) + " anulada. Se devolvió el stock y se ajustó la caja.", "exito")
    except oracledb.DatabaseError as e:
        flash("No se pudo anular: " + obtener_mensaje_error(e), "error")

    return redirect(url_for("ventas.detalle", id_venta=id_venta))


@ventas_bp.route("/recibo/<int:id_venta>")
def recibo(id_venta):
    """Comprobante imprimible (el navegador permite imprimirlo o guardarlo en PDF).
    Los datos del negocio (nombre, NIT, dirección) vienen de config.NEGOCIO."""
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