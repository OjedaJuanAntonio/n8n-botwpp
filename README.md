# Bot de WhatsApp para las farmacias Farmar — Entorno local de desarrollo

Este repo contiene **solo la infraestructura** para levantar n8n + la base
de datos de negocio en local. El workflow del bot (nodos, lógica, mensajes)
se arma a mano en la interfaz visual de n8n — no está versionado acá.

Estás corriendo en **Windows con Git Bash** (sin WSL2) y la base de datos
de negocio elegida es **PostgreSQL**.

## Contenido

```
.
├── docker-compose.yml   # n8n + Postgres
├── .env.example         # plantilla de variables de entorno
├── sql/init.sql         # esquema + datos de ejemplo (farmacias, productos, proveedores, compradores)
├── setup.sh             # script de arranque (Docker, .env, docker compose up, healthcheck)
├── ConsultasOracle/     # sync del catálogo: lee Oracle (solo lectura) y reemplaza la tabla productos
├── CONTINUAR_AQUI.md    # estado actual del proyecto y próximos pasos
├── BITACORA_COMPLETA.md # cronología de todo lo hecho, con decisiones y errores resueltos
└── README.md            # este archivo
```

---

## 0. Primera configuración (después de clonar)

Este repo **no incluye credenciales**. Antes de levantar nada, creá los dos
archivos de configuración a partir de sus plantillas y completalos:

```bash
cp .env.example .env
cp ConsultasOracle/config.py.example ConsultasOracle/config.py
```

- `.env` → usuario/password de n8n, credenciales de Postgres y `WEBHOOK_URL`.
- `ConsultasOracle/config.py` → credenciales de Oracle y las mismas de Postgres
  que pusiste en el `.env` (tienen que coincidir).

Ambos están en `.gitignore`: nunca los subas al repositorio.

---

## 1. Requisitos previos

- **Docker Desktop para Windows**, instalado y corriendo (el ícono de la
  ballena en la bandeja del sistema tiene que decir "Running").
  Descarga: https://www.docker.com/products/docker-desktop/
- **Git Bash** (ya lo tenés, es el shell donde corrés estos comandos).

`setup.sh` verifica esto automáticamente y te avisa si falta algo.

---

## 2. Cómo correr setup.sh

Desde Git Bash, parado en esta carpeta:

```bash
chmod +x setup.sh   # solo la primera vez, para que sea ejecutable
./setup.sh
```

El script:

1. Verifica que Docker y `docker compose` estén disponibles y corriendo.
2. Copia `.env.example` → `.env` **solo si `.env` no existe todavía**
   (nunca pisa un `.env` que ya tengas configurado).
3. Levanta los contenedores con `docker compose up -d`.
4. Espera (polling) a que n8n responda en `http://localhost:5678`.
5. Te muestra la URL de acceso y las credenciales.

**Antes de correrlo por primera vez**, o justo después, abrí el archivo
`.env` y completá al menos:

- `N8N_BASIC_AUTH_USER` / `N8N_BASIC_AUTH_PASSWORD` (con qué usuario/clave
  vas a entrar a la interfaz de n8n).
- `POSTGRES_USER` / `POSTGRES_PASSWORD` / `POSTGRES_DB` (credenciales de la
  base de negocio).
- `WEBHOOK_URL` la vas a completar **después** de levantar ngrok/Cloudflare
  Tunnel (paso 3). Al principio podés dejar el placeholder.

### Comandos útiles después de levantado

```bash
docker compose ps              # ver estado de los contenedores
docker compose logs -f n8n     # logs de n8n en vivo
docker compose logs -f postgres
docker compose down            # apaga los contenedores (los datos persisten)
docker compose down -v         # apaga y BORRA los volúmenes (datos y sql/init.sql se re-ejecutan de cero)
```

> `sql/init.sql` solo se ejecuta automáticamente la **primera vez** que se
> crea el volumen de Postgres. Si lo modificás después y querés que se
> vuelva a aplicar, tenés que borrar el volumen con `docker compose down -v`
> (esto borra todos los datos de la base de negocio, no los workflows de n8n
> que viven en el volumen `n8n_data`, que es independiente).

---

## 3. Exponer n8n a internet con HTTPS (ngrok o Cloudflare Tunnel)

WhatsApp Cloud API **exige que el webhook sea HTTPS con certificado válido**
y **no acepta `localhost`**. Necesitás un túnel público hacia tu puerto 5678.

### Opción A: ngrok (más simple para desarrollo)

