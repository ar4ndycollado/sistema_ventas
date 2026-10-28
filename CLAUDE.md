# Sistema de Ventas "TecnoMax" — Proyecto Final Base de Datos I

Contexto del proyecto para asistentes de IA y para el equipo. Mantener este archivo actualizado.

---

## 1. Contexto general

- **Curso:** Base de Datos I — Proyecto final individual (15 puntos).
- **Entrega:** sábado 31 de octubre de 2026.
- **Objetivo:** Sistema de Ventas con base de datos Oracle normalizada (3FN), íntegra y segura, más un prototipo web funcional conectado a Oracle.
- **Negocio ficticio:** TecnoMax, venta de equipo de cómputo y accesorios en Guatemala (moneda: quetzales, Q).
- **Idioma:** todo en español (código, comentarios, interfaz y documentación).

### Preferencias de trabajo (importante)

- Código **sencillo y fácil de explicar**: el estudiante debe defender cada línea.
- Usar ciclos **`for` para recorrer listas** (preferencia explícita).
- Arquitectura **MVC**: SQL solo en `models/`, lógica de petición en `controllers/`, HTML en `templates/`.
- Diseño **minimalista e intuitivo** (CSS propio, sin frameworks).
- Las reglas de negocio críticas se validan **en Oracle** (constraints y PL/SQL); Python valida antes para dar mensajes claros.
- Explicar los cambios paso a paso, archivo por archivo.

---

## 2. Tecnología

| Parte | Herramienta |
|---|---|
| Base de datos | Oracle Database 21c XE, PDB `xepdb1`, esquema **`SISTEMA_VENTAS`** |
| Lenguaje | Python 3.12 (entorno virtual `venv`) |
| Framework web | Flask (Blueprints) + plantillas Jinja2 |
| Conexión | `python-oracledb` (modo thin, sin cliente Oracle) |
| Contraseñas | `werkzeug.security` (hash scrypt) |
| Herramientas | VS Code, SQL Developer, SQL Developer Data Modeler |
| SO | Windows (desarrollo). Despliegue opcional en Ubuntu Server |

- Los laboratorios 1–3 se desarrollaron en el esquema `LABPRUEBA` (se conserva como respaldo).
- El proyecto final vive en `SISTEMA_VENTAS`, creado desde cero con `database/proyecto_sistema_ventas.sql`.

---

## 3. Estructura del proyecto

```
sistema_ventas/
├── app.py                    # inicio, registro de Blueprints, control de acceso (before_request)
├── config.py                 # conexión y datos del negocio (NO se sube a GitHub)
├── config.example.py         # plantilla de config.py sin contraseñas
├── requirements.txt
├── establecer_passwords.py   # asigna contraseñas cifradas a los usuarios de prueba
├── database/
│   ├── proyecto_sistema_ventas.sql   # script completo (estructura, PL/SQL, datos, pruebas)
│   └── diagramas/                    # ER, relacional y físico (Data Modeler)
├── controllers/
│   ├── seguridad.py          # PERMISOS por módulo, tiene_permiso(), tiene_rol()
│   ├── auth_controller.py    # login / logout
│   ├── inicio_controller.py
│   ├── clientes_controller.py
│   ├── proveedores_controller.py
│   ├── productos_controller.py
│   ├── compras_controller.py
│   ├── ventas_controller.py      # carrito, pagos, anulación con autorización, recibo
│   ├── cotizaciones_controller.py
│   ├── caja_controller.py        # apertura/cierre, historial, incidencias, vales, cajas
│   ├── kardex_controller.py
│   ├── reportes_controller.py
│   └── usuarios_controller.py
├── models/
│   ├── conexion.py           # obtener_conexion()
│   ├── errores.py            # obtener_mensaje_error(): traduce errores de Oracle
│   └── *_model.py            # un modelo por módulo
├── templates/                # base.html, login.html, inicio.html y una carpeta por módulo
└── static/css/estilos.css    # variables de color en :root
```

### Convenciones de código

