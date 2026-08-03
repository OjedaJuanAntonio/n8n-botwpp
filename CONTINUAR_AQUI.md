# CONTINUAR AQUÍ — Bot de WhatsApp Farmacia (contexto completo)

> Última actualización: **2026-07-07, ~08:30** (sesión con Claude Code).
> Este documento tiene el ESTADO ACTUAL y los PRÓXIMOS PASOS. La historia
> completa de todo lo que se hizo (cronología, errores, decisiones) está en
> **BITACORA_COMPLETA.md**.
> ✅ NOVEDAD: la primera sincronización Oracle → Postgres YA FUNCIONA (85.089 productos cargados).

---

## 1. La idea del proyecto

Un **bot de WhatsApp para la farmacia**: las farmacias autorizadas (whitelist de
números) escriben por WhatsApp para consultar **stock y precio** de productos y
hacer pedidos. Cada pedido se deriva al **comprador** responsable de la marca
(ej: pedidos de productos Farmalife → comprador de Farmalife; Ysdin → el de Ysdin).

**Piezas:**

```
WhatsApp Cloud API (Meta)
        │  webhook HTTPS (ngrok/Cloudflare Tunnel → puerto 5678)
        ▼
   n8n (Docker, localhost:5678)  ←  orquesta el flujo del bot (SE ARMA A MANO en la UI)
        │  nodo Postgres
        ▼
   PostgreSQL (Docker, localhost:5432, base "farmalife_bot")
        ▲  TRUNCATE + INSERT transaccional, cada hora (pendiente de programar)
        │
   sync_stock.py (Python 32 bits)  ←  lee Oracle vía ADODB/MSDAORA
        │
   Oracle 10g "DW" (<IP-SERVIDOR-ORACLE>:1521, esquema DW_SCO)  ←  SOLO LECTURA, fuente
   de verdad de stock/precios (data warehouse del sistema comercial; NUNCA escribir ahí)
```

---

## 2. Estructura de carpetas (todo consolidado acá)

