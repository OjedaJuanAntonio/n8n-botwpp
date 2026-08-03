# Contexto completo del proyecto — Consultas Oracle en Python (reemplazo de Discoverer)

> Documento de referencia para reutilizar en próximos proyectos.
> Fecha de armado: junio 2026. PC: Windows 11 Pro.

---

## 1. Objetivo

Reemplazar **Oracle Discoverer Desktop** (que funciona muy lento) por una forma
**programática en Python** de ejecutar las mismas consultas que estaban guardadas
en los archivos `.DIS`, y exportar los resultados a Excel/CSV.

Uso previsto: bajar listas de precios / stock de proveedores desde la base, para
luego **procesarlas** en Python. La **escritura/actualización** de precios NO se
hace desde acá: eso se hace después desde el **Sistema Comercial (Oracle)**. Python
solo lee y procesa (separación limpia y segura).

---

## 2. Punto de partida: los archivos .DIS

- Estaban en la carpeta de red `Y:\CONSULTAS VARIAS` (junto a ~2000 `.xls`).
- Son **28 workbooks** de Oracle Discoverer **10.1.2**.
- Internamente son **archivos contenedor OLE** (magic bytes `D0 CF 11 E0...`), con un
  stream `Contents`.
- **CLAVE:** los `.DIS` **NO contienen el SQL en texto plano**. Guardan referencias a
  la capa **EUL (End User Layer)** de Discoverer: áreas de negocio (ej.
  *"Maestro de Productos (Master)"*), ítems (`STOCK_TOTAL`, `PRECIO_COSTO_FACOR`…),
  condiciones (`Estado <> 'Inactive'`) y parámetros (`:Deposito`, `:proveedor`).
  El SQL real contra las tablas lo **genera Discoverer al vuelo** desde ese metadato.
- Por eso, para cada consulta, el SQL real se saca **una sola vez** desde Discoverer:
  menú **Ver > Inspector de SQL** (Show SQL) → copiar el SELECT → guardarlo como `.sql`.
  A partir de ahí esa consulta ya no depende de Discoverer.

---

## 3. Diagnóstico del entorno (cómo se averiguó todo)

| Qué | Cómo se descubrió | Resultado |
|---|---|---|
| IP/puerto de la base | leyendo `sqlnet.log` en la carpeta | `<IP-SERVIDOR-ORACLE>:1521` |
| Conectividad de red | `Test-NetConnection <IP-SERVIDOR-ORACLE> -Port 1521` | ✅ abierto |
| Cliente Oracle instalado | registro `HKLM\SOFTWARE\ORACLE` | `D:\oracle\BIToolsHome_1` (Discoverer 10.1, **32 bits**) |
| Alias TNS de la base | `tnsnames.ora` del cliente Discoverer | alias **`DW`** → host `<IP-SERVIDOR-ORACLE>`, `SERVICE_NAME = DW` |
| Versión de la base | consulta `v$version` vía MSDAORA | **Oracle 10g 10.2.0.1.0** (Linux, 64 bits) |
| Python disponible | `py --version` | 3.14 (64 bits) — luego se agregó 3.12 (32 bits) |

**Datos de conexión finales:**
- Host/puerto: `<IP-SERVIDOR-ORACLE>:1521`
- Alias TNS: `DW`  (SERVICE_NAME = `DW`)
- Usuario / contraseña: los mismos de Discoverer (en `config.py`)
- Esquema de los datos: `DW_SCO` (ej. `DW_SCO.SCO_PRODUCTOS_REP`, `DW_SCO.SCO_LABORATORIOS`)
- Hay funciones PL/SQL propias, ej. `COBOL.BUSCO_STOCK_FINAN(item_id, 'J')` → trae stock.

---

## 4. El problema técnico central (y por qué la solución terminó siendo "rara")

La base es **Oracle 10g (10.2.0.1)**, muy antigua. Eso choca con las herramientas modernas:

1. **`python-oracledb` modo "thin"** (sin cliente): solo soporta Oracle **12.1+**.
   → Error `DPY-3010`. Descartado.
2. **`python-oracledb` modo "thick"**: necesita un **cliente Oracle 11.2 o superior**.
   El único cliente de la PC es el de Discoverer (**10.1**), demasiado viejo.
   → Error `DPI-1072: unsupported`. Descartado.
3. **Instant Client moderno (19c)**: NO soporta bases 10.2 (solo 11.2+). Descartado.
4. **Instant Client 11.2** (sí sería compatible con 10.2): la descarga requiere
   **cuenta de Oracle (login SSO)**. No se pudo bajar automáticamente. Quedó como
   alternativa "más moderna" pendiente, pero no se usó por la fricción.
5. El cliente de Discoverer **no incluye** OraOLEDB ni el ODBC de Oracle (es solo
   runtime de BI). En el sistema solo había puentes viejos de Microsoft.

### Solución que SÍ funcionó (sin descargar nada)

Conectarse con el **proveedor OLE DB de Windows `MSDAORA`** vía **ADODB** (librería
`pywin32`), **reutilizando el cliente Oracle 10.1 de Discoverer** que ya estaba.

