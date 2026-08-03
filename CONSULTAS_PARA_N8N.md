# Consultas SQL para los nodos Postgres de n8n

Todas probadas contra los datos reales el 2026-08-03 (n8n 2.28.7). Los tiempos
indicados son los medidos sobre las 85.680 filas del catálogo.

---

## 0. Configurar la credencial de Postgres en n8n

En n8n: **Credentials → New → Postgres**.

| Campo | Valor | Ojo |
|---|---|---|
| Host | `postgres` | ⚠ **NO** `localhost`. n8n corre dentro de Docker y ve a la base por el nombre del servicio de `docker-compose.yml`. |
| Database | `farmar_bot` | |
| User | el `POSTGRES_USER` del `.env` | |
| Password | el `POSTGRES_PASSWORD` del `.env` | |
| Port | `5432` | |
| SSL | Disable | Es una red interna de Docker. |

---

## Cómo pasar parámetros (importante)

En el nodo **Postgres → Execute Query**, usá `$1`, `$2`… en el SQL y cargá los
valores en **Query Parameters** (separados por coma), con expresiones de n8n:

```
Query:            SELECT ... WHERE numero_whatsapp = $1
Query Parameters: {{ $json.from }}
```

⚠️ **Nunca armes el SQL concatenando texto que venga del mensaje de WhatsApp
ni de la respuesta del LLM.** Si el LLM devuelve el término de búsqueda, pasalo
como parámetro; si le dejás escribir el SQL entero, cualquiera que le mande un
mensaje al bot puede borrar la base. El LLM decide *qué buscar*; el SQL es fijo.

---

## 1. Validar que el número está autorizado

Primer nodo después del Webhook. Si no devuelve filas, cortar el flujo.

```sql
SELECT id, nombre_farmacia
FROM farmacias_autorizadas
WHERE numero_whatsapp = $1
  AND activo = TRUE;
```

`$1` = número del remitente, formato internacional **sin `+`** (ej: `54XXXXXXXXXX`).
El webhook de WhatsApp lo manda en `entry[0].changes[0].value.messages[0].from`,
ya en ese formato.

*8 ms · devuelve 0 filas si no está autorizado.*

---

## 2. Buscar por código (barras, farmacia o troquel)

Una sola consulta que cubre las tres formas en que una farmacia identifica un
producto. Devuelve también los que están sin stock, con el estado explícito.

```sql
SELECT nombre,
       marca_proveedor,
       stock,
       precio,
       CASE WHEN stock > 0 THEN 'DISPONIBLE' ELSE 'SIN STOCK' END AS estado
FROM productos
WHERE codigo_barra = $1
   OR codigo_farmacia = $1
   OR troquel = $1
LIMIT 5;
```

`$1` = el código, como texto.

*16 ms · Sirve tanto para EAN (`7798032935096`) como para troquel (`4407513`).*

---

## 3. Buscar por nombre parcial, ordenado por relevancia

Para cuando la farmacia escribe el nombre en lugar de un código. Usa el índice
trigram: tolera errores de tipeo y ordena por parecido.

```sql
SELECT nombre,
       marca_proveedor,
       stock,
       precio,
       round(similarity(nombre, $1)::numeric, 3) AS score
FROM productos_disponibles
WHERE nombre % $1
ORDER BY similarity(nombre, $1) DESC, stock DESC
LIMIT 5;
```

`$1` = el texto buscado (ej: `geniol`). El operador `%` es de `pg_trgm`: filtra
por similitud, no por coincidencia exacta.

Resultado real para `geniol`:

```
GENIOL 1 GR COMP. X8       ELEA - OTC  stock=49381  $3.093,43  score=0.368
GENIOL FLEX COMP. X10      ELEA - OTC  stock=1782   $4.881,76  score=0.333
GENIOL 500 MG COMP. X16    ELEA - OTC  stock=19411  $5.233,72  score=0.304
```

*15 ms · Si querés resultados más laxos, bajá el umbral con
`SET pg_trgm.similarity_threshold = 0.2;` antes de la consulta.*

