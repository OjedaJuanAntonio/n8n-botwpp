# BITÁCORA COMPLETA — Bot de WhatsApp Farmacia

> Registro cronológico de TODO lo hecho hasta ahora, con decisiones, errores y
> soluciones. Complementa a **CONTINUAR_AQUI.md** (que tiene el estado actual y
> los próximos pasos). Última actualización: **2026-07-07 ~08:30**.

---

## Etapa 1 — Infraestructura local n8n + Postgres (2026-07-06, tarde)

**Pedido:** armar desde cero el entorno local para un bot de WhatsApp con n8n
(solo infraestructura; el workflow se arma a mano en la UI de n8n).
**Decisiones del usuario:** Windows nativo con Git Bash (sin WSL2) + PostgreSQL.

**Qué se creó (todo en la raíz del proyecto):**

| Archivo | Contenido |
|---|---|
| `docker-compose.yml` | Servicio **n8n** (imagen oficial `docker.n8n.io/n8nio/n8n`, puerto 5678, volumen `n8n_data`→`/home/node/.n8n`, TZ America/Argentina/Buenos_Aires, basic auth y WEBHOOK_URL desde `.env`) + servicio **postgres** (postgres:16-alpine, puerto 5432, volumen `postgres_data`, `sql/init.sql` montado en `/docker-entrypoint-initdb.d/`, healthcheck `pg_isready`, y n8n con `depends_on: condition: service_healthy`) |
| `.env.example` | Plantilla comentada: credenciales n8n, Postgres, y sección-recordatorio de WhatsApp Cloud API (Access Token / Phone Number ID / WABA ID / Verify Token — esos van EN n8n, no en docker) |
| `sql/init.sql` | 4 tablas: `farmacias_autorizadas` (whitelist de números), `productos`, `proveedores`, `compradores` + seeds de prueba. Solo corre al crear el volumen por primera vez |
| `setup.sh` | Chequea Docker/Compose (con instrucciones por SO), copia `.env.example`→`.env` si falta, `docker compose up -d`, espera n8n con polling y muestra URL/credenciales |
| `README.md` | Guía completa: setup.sh, ngrok/Cloudflare Tunnel (WhatsApp exige HTTPS, no acepta localhost), pasos MANUALES en developers.facebook.com, acceso a n8n |

**Sobre la skill pedida (`czlonkowski/n8n-skills`):** NO se instaló automáticamente
— es un plugin de terceros con hooks que se ejecutan solos; requiere el MCP
`n8n-mcp` como prerequisito. Quedó documentado en README §6 cómo instalarlo a mano
(`/plugin install czlonkowski/n8n-skills` desde una sesión interactiva de Claude Code).

**Ejecución:** `docker compose config` validó OK. Al correr `setup.sh`, Docker
Desktop no estaba corriendo → se arrancó y en ~65 s estuvo listo. Contenedores
`farmar_n8n` y `farmar_postgres` levantados, init.sql aplicado, n8n
respondiendo en http://localhost:5678. El usuario creó su cuenta de owner en n8n
y empezó un workflow en la UI. Prefirió armar el workflow antes de configurar ngrok.

---

## Etapa 2 — Sync Oracle → Postgres (2026-07-06, noche)

