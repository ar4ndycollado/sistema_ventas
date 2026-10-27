# controllers/reportes_controller.py
# CONTROLADOR: reportes del sistema

from flask import Blueprint, render_template, request
from models import reporte_model

reportes_bp = Blueprint("reportes", __name__, url_prefix="/reportes")


def agregar_porcentajes(lista, campo):
    """Calcula el ancho de las barras: el valor más alto ocupa el 100%."""
    maximo = 0
    for elemento in lista:
        if elemento[campo] > maximo:
            maximo = elemento[campo]

    for elemento in lista:
        if maximo > 0:
            elemento["porcentaje"] = round(elemento[campo] * 100 / maximo)
        else:
            elemento["porcentaje"] = 0


@reportes_bp.route("/")
def inicio():
    # Monto mínimo para el reporte con HAVING (por defecto Q500)
    try:
        monto_minimo = float(request.args.get("monto_minimo", "500"))
    except ValueError:
        monto_minimo = 500

    mas_vendidos = reporte_model.productos_mas_vendidos()
    agregar_porcentajes(mas_vendidos, "unidades")

    por_mes = reporte_model.ventas_por_mes()
    agregar_porcentajes(por_mes, "total")

    return render_template(
        "reportes/inicio.html",
        indicadores=reporte_model.indicadores_ventas(),
        inventario=reporte_model.valor_inventario(),
        por_cliente=reporte_model.ventas_por_cliente(monto_minimo),
        monto_minimo=monto_minimo,
        mas_vendidos=mas_vendidos,
        sin_ventas=reporte_model.productos_sin_ventas(),
        por_usuario=reporte_model.ventas_por_usuario(),
        por_mes=por_mes
    )