- **Consultas:** siempre con variables de enlace (`:nombre`), nunca concatenando valores (evita inyección SQL).
- **Modelos:** `with obtener_conexion() as conexion:` y `with conexion.cursor() as cursor:`; devuelven listas de diccionarios armadas con `for`.
- **Transacciones de varios pasos** (compras, ventas, cotizaciones, usuarios): `try / except oracledb.DatabaseError / finally` con `conexion.commit()` y `conexion.rollback()` explícitos.
- **Procedimientos que forman parte de una transacción mayor NO hacen COMMIT** (`SP_AGREGAR_DETALLE_COMPRA`, `SP_CREAR_VENTA`, `SP_AGREGAR_DETALLE_VENTA`, `SP_AGREGAR_PAGO_VENTA`, `SP_FINALIZAR_VENTA`). La aplicación confirma o deshace todo.
- **Errores:** los controladores capturan `oracledb.DatabaseError` y muestran `obtener_mensaje_error(e)` con `flash(..., "error")`. Errores propios de PL/SQL: `RAISE_APPLICATION_ERROR(-20000 a -20999)`.
- **Parámetros OUT:** `var = cursor.var(int)` y `var.getvalue()`.
- **Carritos** (compras, ventas, cotizaciones) en `session`; después de modificarlos: `session.modified = True`.
- **Plantillas:** `{% extends "base.html" %}`, tablas con `{% for %} ... {% else %}` para el mensaje de lista vacía.
- **Auditoría de precios:** el modelo asigna `conexion.client_identifier = usuario` antes del UPDATE; el trigger lo lee con `SYS_CONTEXT('USERENV','CLIENT_IDENTIFIER')`.

### Nombres reales de columnas (evitar ORA-00904)

| Tabla / vista | Columna correcta | NO usar |
|---|---|---|
| `DETALLE_VENTA` | `precio_venta` | `precio_unitario` |
| `DETALLE_COTIZACION` | `precio` | `precio_unitario` |
| `DETALLE_COMPRA` | `precio_costo` | `precio_unitario` |
| `KARDEX` | `referencia`, `existencia_final` | `referencia_doc`, `stock_resultante` |
| `VW_PRODUCTOS_BAJO_STOCK` | `producto` (alias del nombre) | `nombre` |
| `VENTAS` | `estado`: A = Activa, N = Anulada | — |
| `COTIZACION` | `estado`: A = Abierta, C = Caducada, F = Facturada | — |
| `APERTURA_CAJA` | `estado`: A = Abierta, C = Cerrada | — |
| `VALE_DESCUENTO` | `estado`: P = Pendiente, A = Aplicado, N = Anulado | — |

> En Oracle **no se puede** mezclar funciones de agregación con subconsultas escalares en el mismo SELECT sin GROUP BY (ORA-00937). Usar agregación condicional: `SUM(CASE WHEN ... THEN ... END)`.

---

## 4. Usuarios y roles

### Usuarios de prueba de la aplicación

| Usuario | Rol | Notas |
|---|---|---|
| admin_marta | ADMINISTRADOR | Autoriza anulaciones; ve todo |
| cajero1 | CAJERO | Tiene una caja abierta en los datos de prueba |
| vendedor2 | VENDEDOR | Cotiza y vende; con incidencias en octubre |
| bodega_lab | BODEGUERO | Compras, productos, Kardex |
| usuario_inactivo | VENDEDOR | Inactivo: no puede iniciar sesión |

> Las contraseñas de prueba están en el encabezado del script SQL. No escribirlas en archivos que se suban al repositorio.

### Permisos por módulo (`controllers/seguridad.py`)

| Módulo | Roles |
|---|---|
| Clientes | ADMINISTRADOR, VENDEDOR, CAJERO |
| Proveedores | ADMINISTRADOR, BODEGUERO |
| Productos | ADMINISTRADOR, BODEGUERO, VENDEDOR (VENDEDOR solo consulta) |
| Compras | ADMINISTRADOR, BODEGUERO |
| Ventas | ADMINISTRADOR, VENDEDOR, CAJERO (anular requiere credenciales de un ADMINISTRADOR) |
| Cotizaciones | ADMINISTRADOR, VENDEDOR |
| Caja | ADMINISTRADOR, CAJERO, VENDEDOR (catálogo de cajas, incidencias y vales: solo ADMINISTRADOR) |
| Kardex | ADMINISTRADOR, BODEGUERO |
| Reportes | ADMINISTRADOR |
| Usuarios | ADMINISTRADOR |