**Pedido:** dejar operativo `sync_stock.py` (sincroniza la tabla `productos` de
Postgres con el stock/precio real de Oracle), sobre el toolkit ya existente
**ConsultasOracle** (reemplazo de Discoverer: Python **32 bits** en
`C:\Python312-32` + pywin32/ADODB/**MSDAORA**, porque la base es Oracle **10g**
—`DW` en <IP-SERVIDOR-ORACLE>:1521, esquema `DW_SCO`— y ningún driver moderno la soporta;
detalle en `ConsultasOracle\CONTEXTO_DEL_PROYECTO.md`).

**Cronología y decisiones:**

1. **Archivos nuevos ubicados:** `sync_stock.py`, `sync_stock.bat` y
   `stock_sync.sql` aparecieron en la carpeta del proyecto n8n (venían en
   `files.zip`); como los imports (`config`, `_oracle_ado`) viven en
   ConsultasOracle, se copiaron ahí (con OK del usuario).
2. **Paso 1 — validar la consulta:** diagnóstico
   `SELECT DISTINCT INVENTORY_ITEM_STATUS_CODE FROM DW_SCO.SCO_PRODUCTOS_REP`
   → valores reales: **`Active`, `No Planif`, `Inactive`**. Como 'Active' existe,
   la consulta validada por el usuario se guardó tal cual en
   `consultas_sql\stock_sync.sql` (aliases: codigo_barra, codigo_farmacia,
   nombre, marca_proveedor, stock vía `DW_SCO.BUSCO_STOCK_PROD(ITEM_ID,'T')`, precio).
3. **Paso 2 — config.py:** se agregaron las 5 variables `POSTGRES_*` con los
   valores reales del `.env` (localhost:5432, farmar_bot, farmar_admin).
4. **Paso 3 — driver Postgres:** `psycopg2-binary` **falló** (no publica wheel
   para Python 32 bits; intenta compilar y no hay pg_config) → se instaló
   **pg8000 1.31.5**. Diff de adaptación revisado y aprobado por el usuario:
   `import pg8000.dbapi`, `database=` (no `dbname=`), `executemany` con
   placeholders `%s` (pg8000 no tiene `execute_values`).
5. **Paso 4 — ALTER 1 (confirmado):** `DROP COLUMN codigo`,
   `ADD codigo_barra VARCHAR(20)`, `ADD codigo_farmacia VARCHAR(20)`.
6. **Consolidación (pedida por el usuario):** TODO el proyecto ConsultasOracle
   se movió adentro de la carpeta del bot (robocopy /MOVE). Quedó un cascarón
   vacío lockeado en `C:\Users\BACKUP-FCIA\ConsultasOracle` (borrar a mano).
   Duplicados viejos → `_archivos_viejos\`.
7. **Revisión integral** — hallazgos principales:
   - **Bloqueante:** la tabla tenía `marca_proveedor_id` (FK numérica) pero el
     sync inserta `marca_proveedor` (texto de Oracle).
   - `stock`/`precio` eran NOT NULL, y Oracle trae muchísimos NULL.
   - `init.sql` había quedado con el esquema viejo (drift).
   - Passwords placeholder en `.env`/`config.py` (siguen pendientes, §5.2 de CONTINUAR_AQUI).
   - Las `N8N_BASIC_AUTH_*` son legacy en n8n v1+ (la seguridad real es la cuenta owner).
8. **ALTER 2 (confirmado, bloques A+B):** `DROP marca_proveedor_id`,
   `ADD marca_proveedor VARCHAR(150)`; `stock` y `precio` → aceptan NULL.
   `init.sql` actualizado para reflejar el esquema final (+ seeds nuevos).
9. **Paso 5:** `py_compile` OK.

**Primeros intentos del sync (Paso 7, confirmado):**

- **Intento 1** (20:18): Oracle devolvió 85.062 filas en 5,5 min, pero falló al
  escribir: `'Cursor' object does not support the context manager protocol`
  → el cursor de pg8000 **no soporta `with`** (el de psycopg2 sí). Fix aplicado
  en `sync_stock.py` (único arreglo autónomo, según lo acordado). El ROLLBACK
  protegió la tabla.
- **Intento 2** (20:24): avanzó hasta el INSERT y falló:
  `numeric field overflow` — `precio NUMERIC(10,2)` tope $99.999.999,99.
  **Diagnóstico** (consultas de solo lectura): son datos REALES — 3 medicamentos
  de alto costo: LOMUSTINA ECZANE $886.261.436,74, REMODULIN 10MG $266.657.620,75,
  REMODULIN 5MG $141.689.731,95. Además: **63.527 de 85.062 precios en NULL** (75%)
  → confirmó que relajar el NOT NULL era imprescindible. Gotcha aprendido: en Oracle
  `ORDER BY ... DESC` pone los NULL primero (usar `NULLS LAST`).
- **Solución propuesta:** `ALTER COLUMN precio TYPE NUMERIC(14,2)`. El usuario se
  ausentó; quedó preparado `aplicar_alter_precio.bat` y se creó `CONTINUAR_AQUI.md`.

---

## Etapa 3 — Sync funcionando (2026-07-07, mañana)

1. Usuario confirmó → **ALTER aplicado**: `precio` ahora `NUMERIC(14,2)`
   (verificado por information_schema). Scripts de un solo uso borrados.
2. **`sync_stock.bat` corrió COMPLETO y OK:**
   ```
   Oracle devolvio 85089 filas
   OK: 85089 filas cargadas en 'productos'.
   Sincronizacion terminada OK en 550.0 segundos.
   ```
3. **Verificación en Postgres:** 85.089 filas totales, 21.628 con precio,
   precio máximo $886.261.436,74 (la LOMUSTINA entró bien), **846 marcas
   distintas** (vienen en MAYÚSCULAS: 'ABBOTT', 'PUIG ARGENTINA', 'BAGO'...).
4. Duración real del ciclo: **~9 min** (5,7 min lectura Oracle fila-por-fila por
   la función de stock + 3,5 min INSERT de 85 mil filas con pg8000).
5. `CONTINUAR_AQUI.md` actualizado. El **Paso 8 (schtasks horario) quedó
   PENDIENTE**: el usuario pidió esta bitácora antes de decidir. El comando
   exacto propuesto está en CONTINUAR_AQUI.md §4.

---

## Esquema final de `productos` (el que está vivo en la base)

```
id               serial PK
nombre           varchar(200) NOT NULL
stock            integer NULL, default 0
precio           numeric(14,2) NULL          ← medicamentos de alto costo + 75% NULL
unidad_medida    varchar(20) NOT NULL default 'unidad'
activo           boolean NOT NULL default true
creado_en        timestamptz NOT NULL default now()
codigo_barra     varchar(20) NULL            ← EAN de Oracle
codigo_farmacia  varchar(20) NULL            ← código interno de Oracle
marca_proveedor  varchar(150) NULL           ← laboratorio en texto, MAYÚSCULAS
```
El sync la reemplaza ENTERA (TRUNCATE+INSERT en una transacción) en cada corrida:
el bot nunca la ve vacía ni a medias. Si Oracle falla, Postgres no se toca.

## Reglas de trabajo acordadas con el usuario

- Cambios de esquema / acciones destructivas: **mostrar el comando exacto y
  esperar confirmación explícita** antes de ejecutar.
- Mostrar siempre la **salida real completa** de los comandos (nunca "listo" sin salida).
- Ante errores del sync: **un solo intento de arreglo autónomo**; después, revisar juntos.
- La base Oracle `DW` es **SOLO LECTURA** (data warehouse; se pisa desde el sistema comercial).

## Dónde está cada cosa

- Estado actual y próximos pasos → **CONTINUAR_AQUI.md** (raíz del proyecto)
- Por qué MSDAORA/Python 32 bits → `ConsultasOracle\CONTEXTO_DEL_PROYECTO.md`
- Guía de infraestructura n8n/ngrok/Meta → `README.md`
- Log de todas las corridas del sync → `ConsultasOracle\logs\sync_stock.log`
- Credenciales → `.env` (raíz) y `ConsultasOracle\config.py` (⚠ password de
  Postgres sigue siendo el placeholder; cambiarla exige tocar 3 lugares, ver
  CONTINUAR_AQUI.md §5.2)
