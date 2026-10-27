# controllers/kardex_controller.py
# CONTROLADOR: consulta del Kardex

from flask import Blueprint, render_template, request
from models import kardex_model, producto_model

kardex_bp = Blueprint("kardex", __name__, url_prefix="/kardex")


@kardex_bp.route("/")
def lista():
    # Leer los filtros de la URL (?id_producto=1&tipo=ENTRADA)
    id_producto_texto = request.args.get("id_producto", "")
    tipo = request.args.get("tipo", "")

    id_producto = None
    if id_producto_texto.isdigit():
        id_producto = int(id_producto_texto)

    if tipo not in ["ENTRADA", "SALIDA"]:
        tipo = None

    movimientos = kardex_model.listar(id_producto, tipo)

    resumen_producto = None
    if id_producto is not None:
        resumen_producto = kardex_model.resumen_producto(id_producto)
        # Para un solo producto, el Kardex se lee en orden cronológico (del más antiguo al más reciente)
        movimientos.reverse()

    return render_template(
        "kardex/lista.html",
        movimientos=movimientos,
        productos=producto_model.listar(),
        resumen=kardex_model.resumen_por_tipo(),
        resumen_producto=resumen_producto,
        id_producto=id_producto,
        tipo=tipo
    )