### Seguridad en Oracle (Anexo A del script)

- Roles: `R_ADMINISTRADOR`, `R_VENDEDOR`, `R_CAJERO`, `R_BODEGUERO`, `R_CONSULTOR_PRODUCTO`.
- Usuarios de BD: `usr_consulta`, `usr_vendedor`, `usr_bodeguero`.
- Evidencia: `usr_vendedor` puede consultar `SISTEMA_VENTAS.CLIENTES`, pero `SISTEMA_VENTAS.USUARIO` da ORA-00942.

---

## 5. Objetos de la base de datos

### Tablas (20)

| Módulo | Tablas |
|---|---|
| Seguridad | `ROL`, `USUARIO`, `USUARIO_ROL` (asociativa M:N) |
| Personas | `CLIENTES`, `PROVEEDORES` |
| Inventario | `PRODUCTOS`, `KARDEX`, `AUDITORIA_PRODUCTO` |
| Compras | `COMPRAS`, `DETALLE_COMPRA` |
| Ventas | `VENTAS`, `DETALLE_VENTA`, `METODO_PAGO`, `PAGO_VENTA` |
| Cotizaciones | `COTIZACION`, `DETALLE_COTIZACION` |
| Caja | `CAJA`, `APERTURA_CAJA`, `VALE_DESCUENTO`, `POLITICA_SANCION` |

### Vistas (6)

| Vista | Uso |
|---|---|
| `VW_RESUMEN_VENTAS` | Lista de ventas (cliente, usuario, total, estado) |
| `VW_PRODUCTOS_BAJO_STOCK` | Filtro "Bajo stock" de productos |
| `VW_VENTAS_POR_PRODUCTO` | Top de productos vendidos (solo ventas activas) |
| `VW_INCIDENCIAS_CAJA` | Faltantes y sobrantes calculados desde los cierres |
| `VW_ANULACIONES_VENTA` | Ventas anuladas: vendió, solicitó y autorizó |
| `VW_SANCIONES_MES` | Incidencias por usuario y mes con sanción sugerida |

### Funciones (2)

- `FN_STOCK_PRODUCTO(id_producto)` — existencia actual (se usa en la lista de productos).
- `FN_EFECTIVO_APERTURA(id_apertura)` — efectivo de las ventas activas de una apertura.

### Procedimientos (15)

| Procedimiento | COMMIT propio | Propósito |
|---|---|---|
| `SP_REGISTRAR_CLIENTE` | Sí | Registro de clientes (Lab 3) |
| `SP_REGISTRAR_DETALLE_COMPRA` | Sí | Compra de un producto (Lab 3) |
| `SP_REGISTRAR_DETALLE_VENTA` | Sí | Venta de un producto (Lab 3) |
| `SP_VENTA_TRANSACCION` | Sí | Demostración de COMMIT/ROLLBACK (Lab 3) |
| `SP_PROCESAR_VENTA` | Sí | Proceso integrador de un producto (Lab 3) |
| `SP_AGREGAR_DETALLE_COMPRA` | No | Detalle de compra + stock + ENTRADA en Kardex |
| `SP_CREAR_VENTA` | No | Encabezado; valida cliente, usuario, caja y cotización (OUT id_venta) |
| `SP_AGREGAR_DETALLE_VENTA` | No | Detalle + stock + SALIDA en Kardex (precio del catálogo) |
| `SP_AGREGAR_PAGO_VENTA` | No | Pago (efectivo, tarjeta, transferencia) |
| `SP_FINALIZAR_VENTA` | No | Valida pagos = total y actualiza la caja |
| `SP_ANULAR_VENTA` | Sí | Anulación autorizada por ADMINISTRADOR; cursor que devuelve stock |
| `SP_CADUCAR_COTIZACIONES` | Sí | Marca cotizaciones vencidas |
| `SP_ABRIR_CAJA` | Sí | Apertura (OUT id_apertura) |
| `SP_CERRAR_CAJA` | Sí | Cierre; calcula esperado y diferencia |
| `SP_APLICAR_VALES_MES` | Sí | Proceso de fin de mes (OUT cantidad) |

