-- Ejemplo de como guardar una consulta.
-- 1) En Discoverer Desktop abri el workbook (.DIS).
-- 2) Menu  Ver > Inspector de SQL  (o "Show SQL Page").
-- 3) Copia TODO el SELECT y pegalo aca, reemplazando lo de abajo.
--
-- Los parametros de Discoverer (:Deposito, :proveedor, etc.) se mantienen tal cual
-- y se completan al correr con  --p Deposito=83  --p proveedor=JEMAN
--
-- Ejemplo simple para probar la conexion:
SELECT sysdate AS fecha, user AS usuario FROM dual
