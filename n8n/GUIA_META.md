# Guía: conectar el bot a WhatsApp (Meta Cloud API)

Paso a paso, verificado contra `farmar-whatsapp-bot-v2.json`. Es la última pieza
que falta: la lógica del bot ya está probada.

---

## Antes de empezar: instalar ngrok

Meta exige un webhook **HTTPS público**; no acepta `localhost`.

1. Crear cuenta gratis en https://ngrok.com y copiar el authtoken del dashboard.
2. Instalar en Windows (elegir una):
   - Chocolatey: `choco install ngrok`
   - O bajar el .zip de https://ngrok.com/download y poner el .exe en el PATH.
3. Configurar el token una sola vez:

       ngrok config add-authtoken TU_AUTHTOKEN

4. Con los contenedores levantados, en una terminal aparte:

       ngrok http 5678

   Deja esa terminal abierta. Te da una URL tipo
   `https://abcd-1234.ngrok-free.app`.

> ⚠ En el plan gratuito la URL **cambia cada vez que reiniciás ngrok**, y hay
> que actualizarla en Meta y en el `.env`. Si esto va a quedar corriendo,
> conviene Cloudflare Tunnel (URL fija) — ver README §3.

---

## Paso 1 — Crear la app en Meta

1. Entrar a https://developers.facebook.com con tu cuenta.
2. **My Apps → Create App**.
3. Tipo: **Business**. Poner nombre y email, y asociarla a tu Business Manager.
4. Ya dentro de la app: **Add Product → WhatsApp → Set Up**.

Al agregar el producto, Meta crea automáticamente una **WABA de prueba** y un
**número de prueba gratuito**. No hace falta ningún número propio.

---

## Paso 2 — Anotar credenciales

En el menú izquierdo: **WhatsApp → API Setup**. Ahí están:

| Dato | Para qué sirve |
|---|---|
| **Phone Number ID** | Va en los 4 nodos WhatsApp (reemplaza `CAMBIAR_PHONE_NUMBER_ID`) |
| **WhatsApp Business Account ID** | Referencia, no se usa en el workflow |
| **Access token** (botón *Generate*) | Va en la credencial de n8n. ⚠ El temporal **dura 24 h** |

> Para producción hay que generar un token permanente: Business Settings →
> System Users → crear uno con permisos `whatsapp_business_messaging` y
> `whatsapp_business_management`.

---

## Paso 3 — Habilitar los destinatarios de prueba

El número de prueba **solo puede escribirle a números verificados** (hasta 5).

En la misma pantalla de API Setup, en el campo **To** → *Manage phone number
list* → agregar el número del piloto. Llega un código por WhatsApp a ese número
para confirmarlo.

Sin este paso, el bot no le puede responder a nadie.

---

## Paso 4 — Configurar el webhook

1. En n8n, abrir el nodo **`Es Verificación Meta?`** y reemplazar
   `CAMBIAR_ESTE_VERIFY_TOKEN` por una cadena inventada (cualquier texto
   aleatorio; es una contraseña compartida, no la da Meta).
2. **Guardar y ACTIVAR el workflow** (interruptor arriba a la derecha).
3. En Meta: **WhatsApp → Configuration → Webhook → Edit**:
   - **Callback URL**: `https://TU-URL-NGROK/webhook/whatsapp`
   - **Verify token**: exactamente el mismo del paso 1.
   - **Verify and save**.
4. En **Webhook fields**, suscribirse a **`messages`**.

---

## Los tres errores donde más se traba la gente

**1. Usar la URL de test en lugar de la de producción.** n8n expone dos:

    /webhook-test/whatsapp   → solo mientras apretás "Listen for test event"
    /webhook/whatsapp        → permanente, requiere el workflow ACTIVO

Meta necesita la segunda. Si el workflow está desactivado, la verificación falla.

**2. El challenge tiene que volver crudo.** Meta manda un GET con
`hub.mode`, `hub.verify_token` y `hub.challenge`, y espera que le devuelvas el
challenge **como texto plano, con 200**. Si lo envolvés en JSON, falla.
En este workflow ya está bien: el nodo `Responder Challenge` usa
`respondWith: text` y `responseCode: 200`.

**3. El verify token no coincide.** Tiene que ser idéntico en el nodo
`Es Verificación Meta?` y en el formulario de Meta. Sin espacios de más.

### Probar la verificación sin Meta

Con ngrok corriendo y el workflow activo, simulá el handshake:

    curl "https://TU-URL-NGROK/webhook/whatsapp?hub.mode=subscribe&hub.verify_token=TU_TOKEN&hub.challenge=prueba123"

Tiene que devolver exactamente `prueba123`, sin comillas ni llaves. Si eso
funciona, la verificación en Meta va a funcionar.

---

## Paso 5 — Terminar la configuración en n8n

1. Crear la credencial **WhatsApp Business Cloud** con el Access Token y el
   Phone Number ID.
2. Reemplazar `CAMBIAR_PHONE_NUMBER_ID` en los 4 nodos WhatsApp.
3. Reemplazar `CAMBIAR_NUMERO_ADMIN_FALLBACK` en `Preparar Alerta Comprador`.
4. **Reactivar los 4 nodos WhatsApp** (están desactivados para las pruebas):
   seleccionarlos y apretar `D`.
5. **Quitar el pin de datos** del nodo Webhook, si no n8n va a seguir usando el
   mensaje simulado en vez del real.
6. Actualizar `WEBHOOK_URL` en el `.env` con la URL de ngrok y reiniciar n8n:

       docker compose up -d n8n

---

## Paso 6 — Probar de verdad

Desde el WhatsApp del número que verificaste en el paso 3, escribirle al número
de prueba de Meta:

    hola, tenes geniol 500?

El bot debería responder con la lista de productos y precios. Si no llega nada,
revisar en n8n la pestaña **Executions**: ahí se ve si el webhook entró y en qué
nodo se cortó.

---

## Recordatorio de costos

Hasta el **30 de septiembre de 2026** los mensajes de servicio son gratis.
Desde el 1 de octubre Meta los cobra, y ahí el volumen real de mensajes define
la viabilidad del proyecto. Durante el piloto conviene **medir cuántos mensajes
manda por día cada farmacia**: ese número es el que hay que llevar al
presupuesto. Ver la nota *Costos y viabilidad* en la bóveda.
