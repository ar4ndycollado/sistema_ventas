-- Datos iniciales (catálogos) necesarios para que el sistema funcione
-- Generado desde el esquema SISTEMA_VENTAS (Oracle 21c XE)
-- Las contraseñas quedan como 'PENDIENTE': ejecute establecer_passwords.py después.

SET DEFINE OFF

-- ROL (4 registros)
INSERT INTO ROL (id_rol, nombre_rol, descripcion) VALUES (1, 'ADMINISTRADOR', 'Acceso total al sistema');
INSERT INTO ROL (id_rol, nombre_rol, descripcion) VALUES (2, 'VENDEDOR', 'Gestión de ventas y cotizaciones');
INSERT INTO ROL (id_rol, nombre_rol, descripcion) VALUES (3, 'CAJERO', 'Manejo de caja y cobros');
INSERT INTO ROL (id_rol, nombre_rol, descripcion) VALUES (4, 'BODEGUERO', 'Gestión de inventario y compras');

-- METODO_PAGO (3 registros)
INSERT INTO METODO_PAGO (id_metodo, nombre, afecta_caja, requiere_referencia, estado) VALUES (1, 'Efectivo', 'S', 'N', 'A');
INSERT INTO METODO_PAGO (id_metodo, nombre, afecta_caja, requiere_referencia, estado) VALUES (2, 'Tarjeta', 'N', 'S', 'A');
INSERT INTO METODO_PAGO (id_metodo, nombre, afecta_caja, requiere_referencia, estado) VALUES (3, 'Transferencia', 'N', 'S', 'A');

-- CAJA (3 registros)
INSERT INTO CAJA (id_caja, nombre, estado) VALUES (1, 'Caja 1 - Principal', 'A');
INSERT INTO CAJA (id_caja, nombre, estado) VALUES (2, 'Caja 2 - Mostrador', 'A');
INSERT INTO CAJA (id_caja, nombre, estado) VALUES (3, 'Caja 3 - Bodega', 'I');

-- POLITICA_SANCION (3 registros)
INSERT INTO POLITICA_SANCION (id_politica, minimo_incidencias, sancion) VALUES (1, 2, 'Llamada de atención verbal');
INSERT INTO POLITICA_SANCION (id_politica, minimo_incidencias, sancion) VALUES (2, 3, 'Amonestación por escrito');
INSERT INTO POLITICA_SANCION (id_politica, minimo_incidencias, sancion) VALUES (3, 5, 'Suspensión y revisión por gerencia');

-- USUARIO (5 registros)
INSERT INTO USUARIO (id_usuario, usuario, password, estado) VALUES (1, 'admin_marta', 'PENDIENTE', 'A');
INSERT INTO USUARIO (id_usuario, usuario, password, estado) VALUES (2, 'cajero1', 'PENDIENTE', 'A');
INSERT INTO USUARIO (id_usuario, usuario, password, estado) VALUES (3, 'vendedor2', 'PENDIENTE', 'A');
INSERT INTO USUARIO (id_usuario, usuario, password, estado) VALUES (4, 'bodega_lab', 'PENDIENTE', 'A');
INSERT INTO USUARIO (id_usuario, usuario, password, estado) VALUES (5, 'usuario_inactivo', 'PENDIENTE', 'I');

-- USUARIO_ROL (5 registros)
INSERT INTO USUARIO_ROL (id_usuario, id_rol) VALUES (1, 1);
INSERT INTO USUARIO_ROL (id_usuario, id_rol) VALUES (2, 3);
INSERT INTO USUARIO_ROL (id_usuario, id_rol) VALUES (3, 2);
INSERT INTO USUARIO_ROL (id_usuario, id_rol) VALUES (4, 4);
INSERT INTO USUARIO_ROL (id_usuario, id_rol) VALUES (5, 2);

COMMIT;
