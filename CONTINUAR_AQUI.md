# CONTINUAR AQUÍ — Bot de WhatsApp Farmacia (contexto completo)

> Última actualización: **2026-07-07, ~08:30** (sesión con Claude Code).
> Este documento tiene el ESTADO ACTUAL y los PRÓXIMOS PASOS. La historia
> completa de todo lo que se hizo (cronología, errores, decisiones) está en
> **BITACORA_COMPLETA.md**.
> ✅ NOVEDAD: la primera sincronización Oracle → Postgres YA FUNCIONA (85.089 productos cargados).

---

## 1. La idea del proyecto

Un **bot de WhatsApp para la red de farmacias Farmar** (~150 farmacias). Las
farmacias autorizadas (whitelist de números) escriben por WhatsApp para
consultar **stock y precio** y hacer pedidos. Cada pedido se deriva al
**comprador** de Jufec SA responsable de esa marca (ej: un pedido de un producto
ABBOTT va al comprador que atiende ABBOTT).

Quién es quién: **Farmar** es la red de farmacias que usa el bot; **Jufec SA** es
la droguería / centro administrativo y logístico que las abastece, y de donde
salen el catálogo (Oracle) y los compradores.

**Piezas:**

```
WhatsApp Cloud API (Meta)
        │  webhook HTTPS (ngrok/Cloudflare Tunnel → puerto 5678)
        ▼
   n8n (Docker, localhost:5678)  ←  orquesta el flujo del bot (SE ARMA A MANO en la UI)
        │  nodo Postgres
        ▼
   PostgreSQL (Docker, localhost:5432, base "farmar_bot")
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

## 3. Estado de cada pieza (2026-08-03)

| Pieza | Estado |
|---|---|
| Docker n8n + Postgres | ✅ Corriendo (`farmar_n8n`, `farmar_postgres` healthy) |
| Esquema Postgres | ✅ Final: codigo_barra / codigo_farmacia / troquel / monodroga, marca_proveedor texto, precio NUMERIC(14,2) |
| sql\init.sql | ✅ Refleja el esquema final |
| stock_sync.sql | ✅ Trae PRECIO_FARMACIA + MONODROGA + TROQUEL |
| config.py | ✅ Completo (Oracle + Postgres, sin placeholders) |
| pg8000 | ✅ Instalado en C:\Python312-32 (psycopg2-binary NO compila en 32 bits) |
| Sincronización | ✅ **FUNCIONA**: 85.680 filas en ~9 min |
| Datos del piloto | ✅ 1 farmacia + 1 comprador de prueba, 846 marcas cargadas |
| Índices y consultas del bot | ✅ Probados (whitelist, código, nombre, equivalentes, comprador) |
| Repo GitHub | ✅ https://github.com/OjedaJuanAntonio/n8n-botwpp |
| **Workflow n8n** | ⏳ **ES EL PRÓXIMO PASO** (§4): está en `n8n\farmar-whatsapp-bot-v2.json`, falta importarlo |
| Programación horaria (schtasks) | ⏳ Pendiente (§5.3) |
| ngrok / WEBHOOK_URL | ⏳ Pendiente (README §3) |
| App Meta / WhatsApp Cloud API | ⏳ Pendiente, pasos manuales (README §4) |

**Datos del catálogo cargado:** 85.680 productos activos, **65.308 con precio**
(76%, desde que se usa `PRECIO_FARMACIA` en vez de `PRECIO_PUBLICO`), 16.623 con
stock, 846 marcas en MAYÚSCULAS. Duración del sync: ~9 min (5,7 lectura Oracle
fila-por-fila + 3,5 INSERT).

---

## 4. ⚡ PRÓXIMO PASO INMEDIATO: poner a andar el workflow

Todo lo de datos está resuelto. Falta el bot en sí. **No hace falta WhatsApp ni
ngrok para esta parte**: el flujo se prueba entero dentro de n8n.

1. **Importar el flujo**: en http://localhost:5678 → Workflows → ⋯ →
   *Import from File* → `n8n\farmar-whatsapp-bot-v2.json` (20 nodos).
2. **Crear las 3 credenciales** (detalle en `n8n\LEEME.md`):
   - **Postgres** → host `postgres` (⚠ NO `localhost`: n8n corre en Docker),
     base `farmar_bot`, usuario y password del `.env`.
   - **Header Auth** para Claude → `x-api-key` con la API key de Anthropic,
     más el header `anthropic-version: 2023-06-01`.
   - **WhatsApp Business Cloud** → recién cuando exista la app de Meta.
3. **Reemplazar** `CAMBIAR_NUMERO_ADMIN_FALLBACK` en el nodo
   *Preparar Alerta Comprador* por un número real.
4. **Probar nodo por nodo** con *Execute Node*, usando los valores de la tabla
   "Datos para probar" de `CONSULTAS_PARA_N8N.md` (código `7798032935096`,
   troquel `4407513`, nombre `geniol`, agotado `2000000032603`).

Cuando el flujo responda bien, recién ahí: app de Meta con su **número de prueba
gratuito** (⚠ nunca registrar un número personal en la API: se pierde el
WhatsApp de ese número), ngrok, y `WEBHOOK_URL` en el `.env`.

---

## 5. Pendientes siguientes

### 5.1 Cargar las asignaciones reales de compradores
Ya está resuelto el matching: `proveedores` tiene las **846 marcas reales** del
catálogo, con el nombre exacto que devuelve Oracle en MAYÚSCULAS ("PUIG
ARGENTINA", "BAGO", "ROCHE"). Hoy **todas** apuntan al comprador de prueba.

Falta limpiar `datos/compradores_por_laboratorio.csv` (361 filas con `#N/A`, 326
vacías, y diferencias de escritura tipo `ABBOT`/`ABBOTT`) y cargar la asignación
real de cada comprador. Ver marcas disponibles:
`SELECT DISTINCT marca_proveedor FROM productos ORDER BY 1;`

