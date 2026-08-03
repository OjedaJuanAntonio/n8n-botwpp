SELECT * FROM (
    SELECT
        l.DESCRIPCION       AS marca,
        p.DESCRIPCION       AS producto,
        p.PRECIO_PUBLICO    AS pvp,
        p.PRECIO            AS precio,
        p.PRECIO_FARMACIA   AS p_farmacia,
        p.PRECIO_DROGUERIA  AS p_drogueria,
        p.PRECIO_COSTO      AS p_costo,
        p.MONODROGA         AS monodroga
    FROM
        DW_SCO.SCO_PRODUCTOS_REP p,
        DW_SCO.SCO_LABORATORIOS l
    WHERE
        l.LABORATORIO_ID = TO_NUMBER(p.PROVEEDOR)
        AND p.INVENTORY_ITEM_STATUS_CODE = 'Active'
        AND p.PRECIO IS NOT NULL
        AND l.DESCRIPCION IN ('COTY','MAYBELLINE','SAVANT PHARM','ELEA - OTC')
    ORDER BY l.DESCRIPCION, p.DESCRIPCION
) WHERE ROWNUM <= 12