### Triggers (2)

- `TRG_AUDITORIA_PRECIO` — registra cada cambio de `precio_venta` en `AUDITORIA_PRODUCTO`.
- `TRG_VALE_FALTANTE` — al cerrar una caja con faltante, genera el vale de descuento.

### Otros

- **Job:** `JOB_CADUCAR_COTIZACIONES` (`DBMS_SCHEDULER`, diario a las 00:05).
- **Índices:** 23 índices en llaves foráneas, incluidos los compuestos `KARDEX(id_producto, fecha)` y `APERTURA_CAJA(id_usuario, estado)`.
- **Secuencias:** una por tabla con ID generado (`SEQ_*`).
- **Respaldo:** Data Pump (`expdp` / `impdp`) con el directorio `DIR_RESPALDOS` (Anexo B del script).

---

## 6. Lista de cotejo y estado

Leyenda: ✅ listo · ⏳ pendiente

### I. Análisis de requerimientos — 1.50 pts

| # | Criterio | Valor | Estado | Evidencia |
|---|---|---|---|---|
| 1 | Descripción clara del problema | 0.25 | ⏳ | Documento, sección 1.1 (borrador en la sección 7 de este archivo) |
| 2 | Objetivo general y alcance | 0.25 | ⏳ | Documento, secciones 1.2 y 1.3 |
| 3 | Actores o usuarios | 0.25 | ⏳ | Documento, sección 1.4 |
| 4 | Requerimientos funcionales | 0.25 | ⏳ | Documento, sección 1.5 |
| 5 | Reglas del negocio | 0.25 | ⏳ | Documento, sección 1.7 |
| 6 | Requerimientos corresponden con lo implementado | 0.25 | ⏳ | Tabla RF → objeto/pantalla |

### II. Diseño de la base de datos — 2.50 pts

| # | Criterio | Valor | Estado | Evidencia |
|---|---|---|---|---|
| 7 | Diagrama Entidad–Relación | 0.25 | ⏳ | Data Modeler, modelo lógico |
| 8 | Entidades y atributos según requerimientos | 0.25 | ⏳ | Diagrama ER |
| 9 | Relaciones y cardinalidades correctas | 0.25 | ⏳ | Diagrama ER (notación pata de gallo) |
| 10 | M:N resueltas con entidades asociativas | 0.25 | ⏳ | `USUARIO_ROL`; detalles de compra, venta y cotización |
| 11 | Modelo relacional con PK y FK | 0.25 | ⏳ | Data Modeler, modelo relacional |
| 12 | Modelo físico con tipos y restricciones | 0.25 | ⏳ | Relacional con tipos + DDL |
| 13 | Normalización hasta 3FN | 0.50 | ⏳ | Evidencia 1FN → 2FN → 3FN (cambio no guardado, incidencias como vista, catálogos) |
| 14 | Integridad referencial y coherencia modelo–BD | 0.50 | ⏳ | Diagramas generados desde la BD real |

### III. Implementación en Oracle — 2.00 pts

| # | Criterio | Valor | Estado | Evidencia |
|---|---|---|---|---|
| 15 | Estructura completa y funcional | 0.25 | ✅ | Script ejecuta sin errores en esquema vacío |
| 16 | PK, FK, NOT NULL, UNIQUE y CHECK | 0.25 | ✅ | Sección 3 del script (incluye CHECK de varias columnas) |
| 17 | Clientes, proveedores y productos | 0.25 | ✅ | Tablas + módulos de la app |
| 18 | Compras maestro–detalle | 0.25 | ✅ | `COMPRAS` / `DETALLE_COMPRA` |
| 19 | Ventas maestro–detalle | 0.25 | ✅ | `VENTAS` / `DETALLE_VENTA` / `PAGO_VENTA` |
| 20 | Caja con aperturas y cierres | 0.25 | ✅ | `CAJA` / `APERTURA_CAJA` + procedimientos |
| 21 | Cotizaciones con detalle | 0.25 | ✅ | `COTIZACION` / `DETALLE_COTIZACION` |
| 22 | Kardex con entradas y salidas | 0.25 | ✅ | `KARDEX` + módulo Kardex |

