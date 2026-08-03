SELECT
    COUNT(*)                        AS total_activos,
    COUNT(p.PRECIO_PUBLICO)         AS con_pvp,
    COUNT(p.PRECIO)                 AS con_precio,
    COUNT(p.PRECIO_FARMACIA)        AS con_precio_farmacia,
    COUNT(COALESCE(p.PRECIO_PUBLICO, p.PRECIO)) AS con_alguno,
    COUNT(p.MONODROGA)              AS con_monodroga,
    COUNT(p.FONETICA)               AS con_fonetica,
    COUNT(p.TROQUEL)                AS con_troquel
FROM
    DW_SCO.SCO_PRODUCTOS_REP p,
    DW_SCO.SCO_LABORATORIOS l
WHERE
    l.LABORATORIO_ID = TO_NUMBER(p.PROVEEDOR)
    AND p.INVENTORY_ITEM_STATUS_CODE = 'Active'
