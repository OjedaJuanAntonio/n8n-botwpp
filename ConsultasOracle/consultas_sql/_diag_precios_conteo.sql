SELECT
    COUNT(*)                                                        AS total_activos,
    SUM(CASE WHEN p.PRECIO_PUBLICO IS NULL THEN 1 ELSE 0 END)       AS precios_null,
    SUM(CASE WHEN p.PRECIO_PUBLICO >= 100000000 THEN 1 ELSE 0 END)  AS precios_overflow,
    MAX(p.PRECIO_PUBLICO)                                           AS precio_maximo
FROM
    DW_SCO.SCO_PRODUCTOS_REP p,
    DW_SCO.SCO_LABORATORIOS l
WHERE
    l.LABORATORIO_ID = TO_NUMBER(p.PROVEEDOR)
    AND p.INVENTORY_ITEM_STATUS_CODE = 'Active'
