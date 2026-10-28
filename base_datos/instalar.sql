-- Crea todo el esquema del sistema de ventas en orden.
-- Uso (conectado como el usuario dueño del esquema, desde esta carpeta):
--   SQL> @instalar.sql

@@01_secuencias.sql
@@02_tablas.sql
@@03_indices.sql
@@04_llaves_foraneas.sql
@@05_funciones.sql
@@06_vistas.sql
@@07_procedimientos.sql
@@08_triggers.sql
@@09_jobs.sql
@@10_datos_iniciales.sql

-- Después, asignar las contraseñas desde la carpeta del proyecto:
--   python establecer_passwords.py
