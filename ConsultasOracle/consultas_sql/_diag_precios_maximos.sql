SELECT * FROM (
    SELECT
        p.CODIGO_BARRA     AS codigo_barra,
        p.COD_FARMACIA     AS cod_farmacia,
        p.DESCRIPCION      AS nombre,
        l.DESCRIPCION      AS marca,
        p.PRECIO_PUBLICO   AS precio
    FROM
        DW_SCO.SCO_PRODUCTOS_REP p,
        DW_SCO.SCO_LABORATORIOS l
    WHERE
        l.LABORATORIO_ID = TO_NUMBER(p.PROVEEDOR)
        AND p.INVENTORY_ITEM_STATUS_CODE = 'Active'
    ORDER BY p.PRECIO_PUBLICO DESC NULLS LAST
) WHERE ROWNUM <= 15