⚠️ Consulta `productos_disponibles` (solo lo que tiene stock). Si preferís
mostrar también lo agotado, cambiá a `productos`.

---

## 4. Ofrecer equivalentes cuando no hay stock

Cuando el producto pedido está agotado, busca otros con el **mismo principio
activo** que sí tengan stock. Es la respuesta más útil que puede dar el bot.

```sql
SELECT d.nombre,
       d.marca_proveedor,
       d.stock,
       d.precio
FROM productos p
JOIN productos_disponibles d ON d.monodroga = p.monodroga
WHERE p.codigo_barra = $1
  AND p.monodroga IS NOT NULL
  AND d.id <> p.id
ORDER BY d.stock DESC
LIMIT 5;
```

`$1` = código de barras del producto que se pidió y no hay.

Resultado real (IBUPIRAC FEM, sin stock):

```
IBUCLER FEM COMP.X8   MONSERRAT   stock=263   $3.650,00
```

*6 ms · Solo funciona con medicamentos: `monodroga` está cargada en ~22% del
catálogo (18.587 productos). Para perfumería y cosmética devuelve vacío.*

---

## 5. A qué comprador derivar el pedido

```sql
SELECT c.nombre,
       c.numero_whatsapp
FROM proveedores pr
JOIN compradores c ON c.id = pr.comprador_id
WHERE pr.nombre_marca = $1
  AND c.activo = TRUE;
```

`$1` = la marca del producto, **exactamente** como viene en
`productos.marca_proveedor` (en MAYÚSCULAS, ej: `SAVANT PHARM`).

*0 ms · Hoy las 846 marcas apuntan al comprador de prueba. Si la marca no tiene
comprador asignado devuelve 0 filas: conviene manejar ese caso en el flujo.*

---

## 6. Consulta combinada (producto + comprador en un solo paso)

Ahorra un nodo: trae el producto y a quién derivarlo de una vez.

```sql
SELECT p.nombre,
       p.marca_proveedor,
       p.stock,
       p.precio,
       CASE WHEN p.stock > 0 THEN 'DISPONIBLE' ELSE 'SIN STOCK' END AS estado,
       c.nombre          AS comprador,
       c.numero_whatsapp AS comprador_whatsapp
FROM productos p
LEFT JOIN proveedores pr ON pr.nombre_marca = p.marca_proveedor
LEFT JOIN compradores c  ON c.id = pr.comprador_id
WHERE p.codigo_barra = $1
   OR p.codigo_farmacia = $1
   OR p.troquel = $1
LIMIT 1;
```

---

## Estructura sugerida del flujo

```
Webhook (POST)
   └─ Postgres: consulta 1 (whitelist)
        ├─ IF sin filas → cortar (no responder)
        └─ IF autorizada
             └─ AI Agent / LLM: extraer qué producto busca y en qué formato
                  ├─ si es código   → consulta 2 o 6
                  └─ si es nombre   → consulta 3
                       └─ IF stock = 0 → consulta 4 (equivalentes)
                            └─ HTTP Request: responder por Graph API
                                 └─ (si es pedido) consulta 5 → avisar al comprador
```

**Recomendación de costo:** consolidá todo en **un solo mensaje de respuesta**
(stock + precio + alternativas). Desde el 1-oct-2026 Meta cobra cada mensaje
saliente, así que cada mensaje evitado es ahorro directo.

---

## Datos para probar

| Caso | Valor |
|---|---|
| Número autorizado | el cargado en `farmacias_autorizadas` |
| Número no autorizado | `5491100000000` |
| Código de barras con stock | `7798032935096` (FABOGESIC 400) |
| Troquel | `4407513` (BETASERC 16 MG) |
| Nombre parcial | `geniol` |
| Sin stock, con equivalentes | `2000000032603` (IBUPIRAC FEM) |
| Marca para derivación | `SAVANT PHARM` |

Podés probar cada nodo con **Execute Node** en n8n, sin necesidad de WhatsApp
ni de ngrok.
