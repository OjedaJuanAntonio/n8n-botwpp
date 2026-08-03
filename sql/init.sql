-- ============================================================================
-- init.sql
-- Esquema inicial de la base de datos de NEGOCIO para el bot de WhatsApp.
--
-- Este script lo ejecuta automáticamente el contenedor oficial de Postgres
-- (imagen postgres:16-alpine) SOLO la primera vez que se crea el volumen
-- "postgres_data", porque está montado en /docker-entrypoint-initdb.d/.
-- Si ya existe el volumen, este archivo NO se vuelve a correr. Para forzar
-- que se re-ejecute hay que borrar el volumen: docker compose down -v
-- (⚠ eso borra TODOS los datos de negocio).
--
-- El catálogo real (tabla productos) lo carga ConsultasOracle\sync_stock.py
-- desde el Oracle de la empresa. Los seeds de acá son mínimos, solo para que
-- el bot pueda probarse antes de la primera sincronización.
-- ============================================================================

CREATE EXTENSION IF NOT EXISTS pg_trgm;  -- búsqueda por texto parcial (ILIKE '%...%')

-- ----------------------------------------------------------------------------
-- Tabla: compradores
-- Personas que gestionan las compras del lado de la droguería. El bot les
-- deriva los pedidos según la marca del producto solicitado.
-- Una fila por PERSONA (no por marca): un comprador atiende muchas marcas.
-- ----------------------------------------------------------------------------
CREATE TABLE compradores (
    id              SERIAL PRIMARY KEY,
    nombre          VARCHAR(150) NOT NULL,        -- Nombre del responsable de compras
    numero_whatsapp VARCHAR(20) NOT NULL UNIQUE,  -- Internacional sin '+', ej: 54XXXXXXXXXX
    activo          BOOLEAN NOT NULL DEFAULT TRUE,
    creado_en       TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ----------------------------------------------------------------------------
-- Tabla: proveedores
-- Cada marca/laboratorio del catálogo, con el comprador que la atiende.
-- El nombre debe coincidir EXACTAMENTE con productos.marca_proveedor, que
-- viene de Oracle en MAYÚSCULAS (ej: 'ABBOTT', 'PUIG ARGENTINA').
-- comprador_id puede ser NULL: marcas sin comprador asignado (obsoletas).
-- ----------------------------------------------------------------------------
CREATE TABLE proveedores (
    id            SERIAL PRIMARY KEY,
    nombre_marca  VARCHAR(150) NOT NULL UNIQUE,
    comprador_id  INTEGER REFERENCES compradores(id),
    activo        BOOLEAN NOT NULL DEFAULT TRUE,
    creado_en     TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ----------------------------------------------------------------------------
-- Tabla: farmacias_autorizadas
-- Whitelist de números de WhatsApp habilitados para usar el bot. Un mensaje
-- de un número que no esté acá (o con activo = FALSE) debe ser ignorado.
-- ----------------------------------------------------------------------------
CREATE TABLE farmacias_autorizadas (
    id              SERIAL PRIMARY KEY,
    numero_whatsapp VARCHAR(20) NOT NULL UNIQUE,  -- Internacional sin '+', ej: 54XXXXXXXXXX
    nombre_farmacia VARCHAR(150) NOT NULL,
    direccion       VARCHAR(200),
    activo          BOOLEAN NOT NULL DEFAULT TRUE,
    creado_en       TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ----------------------------------------------------------------------------
-- Tabla: productos
-- Catálogo con stock y precio. La REEMPLAZA COMPLETA (TRUNCATE + INSERT en una
-- sola transacción) el script sync_stock.py en cada corrida, con lo que trae
-- consultas_sql\stock_sync.sql. Los alias de ese SELECT deben coincidir con
-- estos nombres de columna.
--
-- Notas sobre los datos reales de Oracle:
--   - precio = PRECIO_FARMACIA (costo + margen de droguería, que es lo que
--     paga la farmacia). ~76% del catálogo tiene precio; el resto viene NULL.
--   - monodroga (principio activo) solo aplica a medicamentos (~22%).
--   - stock puede ser 0: el producto se trabaja pero no hay disponibilidad.
-- ----------------------------------------------------------------------------
CREATE TABLE productos (
    id              SERIAL PRIMARY KEY,
    codigo_barra    VARCHAR(20),                  -- EAN (Oracle CODIGO_BARRA)
    codigo_farmacia VARCHAR(20),                  -- Código interno (Oracle COD_FARMACIA)
    troquel         VARCHAR(50),                  -- Código troquel (Oracle TROQUEL)
    nombre          VARCHAR(200) NOT NULL,        -- Nombre comercial (Oracle DESCRIPCION)
    monodroga       VARCHAR(120),                 -- Principio activo (Oracle MONODROGA)
    marca_proveedor VARCHAR(150),                 -- Laboratorio (Oracle l.DESCRIPCION)
    stock           INTEGER DEFAULT 0,
    precio          NUMERIC(14, 2),               -- Oracle PRECIO_FARMACIA
    unidad_medida   VARCHAR(20) NOT NULL DEFAULT 'unidad',
    activo          BOOLEAN NOT NULL DEFAULT TRUE,
    creado_en       TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Índices para las búsquedas del bot (sin ellos, cada consulta recorre 85k filas)
CREATE INDEX idx_productos_codigo_barra    ON productos (codigo_barra);
CREATE INDEX idx_productos_codigo_farmacia ON productos (codigo_farmacia);
CREATE INDEX idx_productos_troquel         ON productos (troquel);
CREATE INDEX idx_productos_marca           ON productos (marca_proveedor);
CREATE INDEX idx_productos_nombre_trgm     ON productos USING gin (nombre gin_trgm_ops);
CREATE INDEX idx_productos_monodroga_trgm  ON productos USING gin (monodroga gin_trgm_ops);
CREATE INDEX idx_productos_con_stock       ON productos (stock) WHERE stock > 0;

-- ----------------------------------------------------------------------------
-- Vista: productos_disponibles
-- Lo que el bot puede ofrecer realmente. Se mantiene la tabla completa a
-- propósito, para poder distinguir "no trabajamos ese producto" de "lo
-- trabajamos pero está sin stock": son respuestas distintas para la farmacia.
-- ----------------------------------------------------------------------------
CREATE VIEW productos_disponibles AS
SELECT p.id, p.codigo_barra, p.codigo_farmacia, p.troquel, p.nombre, p.monodroga,
       p.marca_proveedor, p.stock, p.precio, p.unidad_medida
FROM productos p
WHERE p.stock > 0;

-- ============================================================================
-- Seeds mínimos (piloto). Las marcas reales las carga sql/02_datos_negocio.sql
-- a partir del catálogo ya sincronizado.
-- ============================================================================

INSERT INTO compradores (nombre, numero_whatsapp, activo) VALUES
    ('Comprador de prueba', '54XXXXXXXXXX', TRUE);

INSERT INTO farmacias_autorizadas (numero_whatsapp, nombre_farmacia, direccion, activo) VALUES
    ('54XXXXXXXXXX', 'Farmacia de Prueba', 'Corrientes', TRUE);