`C:\Users\BACKUP-FCIA\Desktop\random\n8n-bot-farmacia\`

```
├── docker-compose.yml       n8n + postgres:16-alpine (volúmenes persistentes)
├── .env                     credenciales REALES (⚠ password de Postgres sigue placeholder)
├── .env.example             plantilla comentada
├── setup.sh                 levanta todo (Git Bash): chequea Docker, copia .env, up -d, espera n8n
├── README.md                guía: setup, ngrok/Cloudflare, pasos manuales en Meta, acceso n8n
├── sql\init.sql             esquema+seeds; solo corre al CREAR el volumen (down -v para regenerar)
├── CONTINUAR_AQUI.md        este documento
├── ConsultasOracle\         toolkit Oracle + sync (antes en C:\Users\BACKUP-FCIA\ConsultasOracle)
│   ├── config.py            credenciales Oracle + POSTGRES_* (completas)
│   ├── _oracle_ado.py       conexión ADODB/MSDAORA (no tocar)
│   ├── correr.py/.bat       corre un .sql de consultas_sql\ y exporta a salidas\ (⚠ .bat tiene pause)
│   ├── probar.bat           test de conexión Oracle
│   ├── sync_stock.py        el sync Oracle→Postgres (versión pg8000, cursor ya arreglado)
│   ├── sync_stock.bat       lanzador del sync (para schtasks)
│   ├── consultas_sql\       stock_sync.sql (la consulta real) + diagnósticos _diag_*.sql
│   ├── salidas\             Excel/CSV de correr.py
│   ├── logs\sync_stock.log  historial de todas las corridas del sync
│   └── CONTEXTO_DEL_PROYECTO.md   por qué MSDAORA/32 bits (¡leerlo si se toca la conexión Oracle!)
├── _archivos_viejos\        duplicados pre-consolidación (BORRABLES sin miedo)
│   (el scraper de la web pública se movió a ..\scraper-farmalife-web\, no es parte del bot)
└── (cascarón vacío en C:\Users\BACKUP-FCIA\ConsultasOracle — borrarlo a mano, quedó lockeado)
```

---

## 3. Estado de cada pieza (2026-07-06)

| Pieza | Estado |
|---|---|
| Docker n8n + Postgres | ✅ Corriendo (farmalife_n8n, farmalife_postgres healthy) |
| Esquema Postgres | ✅ Final: codigo_barra/codigo_farmacia, marca_proveedor texto, precio NUMERIC(14,2) |
| sql\init.sql | ✅ Actualizado, refleja el esquema final |
| stock_sync.sql | ✅ Consulta real validada ('Active' existe; valores: Active / No Planif / Inactive) |
| config.py | ✅ Completo (Oracle + Postgres, sin placeholders) |
| pg8000 | ✅ Instalado en C:\Python312-32 (psycopg2-binary NO compila en 32 bits) |
| sync_stock.py | ✅ Adaptado a pg8000 + fix cursor |
| **Primera sincronización** | ✅ **FUNCIONA** (2026-07-07 08:08): 85.089 filas en 550 s |
| Programación horaria (schtasks) | ⏳ **ES EL PRÓXIMO PASO** (§4) |
| Workflow n8n | ⏳ Lo arma el usuario a mano en la UI (http://localhost:5678) |
| ngrok / WEBHOOK_URL | ⏳ Pendiente (README §3) |
| App Meta / WhatsApp Cloud API | ⏳ Pendiente, pasos manuales (README §4) |

**Historial de la puesta a punto del sync (3 intentos; en los fallos el rollback
protegió la tabla):** (1) cursor de pg8000 no soporta `with` → corregido en
sync_stock.py; (2) overflow de `precio NUMERIC(10,2)` por 3 medicamentos de alto
costo > $100M (LOMUSTINA ECZANE $886.261.436,74; REMODULIN x2) → columna ampliada
a NUMERIC(14,2); (3) **OK: 85.089 filas cargadas**.

**Datos del catálogo cargado (2026-07-07):** 85.089 productos activos, solo
21.628 con precio (los otros ~63.500 vienen NULL de Oracle), 846 marcas
distintas (en MAYÚSCULAS, ej. 'ABBOTT'), precio máximo $886.261.436,74.
**Duración del sync: ~9 min** (5,7 min lectura Oracle + 3,5 min INSERT).

---

## 4. ⚡ PRÓXIMO PASO INMEDIATO: programar el sync cada hora

Comando exacto (mostrárselo a Claude o correrlo en PowerShell como administrador
si hace falta):
```
schtasks /create /tn "Sync Stock Farmalife" /tr "\"C:\Users\BACKUP-FCIA\Desktop\random\n8n-bot-farmacia\ConsultasOracle\sync_stock.bat\"" /sc hourly /st 00:00
```
Consideraciones: cada corrida tarda ~9 min y reemplaza la tabla entera en una
transacción (el bot nunca ve la tabla vacía ni a medias). Errores quedan en
`ConsultasOracle\logs\sync_stock.log`. La PC tiene que estar prendida y con
Docker Desktop corriendo para que el destino (Postgres) exista.

---

## 5. Pendientes siguientes (después del sync OK)

### 5.1 Chequear el matching de marcas
`productos.marca_proveedor` llega de Oracle en MAYÚSCULAS (ej: "PUIG ARGENTINA",
"BAGO", "ROCHE"). Los seeds de `proveedores.nombre_marca` dicen 'Farmalife'/'Ysdin'.
Cuando se definan las marcas reales del bot: actualizar `proveedores` y `compradores`
con los nombres EXACTOS que devuelve Oracle (o comparar case-insensitive en las
queries del workflow n8n). Ver marcas disponibles:
`SELECT DISTINCT marca_proveedor FROM productos ORDER BY 1;`

### 5.2 Cambiar las contraseñas placeholder ⚠
`POSTGRES_PASSWORD` sigue siendo `cambiar-esta-password-tambien` en **tres lugares
que deben mantenerse sincronizados**:
- `.env` (raíz del proyecto)
- `ConsultasOracle\config.py`
- La base viva: la imagen de Postgres solo lee el env al PRIMER init del volumen,
  así que además hay que correr:
  `docker exec -it farmalife_postgres psql -U farmalife_admin -d farmalife_bot -c "ALTER USER farmalife_admin PASSWORD 'nueva';"`

### 5.3 Exponer n8n con HTTPS (README §3)
`ngrok http 5678` → copiar URL → pegarla en `WEBHOOK_URL` del `.env` →
`docker compose up -d n8n`. (El plan gratuito de ngrok cambia la URL en cada reinicio.)

### 5.4 App de Meta (README §4 — 100% manual en developers.facebook.com)
Crear app Business → producto WhatsApp → anotar Phone Number ID / WABA ID /
Access Token → configurar webhook con URL de ngrok + Verify Token inventado →
suscribirse al campo `messages`. Token y Phone Number ID se cargan EN N8N
(credencial Header Auth + URL de Graph API), no en el .env.

### 5.5 Armar el workflow n8n (a mano, decisión del usuario)
Ya hay un workflow iniciado en la UI. Tablas disponibles: `farmacias_autorizadas`
(whitelist), `productos` (85.089 filas reales ya cargadas), `proveedores`,
`compradores` (derivación).

### 5.6 Limpieza menor
- Borrar `_archivos_viejos\` (duplicados) y el cascarón `C:\Users\BACKUP-FCIA\ConsultasOracle`.
- Los `consultas_sql\_diag_*.sql` son diagnósticos reutilizables; borrarlos si molestan.

---

## 6. Gotchas técnicos (leer antes de tocar código)

- **Python 32 bits obligatorio** (`C:\Python312-32`) para todo lo que toque Oracle:
  la base es 10g y solo conecta vía MSDAORA de 32 bits (detalle completo en
  `ConsultasOracle\CONTEXTO_DEL_PROYECTO.md`).
- **pg8000, no psycopg2**: psycopg2-binary no tiene wheel de 32 bits. Diferencias ya
  aplicadas en sync_stock.py: `database=` (no `dbname=`), sin `execute_values`
  (se usa `executemany` con placeholders `%s`), y el cursor **no soporta `with`**.
- **correr.bat termina con `pause`**: para scripts/automatización llamar
  `C:\Python312-32\python.exe correr.py ...` directo.
- Oracle `ORDER BY ... DESC` pone los **NULL primero** — usar `NULLS LAST` en diagnósticos.
- Los nombres de columna que devuelve Oracle vienen en MAYÚSCULAS; Postgres los
  pliega a minúsculas al no ir entre comillas — por eso el INSERT del sync matchea.
- Las variables `N8N_BASIC_AUTH_*` del .env son **legacy** (n8n v1+ las ignora):
  la seguridad real de n8n es la cuenta de owner creada en el primer acceso.
- `sql\init.sql` solo corre si el volumen de Postgres nace de cero
  (`docker compose down -v` — ⚠ borra TODOS los datos de negocio).

## 7. Comandos útiles

```bash
# estado / logs de contenedores (desde la raíz del proyecto)
docker compose ps
docker compose logs -f n8n

# probar conexión Oracle
ConsultasOracle> .\probar.bat

# correr una consulta suelta contra Oracle → Excel/CSV en salidas\
ConsultasOracle> .\correr.bat consultas_sql\loquesea.sql --max 50 --csv

# sync manual Oracle → Postgres
ConsultasOracle> .\sync_stock.bat

# n8n
http://localhost:5678  (cuenta de owner creada en el navegador)
```