### IV. SQL y explotación de la información — 1.50 pts

| # | Criterio | Valor | Estado | Evidencia |
|---|---|---|---|---|
| 23 | INSERT, UPDATE, DELETE y SELECT | 0.25 | ✅ | Modelos de la app y script |
| 24 | JOIN entre varias tablas | 0.25 | ✅ | Kardex, reportes, vistas |
| 25 | SUM, COUNT, AVG, MAX, MIN | 0.25 | ✅ | Reportes (resumen de ventas), caja |
| 26 | GROUP BY y HAVING | 0.25 | ✅ | Reporte "Mejores clientes", `VW_SANCIONES_MES` |
| 27 | Subconsulta | 0.25 | ✅ | Productos nunca vendidos, `VW_SANCIONES_MES` |
| 28 | Vistas útiles | 0.25 | ✅ | 6 vistas |

### V. Seguridad y PL/SQL — 2.00 pts

| # | Criterio | Valor | Estado | Evidencia |
|---|---|---|---|---|
| 29 | Usuarios, roles y privilegios | 0.25 | ✅ | Anexo A + tablas `USUARIO`/`ROL`/`USUARIO_ROL` |
| 30 | Seguridad acorde al rol | 0.25 | ✅ | `PERMISOS` en la app + GRANT en Oracle |
| 31 | Procedimiento almacenado útil | 0.25 | ✅ | 15 procedimientos |
| 32 | Función PL/SQL y su uso | 0.25 | ✅ | `FN_STOCK_PRODUCTO`, `FN_EFECTIVO_APERTURA` |
| 33 | Trigger de negocio o auditoría | 0.25 | ✅ | `TRG_AUDITORIA_PRECIO`, `TRG_VALE_FALTANTE` |
| 34 | Excepciones en PL/SQL | 0.25 | ✅ | `NO_DATA_FOUND`, `RAISE_APPLICATION_ERROR` |
| 35 | COMMIT y ROLLBACK | 0.25 | ✅ | Ventas, compras y anulaciones atómicas |
| 36 | Reglas que evitan inconsistencias | 0.25 | ✅ | Consultas 11.2–11.5 del script (todo OK) |

### VI. Prototipo funcional — 3.00 pts

| # | Criterio | Valor | Estado | Evidencia |
|---|---|---|---|---|
| 37 | Conexión con Oracle | 0.25 | ✅ | `models/conexion.py` |
| 38 | Inicio de sesión | 0.25 | ✅ | Login con hash y usuarios activos |
| 39 | Gestión de clientes y proveedores | 0.25 | ✅ | Módulos CRUD |
| 40 | Productos y existencias | 0.25 | ✅ | Módulo Productos + auditoría |
| 41 | Compras con varios productos | 0.25 | ✅ | Carrito de compras |
| 42 | Ventas con varios productos | 0.25 | ✅ | Carrito + pagos combinados |
| 43 | Ventas actualizan existencias y Kardex | 0.50 | ✅ | `SP_AGREGAR_DETALLE_VENTA` |
| 44 | Compras actualizan existencias y Kardex | 0.25 | ✅ | `SP_AGREGAR_DETALLE_COMPRA` |
| 45 | Cotizaciones sin afectar inventario | 0.25 | ✅ | Módulo Cotizaciones + conversión a venta |
| 46 | Apertura y cierre de caja | 0.25 | ✅ | Módulo Caja |
| 47 | Reportes útiles | 0.25 | ✅ | Reportes, Incidencias, Vales, recibo |

### VII. Pruebas y validación — 1.00 pt

| # | Criterio | Valor | Estado | Evidencia |
|---|---|---|---|---|
| 48 | Datos de prueba suficientes | 0.25 | ✅ | Sección 10 del script (agosto–octubre) |
| 49 | Valida datos obligatorios | 0.25 | ✅ | Validaciones en Python y Oracle |
| 50 | Restricciones mantienen la integridad | 0.25 | ✅ | Pruebas 12.9–12.13 |
| 51 | Escenario de error con datos consistentes | 0.25 | ✅ | Prueba 12.1 (ROLLBACK) y conflicto de stock en la app |

