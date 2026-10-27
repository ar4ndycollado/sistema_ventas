# controllers/caja_controller.py
# CONTROLADOR: apertura, cierre e historial de caja

from flask import Blueprint, render_template, request, redirect, url_for, flash, session
import oracledb
from models import caja_model
from models.errores import obtener_mensaje_error
from controllers.seguridad import tiene_rol
from datetime import datetime

caja_bp = Blueprint("caja", __name__, url_prefix="/caja")


def leer_monto(nombre_campo):
    """Convierte a número el monto del formulario. Devuelve None si no es válido."""
    try:
        monto = float(request.form[nombre_campo])
        if monto < 0:
            return None
        return monto
    except ValueError:
        return None


@caja_bp.route("/")
def mi_caja():
    apertura = caja_model.obtener_apertura_activa(session["id_usuario"])

    # Sin caja abierta: mostrar el formulario de apertura
    if apertura is None:
        return render_template("caja/abrir.html", cajas=caja_model.cajas_disponibles())

    # Con caja abierta: mostrar el resumen y el formulario de cierre
    resumen = caja_model.resumen_apertura(apertura["id_apertura"])
    ventas = caja_model.ventas_de_apertura(apertura["id_apertura"])
    return render_template("caja/mi_caja.html", resumen=resumen, ventas=ventas)


@caja_bp.route("/abrir", methods=["POST"])
def abrir():
    id_caja = request.form.get("id_caja", "")
    monto_inicial = leer_monto("monto_inicial")

    if id_caja == "":
        flash("Seleccione una caja.", "error")
        return redirect(url_for("caja.mi_caja"))

    if monto_inicial is None:
        flash("Ingrese un monto inicial válido (cero o mayor).", "error")
        return redirect(url_for("caja.mi_caja"))

    try:
        id_apertura = caja_model.abrir(int(id_caja), session["id_usuario"], monto_inicial)
        flash("Caja abierta correctamente (apertura #" + str(id_apertura) + ").", "exito")
    except oracledb.DatabaseError as e:
        flash(obtener_mensaje_error(e), "error")

    return redirect(url_for("caja.mi_caja"))


@caja_bp.route("/cerrar", methods=["POST"])
def cerrar():
    apertura = caja_model.obtener_apertura_activa(session["id_usuario"])
    if apertura is None:
        flash("No tiene una caja abierta.", "error")
        return redirect(url_for("caja.mi_caja"))

    monto_contado = leer_monto("monto_contado")
    if monto_contado is None:
        flash("Ingrese un monto contado válido (cero o mayor).", "error")
        return redirect(url_for("caja.mi_caja"))

    observacion = request.form.get("observacion", "").strip()
    if observacion == "":
        observacion = None

    try:
        caja_model.cerrar(apertura["id_apertura"], session["id_usuario"], monto_contado, observacion)
        flash("Caja cerrada correctamente.", "exito")
        return redirect(url_for("caja.cierre", id_apertura=apertura["id_apertura"]))
    except oracledb.DatabaseError as e:
        flash(obtener_mensaje_error(e), "error")
        return redirect(url_for("caja.mi_caja"))


@caja_bp.route("/cierre/<int:id_apertura>")
def cierre(id_apertura):
    resumen = caja_model.resumen_apertura(id_apertura)

    if resumen is None:
        flash("La apertura no existe.", "error")
        return redirect(url_for("caja.historial"))

    # Solo el dueño de la apertura o un administrador pueden verla
    if resumen["id_usuario"] != session["id_usuario"] and not tiene_rol(["ADMINISTRADOR"]):
        flash("No puede ver aperturas de otros usuarios.", "error")
        return redirect(url_for("caja.historial"))

    ventas = caja_model.ventas_de_apertura(id_apertura)
    return render_template("caja/cierre.html", resumen=resumen, ventas=ventas)


@caja_bp.route("/historial")
def historial():
    if tiene_rol(["ADMINISTRADOR"]):
        aperturas = caja_model.historial()                       # todas
    else:
        aperturas = caja_model.historial(session["id_usuario"])  # solo las propias
    return render_template("caja/historial.html", aperturas=aperturas)


# ===== Catálogo de cajas (solo ADMINISTRADOR) =====

@caja_bp.route("/cajas")
def cajas():
    if not tiene_rol(["ADMINISTRADOR"]):
        flash("Solo el administrador puede gestionar las cajas.", "error")
        return redirect(url_for("caja.mi_caja"))
    return render_template("caja/cajas.html", cajas=caja_model.listar_cajas())


