# Sistema de Ventas — Eden Store

Proyecto final del curso **Base de Datos I**. Sistema de ventas para una tienda de equipo de cómputo y accesorios en Guatemala, con base de datos **Oracle 21c XE** y un prototipo web en **Python + Flask**.

## Módulos

| Módulo | Qué permite |
|---|---|
| Inicio de sesión | Entrar con usuario y contraseña; cada rol ve solo sus módulos |
| Clientes y proveedores | Registrar, modificar y eliminar (si no tienen operaciones) |
| Productos | Registrar, modificar precios (con auditoría), activar y desactivar |
| Compras | Compras con varios productos; suben el stock y registran ENTRADA en el Kardex |
| Ventas | Ventas con varios productos y pagos combinados; bajan el stock, registran SALIDA en el Kardex y actualizan la caja; recibo imprimible; anulación con autorización de un administrador |
| Cotizaciones | Cotizaciones con vigencia que no afectan el inventario y se pueden convertir en venta |
| Caja | Apertura y cierre con monto esperado y diferencia; faltantes generan vales de descuento |
| Kardex | Movimientos de inventario por producto |
| Reportes | Ventas, productos, clientes, usuarios y métodos de pago |
| Usuarios | Crear usuarios con uno o varios roles, activar y desactivar |

## Usuarios y roles

| Rol | Puede usar |
|---|---|
| ADMINISTRADOR | Todo el sistema; autoriza anulaciones |
| VENDEDOR | Clientes, cotizaciones, ventas, su caja y consulta de productos |
| CAJERO | Clientes, ventas y su caja |
| BODEGUERO | Proveedores, productos, compras y Kardex |

Las contraseñas de los usuarios de prueba están en el encabezado de `database/proyecto_sistema_ventas.sql`.

## Requisitos

- Oracle Database 21c XE (PDB `xepdb1`)
- Python 3.12
- SQL Developer (para ejecutar el script)

## Instalación

### 1. Base de datos

1. Como **SYSDBA** en `XEPDB1`, crear el usuario `SISTEMA_VENTAS` y los roles (sección 1 y 2 del **Anexo A** del script).
2. Conectado como **SISTEMA_VENTAS**, abrir `database/proyecto_sistema_ventas.sql` en SQL Developer y ejecutarlo con **F5**. Crea las tablas, objetos PL/SQL y datos de prueba.
3. Como **SYSDBA**, ejecutar los GRANT y usuarios de base de datos (secciones 3 a 5 del **Anexo A**).

### 2. Aplicación

```powershell
python -m venv venv
.\venv\Scripts\Activate.ps1
pip install -r requirements.txt
copy config.example.py config.py
```

Editar `config.py` con la contraseña de Oracle y una clave secreta. Después:

```powershell
python app.py
```

Abrir <http://127.0.0.1:5000> e iniciar sesión, por ejemplo con `admin_marta`.

> Si las contraseñas de la aplicación no funcionan, escribir las del script en `PASSWORDS_PRUEBA` de `config.py` y ejecutar `python establecer_passwords.py`.

## Estructura

```
app.py                 inicio de la aplicación y control de acceso
config.example.py      plantilla de configuración (config.py no se sube)
establecer_passwords.py
database/              script SQL completo
database/diagramas/    diagramas ER (notación de Chen), modelo relacional y modelo físico
docs/                  documento del proyecto y capturas de la aplicación
controllers/           lógica de cada pantalla (Flask Blueprints)
models/                consultas a Oracle
templates/             páginas HTML (Jinja2)
static/css/            estilos
```

La aplicación sigue el patrón **Modelo–Vista–Controlador**: el SQL está solo en `models/`, la lógica de cada petición en `controllers/` y el HTML en `templates/`. Las reglas de negocio críticas (stock, caja, pagos, anulaciones) se validan en Oracle con restricciones y procedimientos almacenados.

## Documentación

- `docs/Documento_Proyecto_Eden_Store.docx`: análisis de requerimientos, diseño, normalización hasta 3FN, implementación, pruebas y diccionario de datos.
- `database/diagramas/`: diagrama Entidad–Relación (general y por módulo), modelo relacional y modelo físico con su DDL.

## Respaldo

Respaldo y restauración con Data Pump (`expdp` / `impdp`): ver el **Anexo B** del script.
