# Workflow de n8n

`farmar-whatsapp-bot-v2.json` — flujo del bot listo para importar (19 nodos).

Parte del workflow original (armado el 2026-07-06, que quedó en `Downloads` y
**nunca llegó a importarse**) y lo actualiza al esquema actual de la base.

## Cómo importarlo

En n8n: **Workflows → ⋯ → Import from File** y elegir el JSON.

## Credenciales que hay que crear

| Nodo | Credencial | Datos |
|---|---|---|
| Los 4 nodos Postgres | **Postgres** | Host `postgres` (⚠ no `localhost`: n8n corre en Docker), base `farmar_bot`, usuario y password del `.env`, puerto 5432, SSL disable |
| `Clasificar con IA` | **Header Auth** | Name: `x-goog-api-key` · Value: tu API key de Google AI Studio |
| Los 4 nodos WhatsApp | **WhatsApp Business Cloud** | Access Token y Phone Number ID de la app de Meta |

## Qué se corrigió respecto de la versión original

| Nodo | Problema | Estado |
|---|---|---|
| `Buscar Stock` | Usaba la columna `codigo`, que ya no existe | ✅ Ahora busca por `codigo_barra`, `codigo_farmacia` y `troquel`, o por nombre con similitud trigram |
| `Buscar Comprador Asignado` | Hacía join por `compradores.marca_proveedor_asignada`, columna eliminada | ✅ Join por `proveedores.comprador_id → compradores.id` |
| `Clasificar con Claude` | El system prompt era un placeholder literal | ✅ Prompt completo, con el formato JSON de salida y las reglas de derivación |
| `Traer Marcas Activas` | Inyectaba las 846 marcas en el prompt de **cada** mensaje | ✅ Eliminado. La marca se resuelve por SQL |
| `Formatear Respuesta Stock` | Mostraba `$null` cuando el producto no tiene precio | ✅ Muestra "precio a confirmar"; separa disponibles de agotados |

Sobre las marcas: eran ~10 KB de texto extra por mensaje. A 43.500 mensajes/mes
el gasto de tokens se disparaba sin aportar precisión.

## Consultas verificadas

Probadas con `PREPARE`/`EXECUTE` contra los datos reales (2026-08-03):

| Caso | Entrada | Resultado |
|---|---|---|
| Nombre parcial | `geniol` | 5 productos, disponibles primero, el agotado al final |
| Código de barras | `7798032935096` | FABOGESIC 400 — 71.902 u. — $3.999,00 |
| Troquel | `4407513` | BETASERC 16 MG (ABBOTT) — 5 u. |
| Producto agotado | `2000000032603` | IBUPIRAC FEM, estado `SIN_STOCK` |
| Inexistente | `inventadoxyz` | 0 filas → el bot responde que no lo encontró |

## Pendientes antes de usarlo

- [ ] Reemplazar `CAMBIAR_NUMERO_ADMIN_FALLBACK` en el nodo `Preparar Alerta
      Comprador` por un número real de administración.
- [ ] Cargar las tres credenciales de la tabla de arriba.
- [ ] Configurar el Verify Token del nodo Webhook (tiene que coincidir con el
      que se cargue en developers.facebook.com).
- [ ] Probar cada nodo con **Execute Node** antes de conectar WhatsApp.

## Mejora posible: productos equivalentes

Cuando un producto está agotado se le puede ofrecer otro con el mismo principio
activo. La consulta está probada y documentada en
[`../CONSULTAS_PARA_N8N.md`](../CONSULTAS_PARA_N8N.md) (sección 4). Requiere
agregar un nodo Postgres más después de `Buscar Stock`, condicionado a que no
haya disponibles. Solo aplica a medicamentos (~22% del catálogo tiene
`monodroga` cargada).

## Nodos WhatsApp: parámetro renombrado

El workflow original traía el destinatario bajo `recipientPhone`, nombre que
usaba una versión anterior del nodo. n8n 2.28.7 espera **`recipientPhoneNumber`**,
y por eso los 4 nodos daban *"Parameter Recipient's Phone Number is required"* y
el flujo no arrancaba. Ya está corregido en el JSON.

Destinatario de cada uno:

| Nodo | Le escribe a | Expresión |
|---|---|---|
| `Enviar Rechazo` | la farmacia no autorizada | `$('Extraer Datos Mensaje').item.json.from` |
| `Enviar Respuesta Farmacia` | la farmacia | `$('Parsear JSON Claude').item.json.numero_from` |
| `Enviar Alerta Comprador` | el comprador | `$json.comprador_numero` |
| `Avisar Derivación a Farmacia` | la farmacia | `$('Preparar Alerta Comprador').item.json.farmacia_numero` |

El último tenía además un error propio: usaba `$json.farmacia_numero`, pero como
va *después* de `Enviar Alerta Comprador`, su `$json` es la respuesta de la API
de WhatsApp y ese campo no existe. Ahora referencia el nodo explícitamente.

Falta completar `phoneNumberId` (hoy `CAMBIAR_PHONE_NUMBER_ID`) con el Phone
Number ID de la app de Meta.


## Motor de IA: Google Gemini (gratis para pruebas)

El nodo `Clasificar con IA` (antes *Clasificar con Claude*) apunta a la API de
Gemini, que tiene un tier gratuito suficiente para el piloto (~1.500 requests
por día, sin tarjeta).

### Conseguir la API key

1. Entrar a **https://aistudio.google.com/apikey** con una cuenta de Google.
2. **Create API key** → copiarla.

