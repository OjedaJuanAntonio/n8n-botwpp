-- ============================================================================
-- 02_datos_negocio.sql
-- Rediseña las tablas de negocio y carga los datos para el PILOTO.
--
-- Por qué el rediseño: hoy "compradores" tiene una fila por marca
-- (marca_proveedor_asignada_id), así que un comprador que atiende 70
-- laboratorios necesitaría 70 filas repetidas. El CSV maestro es
-- LABORATORIO -> COMPRADOR, así que el modelo natural es:
--     compradores  = una fila por persona (con su WhatsApp)
--     proveedores  = una fila por marca, apuntando a su comprador
--
-- Se puede ejecutar más de una vez sin romper nada.
--
-- ANTES DE EJECUTAR: reemplazar los '54XXXXXXXXXX' por el número real de
-- WhatsApp (formato internacional sin '+'). Los números reales no se versionan
-- porque este repositorio es público; la copia con los datos del piloto está
-- en datos/02_datos_negocio.local.sql (fuera de git).
--
--   docker exec -i farmar_postgres psql -U farmar_admin -d farmar_bot \
--       -v ON_ERROR_STOP=1 -f - < sql/02_datos_negocio.sql
-- ============================================================================

BEGIN;

-- ---------------------------------------------------------------------------
-- 1. compradores: una fila por persona
-- ---------------------------------------------------------------------------
DROP TABLE IF EXISTS compradores CASCADE;
CREATE TABLE compradores (
    id              SERIAL PRIMARY KEY,
    nombre          VARCHAR(150) NOT NULL,        -- Nombre del responsable de compras
    numero_whatsapp VARCHAR(20) NOT NULL UNIQUE,  -- Internacional sin '+', ej: 54XXXXXXXXXX
    activo          BOOLEAN NOT NULL DEFAULT TRUE,
    creado_en       TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------------------------
-- 2. proveedores: una fila por marca, con el comprador que la atiende.
--    comprador_id puede quedar NULL: son las marcas sin asignar (obsoletas).
-- ---------------------------------------------------------------------------
DROP TABLE IF EXISTS proveedores CASCADE;
CREATE TABLE proveedores (
    id            SERIAL PRIMARY KEY,
    nombre_marca  VARCHAR(150) NOT NULL UNIQUE,   -- Tal como viene de Oracle (MAYÚSCULAS)
    comprador_id  INTEGER REFERENCES compradores(id),
    activo        BOOLEAN NOT NULL DEFAULT TRUE,
    creado_en     TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------------------------
-- 3. Índices para las búsquedas del bot.
--    pg_trgm permite buscar por nombre parcial ("dame ibuprofeno") de forma
--    rápida con ILIKE '%...%', que sin índice hace scan completo de 85k filas.
-- ---------------------------------------------------------------------------
CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE INDEX IF NOT EXISTS idx_productos_codigo_barra    ON productos (codigo_barra);
CREATE INDEX IF NOT EXISTS idx_productos_codigo_farmacia ON productos (codigo_farmacia);
CREATE INDEX IF NOT EXISTS idx_productos_marca           ON productos (marca_proveedor);
CREATE INDEX IF NOT EXISTS idx_productos_nombre_trgm     ON productos USING gin (nombre gin_trgm_ops);
CREATE INDEX IF NOT EXISTS idx_productos_con_stock       ON productos (stock) WHERE stock > 0;

-- ---------------------------------------------------------------------------
-- 4. Vista con lo que el bot puede ofrecer de verdad (lo que tiene stock).
--    Se mantiene la tabla productos completa a propósito: permite distinguir
--    "no trabajamos ese producto" de "lo trabajamos pero está sin stock",
--    que son respuestas muy distintas para la farmacia.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE VIEW productos_disponibles AS
SELECT p.id, p.codigo_barra, p.codigo_farmacia, p.nombre, p.marca_proveedor,
       p.stock, p.precio, p.unidad_medida
FROM productos p
WHERE p.stock > 0;

-- ---------------------------------------------------------------------------
-- 5. Datos del PILOTO
-- ---------------------------------------------------------------------------

-- Comprador de prueba: recibe las derivaciones de TODAS las marcas.
INSERT INTO compradores (nombre, numero_whatsapp, activo)
VALUES ('Juan Ojeda (comprador de prueba)', '54XXXXXXXXXX', TRUE);

-- Farmacia autorizada de prueba.
DELETE FROM farmacias_autorizadas;
INSERT INTO farmacias_autorizadas (numero_whatsapp, nombre_farmacia, direccion, activo)
VALUES ('54XXXXXXXXXX', 'Farmacia de Prueba (Juan)', 'Corrientes', TRUE);

-- Todas las marcas reales del catálogo, apuntando al comprador de prueba.
INSERT INTO proveedores (nombre_marca, comprador_id, activo)
SELECT DISTINCT p.marca_proveedor,
       (SELECT id FROM compradores WHERE numero_whatsapp = '54XXXXXXXXXX'),
       TRUE
FROM productos p
WHERE p.marca_proveedor IS NOT NULL AND btrim(p.marca_proveedor) <> ''
ON CONFLICT (nombre_marca) DO NOTHING;

COMMIT;