@caja_bp.route("/cajas/nueva", methods=["POST"])
def nueva_caja():
    if not tiene_rol(["ADMINISTRADOR"]):
        return redirect(url_for("caja.mi_caja"))

    nombre = request.form["nombre"].strip()
    if nombre == "":
        flash("El nombre de la caja es obligatorio.", "error")
        return redirect(url_for("caja.cajas"))

    try:
        caja_model.registrar_caja(nombre)
        flash("Caja registrada correctamente.", "exito")
    except oracledb.DatabaseError as e:
        flash(obtener_mensaje_error(e), "error")

    return redirect(url_for("caja.cajas"))


@caja_bp.route("/cajas/estado/<int:id_caja>", methods=["POST"])
def estado_caja(id_caja):
    if not tiene_rol(["ADMINISTRADOR"]):
        return redirect(url_for("caja.mi_caja"))

    caja_actual = None
    for caja in caja_model.listar_cajas():
        if caja["id_caja"] == id_caja:
            caja_actual = caja

    if caja_actual is None:
        flash("La caja no existe.", "error")
        return redirect(url_for("caja.cajas"))

    if caja_actual["en_uso_por"] is not None:
        flash("No se puede desactivar una caja que está abierta.", "error")
        return redirect(url_for("caja.cajas"))

    nuevo_estado = "I" if caja_actual["estado"] == "A" else "A"

    try:
        caja_model.cambiar_estado_caja(id_caja, nuevo_estado)
        flash("Estado de la caja actualizado.", "exito")
    except oracledb.DatabaseError as e:
        flash(obtener_mensaje_error(e), "error")

    return redirect(url_for("caja.cajas"))

# ===== Incidencias y vales (solo ADMINISTRADOR) =====

# Cantidad de faltantes en un mes a partir de la cual se sugiere revisar al usuario
FALTANTES_PARA_REVISION = 3


def mes_seleccionado():
    """Mes de la URL (?mes=2026-10) o el mes actual."""
    mes = request.args.get("mes", "")
    if len(mes) != 7:
        mes = datetime.now().strftime("%Y-%m")
    return mes


@caja_bp.route("/incidencias")
def incidencias():
    if not tiene_rol(["ADMINISTRADOR"]):
        flash("Solo el administrador puede ver las incidencias.", "error")
        return redirect(url_for("caja.mi_caja"))

    mes = mes_seleccionado()
    return render_template(
        "caja/incidencias.html",
        mes=mes,
        incidencias=caja_model.listar_incidencias(mes),
        resumen=caja_model.resumen_incidencias(mes),
        umbral=FALTANTES_PARA_REVISION
    )


@caja_bp.route("/vales")
def vales():
    if not tiene_rol(["ADMINISTRADOR"]):
        flash("Solo el administrador puede gestionar los vales.", "error")
        return redirect(url_for("caja.mi_caja"))

    estado = request.args.get("estado", "P")
    if estado not in ["P", "A", "N"]:
        estado = None   # todos

    return render_template(
        "caja/vales.html",
        vales=caja_model.listar_vales(estado),
        pendientes=caja_model.pendientes_por_usuario(),
        estado=estado,
        mes_actual=datetime.now().strftime("%Y-%m")
    )


@caja_bp.route("/vales/aplicar", methods=["POST"])
def aplicar_vales():
    if not tiene_rol(["ADMINISTRADOR"]):
        return redirect(url_for("caja.mi_caja"))

    mes = request.form.get("mes", "")
    try:
        cantidad = caja_model.aplicar_vales_mes(mes)
        if cantidad == 0:
            flash("No hay vales pendientes en " + mes + ".", "error")
        else:
            flash(str(cantidad) + " vale(s) de " + mes + " aplicados como descuento.", "exito")
    except oracledb.DatabaseError as e:
        flash(obtener_mensaje_error(e), "error")

    return redirect(url_for("caja.vales"))


@caja_bp.route("/vales/anular/<int:id_vale>", methods=["POST"])
def anular_vale(id_vale):
    if not tiene_rol(["ADMINISTRADOR"]):
        return redirect(url_for("caja.mi_caja"))

    motivo = request.form.get("motivo", "").strip()
    if motivo == "":
        flash("Indique el motivo de la anulación.", "error")
        return redirect(url_for("caja.vales"))

    try:
        if caja_model.anular_vale(id_vale, motivo):
            flash("Vale #" + str(id_vale) + " anulado.", "exito")
        else:
            flash("Solo se pueden anular vales pendientes.", "error")
    except oracledb.DatabaseError as e:
        flash(obtener_mensaje_error(e), "error")

    return redirect(url_for("caja.vales"))