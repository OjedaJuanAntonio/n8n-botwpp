# datos/ — datos maestros de negocio

Archivos fuente con los que se cargan las tablas de negocio del bot
(`proveedores`, `compradores`, `farmacias_autorizadas`).

**No se versionan** (están en `.gitignore`): contienen nombres de empleados y
números de teléfono. El repositorio es público.

## compradores_por_laboratorio.csv

Origen: export de la planilla MAESTROS_CENTRALES (2026-08-03).
Columnas: `ID_COMPRADOR`, `LABORATORIO`, `NOMBRE_COMPRADOR`.

Estado del archivo al momento de recibirlo — **necesita limpieza antes de cargarlo**:

| Situación | Filas |
|---|---|
| Total | 945 |
| Con comprador válido | 256 |
| Con `#N/A` (error de fórmula) | 361 |
| Con comprador vacío | 326 |

Compradores identificados: `cesar` (ca1), `tocci` (s1), `Claudio Acevedo` (c1),
`jorge` (j1), `ale soto` (al1), `manu`, y combinaciones compartidas
(`cesar/manu`, `claudio/tocci`, `tocci/claudio`).

### Problemas detectados al cruzar con el catálogo real

- De los 256 laboratorios con comprador, **solo 140 coinciden** con alguna marca
  del catálogo de Oracle. Los otros 116 son casi todos **diferencias de
  escritura**: `ABBOT`/`ABBOTT`, `ABBVIE`/`ABBVIE S.A`, `ASTRA-ZENECA`/`ASTRA ZENECA`,
  `BAYER (ETICO)`/`BAYER (ETICOS)`, `BAGO DERMOCOSMETICA` (el catálogo tiene doble
  espacio), etc. Se resuelven normalizando y revisando a mano los dudosos.
- **706 marcas del catálogo no tienen comprador asignado.**
- `Claudio Acevedo` aparece con dos IDs distintos (`c1` y `j1`).
- Hay 2 laboratorios duplicados.

### Pendiente

Definir qué hacer con los laboratorios sin comprador y con las asignaciones
compartidas (¿se derivan a los dos? ¿a uno principal?), y conseguir los números
de WhatsApp de cada comprador, que este archivo no trae.