### VIII. Documentación y defensa — 1.50 pts

| # | Criterio | Valor | Estado | Evidencia |
|---|---|---|---|---|
| 52 | Documentación y modelos actualizados | 0.25 | ⏳ | Documento del proyecto |
| 53 | Script SQL completo y ejecutable | 0.25 | ✅ | `database/proyecto_sistema_ventas.sql` |
| 54 | Demostración de la aplicación | 0.25 | ⏳ | Ensayo de defensa |
| 55 | Explica relaciones, PK, FK y normalización | 0.25 | ⏳ | Preparar con los diagramas |
| 56 | Explica consultas y objetos SQL/PL-SQL | 0.25 | ⏳ | Preparar con el script |
| 57 | Resuelve una modificación en la defensa | 0.25 | ⏳ | Practicar cambios rápidos |

### Productos a entregar

1. Documento del proyecto (análisis, requerimientos, reglas, modelos) — ⏳
2. Diagrama Entidad–Relación — ⏳
3. Modelo Relacional — ⏳
4. Modelo Físico — ⏳
5. Evidencia de normalización hasta 3FN — ⏳
6. Script SQL completo — ✅
7. Código fuente de la aplicación — ✅
8. Base de datos con datos de prueba — ✅
9. Prototipo funcional conectado a Oracle — ✅
10. Presentación y defensa individual — ⏳

---

## 7. Análisis de requerimientos (borrador del documento)

### 7.1 Descripción del problema

TecnoMax registra compras, ventas e inventario en hojas de cálculo y documentos separados. Esto provoca: inventario descuadrado; ventas de productos sin existencia; falta de trazabilidad sobre quién y cuándo cambió existencias o precios; cotizaciones confundidas con ventas; ausencia de control formal de caja (faltantes y sobrantes sin responsable); anulaciones sin autorización ni registro; y acceso sin control a la información.

### 7.2 Objetivos

**General:** Desarrollar un Sistema de Ventas con una base de datos Oracle normalizada e íntegra que permita registrar compras, ventas, cotizaciones, pagos y movimientos de caja, mantener el inventario actualizado y trazable, y controlar el acceso según el rol de cada usuario.

**Específicos:**
1. Diseñar una base de datos relacional normalizada hasta 3FN con integridad referencial.
2. Automatizar en Oracle (procedimientos, funciones, triggers y jobs) la actualización del inventario, el Kardex y la caja.
3. Garantizar con transacciones que ninguna operación quede registrada parcialmente.
4. Controlar la caja con aperturas, cierres, faltantes, sobrantes, vales y sanciones sugeridas.
5. Implementar seguridad por roles en Oracle y en la aplicación.
6. Desarrollar un prototipo web conectado a Oracle con reportes para la toma de decisiones.

### 7.3 Alcance

**Incluye:** inicio de sesión y usuarios con roles; clientes, proveedores y productos; compras y ventas con varios productos; pagos en efectivo, tarjeta, transferencia y combinados; anulación de ventas con autorización; recibo imprimible; cotizaciones con vigencia y conversión a venta; Kardex; apertura y cierre de caja; faltantes, sobrantes, vales y sanciones sugeridas; auditoría de precios; reportes; tarea programada; índices y respaldos.

**No incluye (mejoras futuras):** facturación electrónica FEL (SAT); notas de crédito para ventas de cajas cerradas; devoluciones parciales; créditos y cuentas por cobrar; contabilidad; varias sucursales o bodegas; login con reconocimiento facial.

### 7.4 Actores

| Actor | Tipo | Responsabilidades |
|---|---|---|
| Administrador | Interno | Usuarios, cajas, precios, autorización de anulaciones, reportes, incidencias y vales |
| Vendedor | Interno | Clientes, cotizaciones, ventas y su caja |
| Cajero | Interno | Apertura y cierre de caja, ventas, solicitud de anulaciones |
| Bodeguero | Interno | Proveedores, productos, compras y Kardex |
| Consultor de productos | Interno (solo BD) | Consulta del catálogo de productos |
| Cliente | Externo | Solicita cotizaciones y compra; no usa el sistema |
| Proveedor | Externo | Abastece productos; no usa el sistema |

