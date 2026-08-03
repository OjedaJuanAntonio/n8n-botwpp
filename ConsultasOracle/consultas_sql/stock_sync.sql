SELECT
    p.CODIGO_BARRA                         AS codigo_barra,
    p.COD_FARMACIA                         AS codigo_farmacia,
    p.DESCRIPCION                          AS nombre,
    l.DESCRIPCION                          AS marca_proveedor,
    DW_SCO.BUSCO_STOCK_PROD(p.ITEM_ID,'T') AS stock,
    p.PRECIO_PUBLICO                       AS precio
FROM
    DW_SCO.SCO_PRODUCTOS_REP p,
    DW_SCO.SCO_LABORATORIOS l
WHERE
    l.LABORATORIO_ID = TO_NUMBER(p.PROVEEDOR)
    AND p.INVENTORY_ITEM_STATUS_CODE = 'Active'
ORDER BY
    l.DESCRIPCION ASC, p.DESCRIPCION ASC