1. Creá una cuenta gratis en https://ngrok.com/ y conseguí tu authtoken
   desde el dashboard.
2. Instalación en Windows:
   - Con [Chocolatey](https://chocolatey.org/): `choco install ngrok`
   - O descargá el `.zip` desde https://ngrok.com/download y agregá el
     ejecutable a tu PATH.
3. Configurá el authtoken una sola vez:
   ```bash
   ngrok config add-authtoken TU_AUTHTOKEN
   ```
4. Con los contenedores levantados (`./setup.sh` ya corrido), abrí otra
   terminal y ejecutá:
   ```bash
   ngrok http 5678
   ```
5. ngrok te va a mostrar una URL tipo `https://abcd-1234.ngrok-free.app`.
   Copiala.
6. Pegá esa URL en tu `.env` en la variable `WEBHOOK_URL` (con `/` al
   final) y reiniciá n8n para que tome el cambio:
   ```bash
   docker compose up -d n8n
   ```

**Importante:** en el plan gratuito de ngrok, la URL cambia cada vez que
reiniciás el túnel. Vas a tener que repetir el paso 6 y también actualizar
la URL del webhook en developers.facebook.com cada vez que la URL cambie
(a menos que pagues un plan con subdominio fijo).

### Opción B: Cloudflare Tunnel (URL estable, gratis, requiere dominio en Cloudflare)

1. Instalá `cloudflared`:
   - Con Chocolatey: `choco install cloudflared`
   - O descargá el binario desde
     https://github.com/cloudflare/cloudflared/releases
2. Si ya tenés un dominio en Cloudflare, autenticate y creá un túnel:
   ```bash
   cloudflared tunnel login
   cloudflared tunnel create n8n-bot
   cloudflared tunnel route dns n8n-bot n8n.tu-dominio.com
   cloudflared tunnel run --url http://localhost:5678 n8n-bot
   ```
3. Tu webhook quedaría en `https://n8n.tu-dominio.com`, fijo (no cambia al
   reiniciar), lo cual es más cómodo que ngrok a largo plazo.
4. Actualizá `WEBHOOK_URL` en `.env` y reiniciá n8n como en el paso 6 de ngrok.

Para desarrollo rápido y sin dominio propio, **usá ngrok**. Si esto va a
producción o lo vas a dejar corriendo por semanas, conviene Cloudflare Tunnel.

---

## 4. Pasos MANUALES en developers.facebook.com (WhatsApp Cloud API)

**Esto no se puede automatizar por API/CLI.** Requiere crear la app y
generar credenciales desde la interfaz web de Meta, usando tu cuenta
personal de Facebook Business Manager — no existe una API pública para
"crear una app de WhatsApp Business" de cero sin pasar por la consola web.
Hacé esto una sola vez:

1. Entrá a https://developers.facebook.com/ y logueate con tu cuenta.
2. **Mis Apps → Crear app**. Elegí el tipo "Business" (o "Otro" según la
   versión de la consola) y asignala a tu Business Manager.
3. Dentro de la app, en el panel de productos, agregá **WhatsApp**
   ("Configurar" sobre el producto WhatsApp).
4. En la sección **WhatsApp → Configuración de la API (API Setup)**
   vas a encontrar:
   - **Phone Number ID**: identificador del número de prueba (o el tuyo
     si ya migraste un número real). Anotalo — va en n8n, no en `.env`.
   - **WhatsApp Business Account ID (WABA ID)**: identificador de la
     cuenta de negocio.
   - **Access Token temporal**: válido por 24hs, sirve para probar ya
     mismo. Para producción vas a necesitar generar un **token permanente**
     (System User + permisos `whatsapp_business_messaging` y
     `whatsapp_business_management`, desde Business Settings → System Users).
5. **Configurar el Webhook** (en la misma sección de WhatsApp, o en
   "Configuration" del producto):
   - **Callback URL**: la URL HTTPS de ngrok/Cloudflare Tunnel + el path
     del nodo Webhook que crees en n8n, ej:
     `https://abcd-1234.ngrok-free.app/webhook/whatsapp-in`
   - **Verify Token**: un string que **vos inventás** (ej: una password
     random). Tiene que coincidir exactamente con el que configures en el
     nodo Webhook de n8n (n8n necesita responder al challenge GET de Meta
     devolviendo ese mismo token).
   - Suscribite al campo **`messages`** para recibir los mensajes entrantes.
6. Con el Phone Number ID + Access Token, en n8n vas a:
   - Crear una credencial (Header Auth) con el Access Token para el nodo
     HTTP Request que envía respuestas vía Graph API
     (`https://graph.facebook.com/v20.0/<PHONE_NUMBER_ID>/messages`).
   - Crear el nodo Webhook que recibe los mensajes entrantes, usando el
     Verify Token del paso anterior.

Anotá estos valores en algún lugar seguro (gestor de contraseñas, no en
texto plano en el repo). El `.env.example` tiene comentarios recordatorio
de qué dato va en cada lado, pero **no se leen desde docker-compose** —
se pegan directamente en las credenciales/nodos de n8n.

---

## 5. Acceder a n8n

Una vez que `./setup.sh` termina OK:

- **URL local:** http://localhost:5678
- **URL pública (para el webhook de Meta):** la que te dio ngrok/Cloudflare
  Tunnel, la misma que pusiste en `WEBHOOK_URL` dentro de `.env`.
- **Usuario:** el valor de `N8N_BASIC_AUTH_USER` en tu `.env`.
- **Contraseña:** el valor de `N8N_BASIC_AUTH_PASSWORD` en tu `.env`.

La base de datos de negocio (Postgres) se conecta desde el nodo **Postgres**
de n8n con:

- **Host:** `postgres` si te conectás desde dentro de la red de Docker
  (que es como lo va a ver n8n, porque comparten la misma red de
  `docker-compose.yml`), o `localhost` si te conectás desde una herramienta
  externa (DBeaver, pgAdmin, psql) corriendo en tu Windows.
- **Puerto:** el valor de `POSTGRES_PORT` en `.env` (por defecto `5432`).
- **Usuario / Password / Database:** los valores de `POSTGRES_USER` /
  `POSTGRES_PASSWORD` / `POSTGRES_DB` en `.env`.

---

## 6. El sync del catálogo (carpeta `ConsultasOracle/`) — pieza obligatoria

El stock y los precios reales viven en el **Oracle del sistema comercial** (base
de reportes `DW`, esquema `DW_SCO`). n8n **no puede consultarla directamente**:
es un Oracle 10g y ningún driver moderno lo soporta (el detalle de por qué está
en `ConsultasOracle/CONTEXTO_DEL_PROYECTO.md`).

Por eso existe esta carpeta: **consulta Oracle y clona el catálogo a Postgres**,
que sí es una base compatible con el nodo nativo de n8n. Sin este paso el bot no
tiene datos que responder.

```
Oracle 10g (DW)  --[ solo lectura, ADODB/MSDAORA, Python 32 bits ]-->  sync_stock.py
                                                                            |
                                              TRUNCATE + INSERT en 1 transacción
                                                                            v
                                        Postgres (tabla productos)  <--  nodo Postgres de n8n
```

Puntos clave:

- La consulta que define qué se trae está en `ConsultasOracle/consultas_sql/stock_sync.sql`.
  Los **alias de sus columnas deben coincidir exactamente** con los nombres de
  columna de la tabla `productos` en Postgres.
- El Oracle se usa **solo en modo lectura**. Nunca se escribe ahí: es un data
  warehouse que se regenera desde el sistema comercial.
- Todo el reemplazo ocurre en **una sola transacción**, así que el bot nunca ve
  la tabla vacía ni a medias. Si Oracle falla, Postgres no se toca y quedan los
  datos de la corrida anterior.
- Se ejecuta con `sync_stock.bat` y está pensado para programarse cada hora con
  el Programador de Tareas de Windows.
- Requiere el **Python de 32 bits** (`C:\Python312-32`) con `pywin32`, `openpyxl`
  y `pg8000` instalados.

---

## 7. Opcional: skills de n8n para Claude Code

Si querés ayuda contextual de Claude mientras armás el workflow a mano en
la interfaz de n8n, existe el plugin de terceros
[`czlonkowski/n8n-skills`](https://github.com/czlonkowski/n8n-skills), que
agrega 14 skills sobre expresiones, nodos, validación, etc., apoyado en el
servidor MCP `n8n-mcp`. No lo instalé automáticamente porque:

- Es código de terceros que instala **hooks** que se ejecutan solos en
  futuras sesiones — conviene revisarlo antes de confiar en él.
- Requiere configurar primero el servidor MCP `n8n-mcp` en tu `.mcp.json`.

Si lo querés instalar, desde una sesión interactiva de Claude Code corré:

```
/plugin install czlonkowski/n8n-skills
```

y seguí las instrucciones del propio repo para configurar `n8n-mcp` como
prerequisito.