### 5.2 Cambiar las contraseñas placeholder ⚠
`POSTGRES_PASSWORD` sigue siendo `cambiar-esta-password-tambien` en **tres lugares
que deben mantenerse sincronizados**:
- `.env` (raíz del proyecto)
- `ConsultasOracle\config.py`
- La base viva: la imagen de Postgres solo lee el env al PRIMER init del volumen,
  así que además hay que correr:
  `docker exec -it farmar_postgres psql -U farmar_admin -d farmar_bot -c "ALTER USER farmar_admin PASSWORD 'nueva';"`

### 5.3 Exponer n8n con HTTPS (README §3)
`ngrok http 5678` → copiar URL → pegarla en `WEBHOOK_URL` del `.env` →
`docker compose up -d n8n`. (El plan gratuito de ngrok cambia la URL en cada reinicio.)

### 5.4 App de Meta (README §4 — 100% manual en developers.facebook.com)
Crear app Business → producto WhatsApp → anotar Phone Number ID / WABA ID /
Access Token → configurar webhook con URL de ngrok + Verify Token inventado →
suscribirse al campo `messages`. Token y Phone Number ID se cargan EN N8N
(credencial Header Auth + URL de Graph API), no en el .env.

### 5.5 Programar el sync cada hora
Comando exacto (PowerShell, como administrador si hace falta):

    schtasks /create /tn "Sync Stock Farmar" /tr "\"C:\Users\BACKUP-FCIA\Desktop\random\n8n-bot-farmacia\ConsultasOracle\sync_stock.bat\"" /sc hourly /st 00:00

Cada corrida tarda ~9 min y reemplaza la tabla entera dentro de una transacción,
así que el bot nunca ve la tabla vacía ni a medias. Los errores quedan en
`ConsultasOracle\logs\sync_stock.log`. La PC tiene que estar prendida y con
Docker Desktop corriendo, porque el destino es el Postgres del contenedor.

### 5.6 Limpieza menor
- Borrar `_archivos_viejos\` (duplicados) y el cascarón `C:\Users\BACKUP-FCIA\ConsultasOracle`.
- Borrar los volúmenes Docker viejos, que quedaron como respaldo del renombre:
  `scarpparafarmalifeysdin_postgres_data` y `scarpparafarmalifeysdin_n8n_data`
  (más los `n8n-bot-farmacia_*`, que nunca tuvieron datos).
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