### Cargarla en n8n

Crear una credencial **Header Auth** (no la de Google predefinida):

| Campo | Valor |
|---|---|
| Name | `x-goog-api-key` |
| Value | la API key |

Y asignarla al nodo `Clasificar con IA`. Poner la key como header, no como
`?key=` en la URL: así no queda escrita en los logs de ejecución.

### Detalles del pedido

- **Modelo**: `gemini-3.5-flash-lite` (en la URL). Está pensado justo para esto:
  clasificación y extracción de datos de alto volumen con baja latencia y costo.
  ⚠ **`gemini-2.0-flash` fue retirado el 2026-03-03**; si ves errores raros,
  lo primero a revisar es que el modelo de la URL siga vigente.
- **`responseMimeType: "application/json"`** fuerza a que la respuesta sea JSON
  válido, que es justo lo que necesita el nodo siguiente.
- El parser (`Parsear JSON IA`) lee `candidates[0].content.parts[0].text`, y
  mantiene compatibilidad con el formato de Anthropic (`content[0].text`) por si
  se vuelve a Claude más adelante. Si la respuesta no se puede parsear, marca
  `requiere_humano: true` en vez de romper el flujo.

### Volver a Claude

Cambiar la URL a `https://api.anthropic.com/v1/messages`, el body al formato
`{model, max_tokens, system, messages}` y la credencial a `x-api-key` más el
header `anthropic-version: 2023-06-01`. El parser ya contempla ambos formatos.


## Si aparece "The service is receiving too many requests" (429)

El free tier de Gemini permite del orden de **15 requests por minuto** y 1.500
por día. Un 429 puede venir de tres lados:

1. **Modelo retirado o inexistente** en la URL. Verificá qué modelos habilita tu
   API key:

       curl -s "https://generativelanguage.googleapis.com/v1beta/models" -H "x-goog-api-key: TU_API_KEY"

2. **Ráfaga de pruebas**: ejecutar el nodo muchas veces seguidas satura los
   15 RPM. El nodo ya tiene **3 reintentos con 5 s de espera**, así que se
   recupera solo de los picos.
3. **Cuota diaria agotada** (1.500/día): hay que esperar al reset o pasar a
   tier pago.

Para el volumen del piloto (145 farmacias × pocas consultas/día) el free tier
alcanza sobrado; el límite molesta solo mientras se prueba a mano.


## Prueba end-to-end (2026-08-03) — el flujo funciona

Con los 4 nodos de WhatsApp desactivados y datos pineados en el Webhook
(`datos_prueba_webhook.json`), el mensaje *"hola, necesito 10 cajas de geniol
500"* recorrió el flujo completo:

| Nodo | Resultado |
|---|---|
| `Extraer Datos Mensaje` | `from=543795357760`, texto del mensaje |
| `Validar Whitelist` | autorizada — *Farmacia de Prueba* |
| `Clasificar con IA` | `intencion=pedido`, `termino_busqueda="geniol 500"`, `cantidad_solicitada=10`, `requiere_humano=false` |
| `Buscar Stock` | 5 productos, disponibles primero |
| `Formatear Respuesta Stock` | un único mensaje consolidado |

Respuesta generada:

```
Disponible:
- GENIOL 500 MG COMP. X16 | 19411 u. | $5.233,72
- GENIOL 500 MG COMP. X64 EXPEND. | 4 u. | $19.717,48
- GENIOL COMP.EXPEND 50 BL 500 MG -8457 | 43 u. | $123.234,25
- GENIOL 1 GR COMP. X8 | 49381 u. | $3.093,43
- GENIOL 1G COMP. X56 | 133 u. | $20.088,85
```

> En el panel de n8n ese campo se ve con `\n` escapados: es solo cómo n8n
> muestra el string. El contenido real tiene saltos de línea y así llega a
> WhatsApp.

### El clasificador, probado aparte

Cuatro mensajes contra la API de Gemini:

| Mensaje | Clasificación |
|---|---|
| "necesito 10 cajas de geniol 500" | `pedido` · término `geniol 500` · cantidad 10 |
| "tenes el 7798032935096?" | `consulta_stock` · código detectado |
| "buen dia!" | `saludo` |
| "hay un error en mi factura" | `otro` · **requiere_humano** · motivo: reclamo de factura |

## Defectos encontrados y corregidos

| Nodo | Defecto | Origen |
|---|---|---|
| `Formatear Respuesta Stock` | Saltos de línea reales donde iban escapes, dejando strings sin cerrar → *"Invalid or unexpected token"* | Introducido al generar el JSON |
| `Enviar Alerta Comprador` | `\n` y comillas escapadas se enviaban literales: los campos de texto de n8n no interpretan escapes | Workflow original |
| Los 4 nodos WhatsApp | Usaban `recipientPhone`; n8n 2.28.7 espera `recipientPhoneNumber` | Workflow original |
| `Avisar Derivación a Farmacia` | Leía `$json.farmacia_numero`, pero va después de un nodo WhatsApp y ese `$json` es la respuesta de la API | Workflow original |
| `Clasificar con IA` | Faltaban `authentication` y `genericAuthType`, sin los cuales n8n no muestra el selector de credencial | Introducido al cambiar a Gemini |

Los cinco nodos Code se validaron con `node --check`.

## Estado: qué falta

Solo la parte de Meta. Ver §4 de `../CONTINUAR_AQUI.md`: crear la app, usar el
número de prueba gratuito, cargar la credencial de WhatsApp, reactivar los 4
nodos y levantar ngrok.