Como ese cliente es de **32 bits**, hubo que instalar un **Python de 32 bits dedicado**
(`C:\Python312-32`) — la arquitectura del Python debe coincidir con la del cliente.

```
Python 32-bit  →  pywin32 (ADODB)  →  MSDAORA  →  cliente Oracle 10.1 (Discoverer)  →  base DW (Oracle 10g)
```

**Gotchas aprendidos con MSDAORA:**
- Los comentarios `--` y el `;` final pueden dejar el recordset cerrado → se limpian
  antes de ejecutar (`limpiar_sql`). Se usa `Connection.Execute()` (más tolerante que
  `Recordset.Open`).
- Las fechas vuelven como `pywintypes.datetime` con zona horaria; openpyxl no las
  acepta → se convierten a datetime "naive" (`_a_python`).
- Los números **sí** se leen bien (vuelven como `Decimal`). **Atención:** si una columna
  numérica sale vacía, **primero verificar si el dato es NULL en la base** (nos pasó: un
  laboratorio tenía todos los precios en NULL) — no asumir que es limitación del driver.

---

## 5. Estructura del proyecto

Carpeta: `C:\Users\BACKUP-FCIA\ConsultasOracle`

```
config.py            Credenciales + alias + rutas del cliente Oracle
_oracle_ado.py       Conexión común (ADODB/MSDAORA) + limpieza SQL + conversión de tipos
probar_conexion.py   Test de conexión (muestra v$version)
correr.py            Corre un .sql, aplica parámetros y exporta a Excel/CSV
probar.bat           Lanza probar_conexion.py con el Python 32-bit
correr.bat           Lanza correr.py con el Python 32-bit
consultas_sql\       Los .sql sacados del Inspector de Discoverer
salidas\             Excel/CSV generados
LEEME.txt            Guía corta de uso
CONTEXTO_DEL_PROYECTO.md   Este documento
```

### Software instalado para que funcione
- **Python 3.12 (32 bits)** en `C:\Python312-32` (instalación silenciosa, no toca el Python 64-bit).
- En ese Python: `pip install pywin32 openpyxl` (y `oracledb` quedó instalado pero NO se usa).
- Reutiliza el cliente Oracle ya existente: `D:\oracle\BIToolsHome_1`.

---

## 6. Cómo se usa (día a día)

```powershell
# parado en C:\Users\BACKUP-FCIA\ConsultasOracle

# 1) probar conexión
.\probar.bat

# 2) correr una consulta (el SQL ya guardado en consultas_sql\)
.\correr.bat consultas_sql\precios_por_laboratorio.sql --p PROVEEDOR=2081

# opciones: --max 50  (limitar filas)   --csv  (también CSV)   --salida nombre.xlsx
```

Para una consulta nueva: Discoverer → **Ver > Inspector de SQL** → copiar SELECT →
guardar en `consultas_sql\` → correr. Los parámetros `:Nombre` de Discoverer se pasan
con `--p Nombre=valor`.

---

## 7. Receta para REPLICAR esto en otra PC / otro proyecto similar

1. **Averiguar a qué base apunta** (leer `sqlnet.log`, buscar `tnsnames.ora`, registro
   `HKLM\SOFTWARE\ORACLE` para hallar el ORACLE_HOME y la arquitectura del cliente).
2. **Probar conectividad** de red al host:puerto (`Test-NetConnection`).
3. **Averiguar la versión de la base** (`SELECT banner FROM v$version`).
4. **Elegir el driver según la versión:**
   - Base **12.1+** → `python-oracledb` modo thin (lo más simple, sin cliente). 64-bit.
   - Base **vieja (10g/11g)** con cliente moderno disponible → `oracledb` thick + Instant
     Client 11.2 (descarga con cuenta Oracle).
   - Base **vieja** y solo hay un cliente Oracle **viejo** instalado → repetir esta receta:
     **Python de la misma arquitectura del cliente + pywin32 + MSDAORA**.
5. **Recordar:** la arquitectura (32/64 bits) del Python debe coincidir con la del cliente
   Oracle en modo thick/MSDAORA.

---

## 8. Notas de seguridad / buenas prácticas

- La base `DW` es un **Data Warehouse de reportes** (copia de solo lectura, se regenera
  desde el sistema operativo/COBOL). **No escribir** precios acá: se pisarían y no sirven.
  Las actualizaciones se hacen desde el **Sistema Comercial**.
- Los parámetros se reemplazan por texto dentro del SQL (`aplicar_parametros`). Es para
  **uso interno/confiable**; no exponer esto a usuarios externos/internet (riesgo de
  inyección SQL).
- La contraseña está en texto plano en `config.py`. Aceptable para una PC interna; si se
  quiere endurecer, mover a variable de entorno.

---

## 9. Mejoras posibles (no hechas)

- Alias de columnas más legibles en los `.sql` (las consultas de Discoverer traen columnas
  duplicadas como `DESCRIPCION` y expresiones sin nombre).
- Sumar **pandas** para el procesamiento de listas (comparar precios viejos vs. nuevos,
  aplicar márgenes, detectar diferencias).
- Migrar a `python-oracledb` + Instant Client 11.2 si se quiere salir del proveedor
  legacy MSDAORA (requiere cuenta Oracle para la descarga).
