-- ============================================================================
-- init.sql
-- Esquema inicial de la base de datos de NEGOCIO para el bot de WhatsApp.
--
-- Este script lo ejecuta automáticamente el contenedor oficial de Postgres
-- (imagen postgres:16-alpine) SOLO la primera vez que se crea el volumen
-- "postgres_data", porque está montado en /docker-entrypoint-initdb.d/.
-- Si ya existe el volumen, este archivo NO se vuelve a correr. Para forzar
-- que se re-ejecute (por ejemplo si lo modificás), hay que borrar el volumen
-- (ver instrucciones en README.md).
--
-- Incluye datos de ejemplo (seed) para poder probar el flujo del bot sin
-- tener todavía el catálogo real de Farmalife/Ysdin.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Tabla: proveedores
-- Representa cada marca/proveedor (ej: "Farmalife", "Ysdin") a la que se le
-- pueden pedir productos. Un comprador queda asignado a una sola marca.
-- ----------------------------------------------------------------------------
CREATE TABLE proveedores (
    id              SERIAL PRIMARY KEY,
    nombre_marca    VARCHAR(100) NOT NULL UNIQUE, -- Nombre de la marca/proveedor, ej: 'Farmalife', 'Ysdin'
    activo          BOOLEAN NOT NULL DEFAULT TRUE, -- Si está en FALSE, el bot no debe permitir pedidos a esta marca
    creado_en       TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ----------------------------------------------------------------------------
-- Tabla: farmacias_autorizadas
-- Whitelist de números de WhatsApp que tienen permiso para hacer pedidos
-- a través del bot. Cualquier mensaje entrante de un número que no esté acá
-- (o que esté con activo = FALSE) debería ser rechazado/ignorado por el flow.
-- ----------------------------------------------------------------------------
CREATE TABLE farmacias_autorizadas (
    id                  SERIAL PRIMARY KEY,
    numero_whatsapp     VARCHAR(20) NOT NULL UNIQUE, -- Número en formato internacional sin '+', ej: '5491122334455'
    nombre_farmacia     VARCHAR(150) NOT NULL,        -- Razón social o nombre de fantasía de la farmacia
    direccion           VARCHAR(200),                 -- Dirección de la farmacia (opcional, útil para logística)
    activo              BOOLEAN NOT NULL DEFAULT TRUE, -- Permite dar de baja sin borrar el historial
    creado_en           TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ----------------------------------------------------------------------------
-- Tabla: productos
-- Catálogo de productos con stock y precio para que el bot pueda responder
-- disponibilidad y armar el pedido.
--
-- IMPORTANTE: esta tabla la reemplaza COMPLETA (TRUNCATE + INSERT) el script
-- ConsultasOracle\sync_stock.py en cada corrida, con la foto que trae de
-- Oracle (consultas_sql\stock_sync.sql). Los alias del SELECT de Oracle
-- tienen que coincidir con estos nombres de columna. Los seeds de abajo solo
-- sirven para probar el bot antes de la primera sincronización.
-- marca_proveedor es texto (el nombre del laboratorio tal como viene de
-- Oracle); para derivar pedidos se matchea contra proveedores.nombre_marca.
-- ----------------------------------------------------------------------------
CREATE TABLE productos (
    id                  SERIAL PRIMARY KEY,
    codigo_barra        VARCHAR(20),                  -- Código de barras (EAN), viene de Oracle CODIGO_BARRA
    codigo_farmacia     VARCHAR(20),                  -- Código interno propio, viene de Oracle COD_FARMACIA
    nombre              VARCHAR(200) NOT NULL,        -- Nombre comercial del producto
    marca_proveedor     VARCHAR(150),                 -- Marca/laboratorio en texto (Oracle l.DESCRIPCION)
    stock               INTEGER DEFAULT 0,            -- Unidades disponibles (puede venir NULL de Oracle)
    precio              NUMERIC(14, 2),               -- Precio en ARS (NULL en ~75% del catálogo; hay medicamentos de alto costo que superan los $100M)
    unidad_medida       VARCHAR(20) NOT NULL DEFAULT 'unidad', -- ej: 'unidad', 'caja x10', 'blister'
    activo              BOOLEAN NOT NULL DEFAULT TRUE, -- Permite discontinuar un producto sin borrarlo
    creado_en           TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ----------------------------------------------------------------------------
-- Tabla: compradores
-- Personas que gestionan los pedidos del lado del proveedor (a quién el bot
-- le tiene que avisar/derivar cuando entra un pedido de una marca puntual).
-- ----------------------------------------------------------------------------
CREATE TABLE compradores (
    id                          SERIAL PRIMARY KEY,
    nombre                      VARCHAR(150) NOT NULL, -- Nombre del comprador/responsable de compras
    marca_proveedor_asignada_id INTEGER NOT NULL REFERENCES proveedores(id), -- Marca de la que se ocupa
    numero_whatsapp             VARCHAR(20) NOT NULL UNIQUE, -- Número donde el bot le reenvía/notifica pedidos
    activo                      BOOLEAN NOT NULL DEFAULT TRUE,
    creado_en                   TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ============================================================================
-- Datos de ejemplo (seed) para poder probar el flujo end-to-end sin el
-- catálogo real. Reemplazar/borrar cuando se cargue la data verdadera.
-- ============================================================================

INSERT INTO proveedores (nombre_marca, activo) VALUES
    ('Farmalife', TRUE),
    ('Ysdin', TRUE);

INSERT INTO farmacias_autorizadas (numero_whatsapp, nombre_farmacia, direccion, activo) VALUES
    ('5491122334455', 'Farmacia Central',        'Av. Siempre Viva 123, CABA', TRUE),
    ('5491133445566', 'Farmacia del Barrio',      'Calle Falsa 456, CABA',      TRUE),
    ('5491144556677', 'Farmacia San Martín',      'San Martín 789, La Plata',   FALSE);

INSERT INTO productos (codigo_barra, codigo_farmacia, nombre, marca_proveedor, stock, precio, unidad_medida, activo) VALUES
    ('7790000000011', 'FL-001', 'Ibuprofeno 400mg x20',        'Farmalife', 150, 2500.00, 'caja x20', TRUE),
    ('7790000000028', 'FL-002', 'Paracetamol 500mg x30',       'Farmalife', 80,  1800.00, 'caja x30', TRUE),
    ('7790000000035', 'FL-003', 'Alcohol en Gel 250ml',        'Farmalife', 200, 900.00,  'unidad',   TRUE),
    ('7790000000042', 'YS-001', 'Protector Solar FPS50 200ml', 'Ysdin',     60,  6500.00, 'unidad',   TRUE),
    ('7790000000059', 'YS-002', 'Crema Hidratante 100ml',      'Ysdin',     40,  4200.00, 'unidad',   TRUE),
    ('7790000000066', 'YS-003', 'Jabón Líquido Dermo 500ml',   'Ysdin',     0,   3100.00, 'unidad',   FALSE);

INSERT INTO compradores (nombre, marca_proveedor_asignada_id, numero_whatsapp, activo) VALUES
    ('Juan Pérez (Compras Farmalife)', 1, '5491155667788', TRUE),
    ('María Gómez (Compras Ysdin)',    2, '5491166778899', TRUE);
