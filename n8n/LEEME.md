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
| `Clasificar con Claude` | **Header Auth** | Name: `x-api-key` · Value: tu API key de Anthropic. Agregar también el header `anthropic-version: 2023-06-01` |
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