### 7.5 Requerimientos funcionales

| ID | Requerimiento | Implementación |
|---|---|---|
| RF-01 | Iniciar sesión validando contraseña y usuario activo | Login (`USUARIO`, `USUARIO_ROL`) |
| RF-02 | Mostrar solo los módulos permitidos por el rol | `PERMISOS` / `before_request` |
| RF-03 | Crear, modificar, activar y desactivar usuarios con uno o varios roles | Módulo Usuarios |
| RF-04 | Gestionar clientes | `SP_REGISTRAR_CLIENTE` + módulo Clientes |
| RF-05 | Gestionar proveedores | Módulo Proveedores |
| RF-06 | Registrar, modificar, activar y desactivar productos | Módulo Productos |
| RF-07 | Consultar existencias e identificar bajo stock | `FN_STOCK_PRODUCTO`, `VW_PRODUCTOS_BAJO_STOCK` |
| RF-08 | Auditar automáticamente los cambios de precio | `TRG_AUDITORIA_PRECIO` |
| RF-09 | Registrar compras con varios productos (stock + Kardex) | `SP_AGREGAR_DETALLE_COMPRA` |
| RF-10 | Registrar ventas con varios productos validando cliente, usuario, caja, producto y stock | `SP_CREAR_VENTA`, `SP_AGREGAR_DETALLE_VENTA` |
| RF-11 | Registrar uno o varios pagos por venta, con cálculo de cambio | `SP_AGREGAR_PAGO_VENTA`, `SP_FINALIZAR_VENTA` |
| RF-12 | Imprimir o guardar en PDF el comprobante de venta | Recibo (`/ventas/recibo`) |
| RF-13 | Anular ventas con autorización de un administrador, devolviendo el stock | `SP_ANULAR_VENTA` |
| RF-14 | Elaborar cotizaciones con vencimiento sin afectar el inventario | Módulo Cotizaciones |
| RF-15 | Caducar automáticamente las cotizaciones vencidas | `SP_CADUCAR_COTIZACIONES` + `JOB_CADUCAR_COTIZACIONES` |
| RF-16 | Convertir una cotización abierta en venta | Carga del carrito + `SP_CREAR_VENTA` |
| RF-17 | Abrir y cerrar caja con monto esperado y diferencia | `SP_ABRIR_CAJA`, `SP_CERRAR_CAJA` |
| RF-18 | Generar vales de descuento por faltantes | `TRG_VALE_FALTANTE` |
| RF-19 | Consultar incidencias, aplicar o anular vales y ver sanciones sugeridas | `VW_INCIDENCIAS_CAJA`, `SP_APLICAR_VALES_MES`, `VW_SANCIONES_MES` |
| RF-20 | Consultar el Kardex por producto y tipo de movimiento | Módulo Kardex |
| RF-21 | Generar reportes de ventas, inventario, clientes, usuarios y métodos de pago | Módulo Reportes y vistas |
| RF-22 | Respaldar y restaurar la base de datos | Data Pump (Anexo B) |

### 7.6 Requerimientos no funcionales

| ID | Requerimiento |
|---|---|
| RNF-01 | Seguridad: contraseñas con hash; acceso por roles en Oracle y en la aplicación |
| RNF-02 | Integridad: compras, ventas, pagos y anulaciones son transacciones atómicas |
| RNF-03 | Consistencia: reglas críticas validadas en la BD (constraints y PL/SQL) |
| RNF-04 | Usabilidad: interfaz web minimalista y mensajes de error comprensibles |
| RNF-05 | Rendimiento: índices en llaves foráneas y consultas frecuentes |
| RNF-06 | Disponibilidad: respaldos con Data Pump |
| RNF-07 | Portabilidad: ejecución local y despliegue posible en Ubuntu Server |
| RNF-08 | Mantenibilidad: patrón Modelo–Vista–Controlador |

### 7.7 Reglas del negocio

