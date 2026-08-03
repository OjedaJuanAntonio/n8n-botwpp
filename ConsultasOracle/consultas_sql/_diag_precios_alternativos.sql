SELECT
    l.DESCRIPCION AS marca,
    COUNT(*) AS productos,
    COUNT(p.PRECIO_PUBLICO)   AS con_precio_publico,
    COUNT(p.PRECIO)           AS con_precio,
    COUNT(p.PRECIO_FARMACIA)  AS con_precio_farmacia,
    COUNT(p.PRECIO_DROGUERIA) AS con_precio_drogueria,
    COUNT(p.PRECIO_COSTO)     AS con_precio_costo,
    COUNT(p.MONODROGA)        AS con_monodroga
FROM
    DW_SCO.SCO_PRODUCTOS_REP p,
    DW_SCO.SCO_LABORATORIOS l
WHERE
    l.LABORATORIO_ID = TO_NUMBER(p.PROVEEDOR)
    AND p.INVENTORY_ITEM_STATUS_CODE = 'Active'
    AND l.DESCRIPCION IN ('COTY','PUIG ARGENTINA','MAYBELLINE','ARCOR S.A.','SAVANT PHARM','ELEA - OTC')
GROUP BY l.DESCRIPCION
ORDER BY productos DESC