| ID | Regla | Dónde se garantiza |
|---|---|---|
| RN-01 | Un usuario inactivo no inicia sesión, no abre caja ni vende | Login, `SP_ABRIR_CAJA`, `SP_CREAR_VENTA` |
| RN-02 | Un usuario puede tener varios roles | `USUARIO_ROL` |
| RN-03 | No se repiten usuario, correo de cliente ni NIT de proveedor | `UNIQUE` |
| RN-04 | El stock nunca es negativo | `CHECK (stock >= 0)` + validación en PL/SQL |
| RN-05 | El stock solo cambia por compras, ventas y anulaciones | Procedimientos |
| RN-06 | Todo movimiento de inventario queda en el Kardex | Procedimientos |
| RN-07 | Precio de venta ≥ precio de compra | `CHECK` |
| RN-08 | Productos y usuarios con historial se desactivan, no se eliminan | `estado` + FK |
| RN-09 | Un producto inactivo no se compra ni se vende | Procedimientos |
| RN-10 | Para vender se necesita una caja abierta; toda venta pertenece a una apertura | `SP_CREAR_VENTA`, `id_apertura NOT NULL` |
| RN-11 | El precio de venta lo toma el sistema del catálogo | `SP_AGREGAR_DETALLE_VENTA` |
| RN-12 | La suma de los pagos debe ser igual al total de la venta | `SP_FINALIZAR_VENTA` |
| RN-13 | Tarjeta y transferencia requieren referencia; solo el efectivo registra monto recibido | `SP_AGREGAR_PAGO_VENTA` + `CHECK` |
| RN-14 | Solo el efectivo de ventas activas suma al monto esperado de la caja | `FN_EFECTIVO_APERTURA` |
| RN-15 | Una cotización no modifica el inventario | Módulo Cotizaciones |
| RN-16 | Una cotización vencida pasa a Caducada; solo una abierta se factura, una sola vez | `SP_CADUCAR_COTIZACIONES`, `UNIQUE (id_cotizacion)` |
| RN-17 | Un usuario solo tiene una caja abierta; una caja solo la abre un usuario | `SP_ABRIR_CAJA` |
| RN-18 | Solo quien abrió la caja puede cerrarla | `SP_CERRAR_CAJA` |
| RN-19 | Diferencia = contado − esperado | `SP_CERRAR_CAJA` |
| RN-20 | Un faltante genera vale; un sobrante solo es incidencia | `TRG_VALE_FALTANTE`, `VW_INCIDENCIAS_CAJA` |
| RN-21 | Vale aplicado requiere fecha; vale anulado requiere motivo | `CHECK` de dos columnas |
| RN-22 | Solo se anula una venta si su caja sigue abierta, con motivo y autorización de un administrador | `SP_ANULAR_VENTA` |
| RN-23 | Una venta anulada conserva fecha, solicitante, autorizador y motivo | `CHECK chk_ventas_anulacion` |
| RN-24 | La sanción se sugiere según faltantes no justificados + anulaciones del mes; decide el administrador | `POLITICA_SANCION`, `VW_SANCIONES_MES` |
| RN-25 | Todo cambio de precio queda auditado | `TRG_AUDITORIA_PRECIO` |
| RN-26 | No se elimina un cliente o proveedor con operaciones | Llaves foráneas |

---

## 8. Pendientes (plan hasta la entrega)

- [ ] Importar `SISTEMA_VENTAS` en Data Modeler y generar: ER (lógico), relacional y físico; exportar a PDF/PNG en `database/diagramas/`.
- [ ] Redactar la evidencia de normalización (1FN → 2FN → 3FN).
- [ ] Armar el documento del proyecto (secciones: análisis, diseño, implementación, seguridad, prototipo, pruebas, instalación, conclusiones).
- [ ] Ensayar la defensa (registrar compra, vender, venta sin stock, Kardex, crear usuario, vista, procedimiento, excepción, trigger, ROLLBACK).
- [ ] (Opcional) Despliegue en Ubuntu Server.

## 9. Cómo ejecutar

1. Crear `config.py` a partir de `config.example.py` con los datos de conexión.
2. `python -m venv venv` → `.\venv\Scripts\Activate.ps1` → `pip install -r requirements.txt`.
3. Base de datos: seguir el orden del Anexo A del script (SYSDBA → script con `SISTEMA_VENTAS` → GRANT).
4. `python app.py` y abrir `http://127.0.0.1:5000`.
