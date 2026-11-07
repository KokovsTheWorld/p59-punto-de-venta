# Prompt para Google Stitch — #59 Punto de venta

> **Estado (2026-11-05):** ✅ diseño generado en Google Stitch por el equipo
> (proyecto: ver `design/evidencias/ENLACE.txt`), exportado en `design/stitch/`
> e **integrado** en `priv/www/`. Detalles de la integración en la sección 8.

Contenido original de la plantilla (se conserva):

> Disena la interfaz de: **Punto de venta** (Comercio, finanzas y servicios).
> Contexto: ventas concurrentes, corte de caja y tickets.
> Pantallas minimas: 1. Dashboard principal con el estado en tiempo real.
> 2. Detalle de un elemento (uno de los procesos del dominio). 3. Historial /
> bitacora de eventos y alertas. Requisitos: legible en celular, colores de
> estado (ok / alerta / falla), espanol. Exporta el zip desde Stitch y
> descomprimelo en esta carpeta (`design/`), incluyendo `DESIGN.md`.

---

## 1. Qué hacer (paso a paso)

1. Abre **https://stitch.withgoogle.com** con tu cuenta de Google.
2. Crea un proyecto nuevo llamado **`p59-punto-de-venta`**. Elige el modo
   **Web** (no Mobile): la interfaz debe ser responsiva y se probará en celular
   desde el mismo navegador.
3. Pega el **Prompt maestro** (sección 2) y genera.
4. Para cada pantalla de la sección 3 que no haya salido bien, o que falte,
   pega su **prompt de pantalla** dentro del mismo proyecto. Así se conserva
   el mismo estilo visual.
5. Revisa que existan las **7 pantallas** de la sección 3 y que los textos
   estén en español.
6. Exporta (sección 5) y coloca los archivos en `design/stitch/`.
7. Toma las capturas de evidencia (sección 6).

## 2. Prompt maestro (copiar completo en Stitch)

```text
Diseña una aplicación web responsiva en ESPAÑOL (México) para el punto de venta de una tienda de
abarrotes y artículos generales en Tijuana, B.C., con 4 cajas registradoras que cobran al mismo
tiempo sobre un inventario compartido de 800 productos. Se cobra en pesos (MXN) y dólares (USD) con
tipo de cambio variable, con tarjeta y con pago mixto. Es la demo académica de un backend en
Erlang/OTP: además de cobrar, la interfaz debe hacer VISIBLE la tolerancia a fallos (procesos que
caen y se reinician, terminal bancaria que falla, ventas en revisión).

Estilo: limpio, profesional, de alto contraste, pensado para usarse rápido en mostrador y para
proyectarse en una presentación. Tipografía sans-serif legible; cifras con números tabulares.
Color de acento verde oscuro (#0B6E4F). Fondo gris muy claro, tarjetas blancas con bordes suaves.
Incluye también una variante de modo oscuro.
Estados semánticos SIEMPRE con color + texto (nunca solo color):
  OK = verde "Operando", ALERTA = ámbar "Alerta", FALLA = rojo "Falla".
Montos con formato $1,234.56 (MXN) y US$12.00 (USD). Tipo de cambio con 4 decimales: 18.2000.
Debe funcionar desde 360 px de ancho (celular) hasta escritorio; en celular la navegación pasa a una
barra inferior o menú hamburguesa.

Navegación principal (barra superior en escritorio): Tablero · Cobrar · Corte · Bitácora · Simulación.
En la barra: nombre "Punto de venta #59", indicador de conexión en tiempo real ("En vivo" verde /
"Sin conexión" rojo) y el tipo de cambio vigente.

Pantallas:
1. Tablero en tiempo real.
2. Cobrar (punto de venta de una caja).
3. Detalle de caja (proceso, turno, venta en curso, operaciones recientes).
4. Detalle de venta / ticket (máquina de estados y comprobante).
5. Corte de caja.
6. Bitácora de eventos y alertas.
7. Simulación de fallas (herramientas de la demo).

El ticket es un "COMPROBANTE INTERNO — NO ES CFDI"; no muestres sellos SAT, QR fiscal ni "factura".
```

## 3. Pantallas (prompts por pantalla y contenido requerido)

Usa datos de ejemplo realistas como los de abajo (son los que devuelve la API).

### 3.1 Tablero en tiempo real (`dashboard`)

```text
Pantalla "Tablero en tiempo real". Fila de 8 indicadores (tarjetas KPI): Tickets confirmados (600),
Importe vendido ($763,171.36), Ventas en proceso (2), Cajas activas (4 / 4), Cancelaciones /
devoluciones (9 / 8), Tipo de cambio simulado (18.2000), Terminal bancaria (modo "normal" con
insignia OK; o "falla inyectada" en ámbar), Productos agotados (3, con insignia ámbar "1 descuadre").
Debajo, 4 tarjetas de caja (Caja 1..4) con: semáforo (Operando / Turno cerrado / Cobro en revisión /
Proceso caído), cajero y turno ("Ana · turno 2"), identificador de proceso en monoespaciado
("pid <0.152.0>"), contador de reinicios ("1 reinicio") y la venta en curso (V-000376 · abierta ·
$540.90). Tarjeta clicable que lleva al detalle de la caja.
Abajo, dos columnas: "Últimos eventos" (lista con hora, insignia de nivel y mensaje, p. ej.
"15:04:49 FALLA Caja 3 reiniciada por su supervisor") y "Árbol de supervisión (en vivo)" mostrado
como árbol indentado: p59_punto_de_venta_sup → p59_servicios_sup, p59_almacen, p59_inventario,
p59_sucursal_sup → p59_ventas_sup (ventas V-…), p59_cajas_sup → p59_caja_1..4. Cada nodo con su pid
y una marca roja si está caído.
```

### 3.2 Cobrar (`pos`)

```text
Pantalla "Cobrar" para una caja. Arriba, pestañas Caja 1 | Caja 2 | Caja 3 | Caja 4.
Columna izquierda: buscador de productos ("Buscar por nombre o clave P0001") y lista con nombre,
clave, categoría, existencias disponibles, precio y botón "Agregar"; productos inactivos o agotados
deshabilitados con insignia.
Columna derecha: "Venta V-000123" con insignia de estado (abierta / procesando pago / pendiente de
revisión / pagada / cancelada), tabla de partidas (producto, precio unitario, IVA 0 % o 16 %,
descuento, cantidad, importe, botón quitar), Subtotal, Descuentos, IVA y TOTAL grande.
Panel de pago: campos Efectivo MXN, Efectivo USD y Tarjeta (simulada), botones rápidos "Efectivo
exacto" y "Tarjeta exacta", muestra del cambio calculado en pesos y del tipo de cambio usado.
Botones "Cobrar" (primario) y "Cancelar venta" (peligro).
Estado especial "Pendiente de revisión": banner rojo "La terminal no respondió: no sabemos si se
cobró" con botón "Consultar al banco y resolver". Mensajes de error claros: "Pago insuficiente",
"Tarjeta rechazada", "Sin existencia: otra caja tomó las últimas piezas".
Pie: "Caja 1 · Ana · turno 1 (abierto) · tipo de cambio 18.2000 MXN/USD".
En celular las dos columnas se apilan y el total + botón Cobrar quedan fijos abajo.
```

### 3.3 Detalle de caja (`caja`)

```text
Pantalla "Caja 2" con semáforo. Tarjeta "Proceso": registrado como p59_caja_2, pid, número de
reinicios, supervisor "p59_cajas_sup (one_for_one)". Tarjeta "Turno": número, estado, cajero, fondo
inicial ($1,000.00), hora de apertura. Botones "Ir a cobrar", "Ver corte" y "Simular caída de la
caja" (peligro). Tarjeta "Venta en curso" y tabla "Operaciones recientes" (folio T-000045, tipo
venta/cancelación/devolución, hora, importe; reembolsos en negativo).
```

### 3.4 Detalle de venta y ticket (`venta-ticket`)

```text
Pantalla de detalle de venta "V-000123" con línea de tiempo vertical de la máquina de estados:
abierta → procesando pago → pendiente de revisión → pagada, cada paso con hora y detalle
("Terminal sin respuesta: no se sabe si se cobró", "Confirmada con ticket T-000045").
Al lado, el ticket en formato de impresora térmica (monoespaciado, 44 columnas) con el encabezado
"COMPROBANTE INTERNO — NO ES CFDI", caja, turno, cajero, fecha, partidas, subtotal, IVA, total,
pagos (efectivo USD US$50.00 = $910.00, tipo de cambio 18.2000, cambio $369.10) y autorización de
tarjeta simulada. Panel "Cancelación o devolución": selector de caja, motivo, cantidades a devolver
por partida, botones "Registrar devolución" y "Cancelar ticket completo", y lista de movimientos
posteriores (p. ej. "cancelación C-000003 · turno 2 (original 1) · -$540.90").
```

### 3.5 Corte de caja (`corte`)

```text
Pantalla "Corte de caja". Filtros: Caja (Todas, 1-4), Turno, Cajero, botón Consultar.
Tarjeta "Consolidado (turnos vigentes)" y una tarjeta por caja/turno con insignia "Invariante OK"
(verde) o "NO CUADRA" (rojo). Cada tarjeta muestra: Ventas (75 · $95,366.34), por modalidad (MXN 34 ·
USD 11 · tarjeta 19 · mixto 11), efectivo MXN recibido, dólares recibidos (US$412.00 = $7,498.40),
tarjeta, cambio entregado, cancelaciones, devoluciones, fondo inicial, efectivo esperado
($52,146.82 + US$412.00), efectivo contado, diferencia y venta neta.
Insignia ámbar "Descuadre: -$50.00" cuando el contado no coincide e insignia ámbar
"2 ventas en proceso NO contadas". Formulario "Cerrar turno" (efectivo contado MXN y USD) y botón
"Abrir turno siguiente". Nota al pie con la fórmula del invariante contable.
```

### 3.6 Bitácora (`bitacora`)

```text
Pantalla "Bitácora de eventos y alertas" con filtros por nivel (Todos / OK / Alerta / Falla) y
lista cronológica en tiempo real: hora, insignia de nivel, tipo (venta, terminal, caja, corte,
inventario, caos) y mensaje. Ejemplos: "OK venta Ticket T-000600 confirmado en caja 4 por $1,203.10",
"FALLA terminal Terminal cayó tras cobrar V-000231-1", "ALERTA caja Caja 3 reiniciada por su
supervisor (reinicio #1); venta en curso: V-000376", "ALERTA corte Corte caja 3 turno 1: descuadre
-$50.00 / US$0.00".
```

### 3.7 Simulación de fallas (`simulacion`)

```text
Pantalla "Simulación y fallas inyectadas" (herramientas de la demo, marcada claramente como
simulación). Tarjetas: "Escenarios del problema" con 5 botones (A Terminal cae a mitad del cobro,
B Cancelar ticket del turno anterior, C Reintento de red duplicado, D Pago en dólares con cambio en
pesos, E Corte con ventas en proceso); "Terminal bancaria" con modos (normal, rechazar, fuera de
línea, caída antes de cobro, caída tras cobro, aleatorio); "Impresora" (en línea / atascar);
"Matar procesos" con botones rojos por proceso y "Prueba de caos completa"; "Carga: 4 cajas,
600 tickets" con botón y barra de progreso. Panel "Resultado" con lista de verificaciones ✔/✘
(esperado vs. obtenido).
```

## 4. Conexión con la API Cowboy (para la integración posterior)

La interfaz final se servirá desde `priv/www/` por el mismo servidor Erlang
(sin CORS). La capa de datos ya existe en **`priv/www/js/api.js`** y debe
reutilizarse: al integrar Stitch solo se reemplazan HTML y CSS.

| Pantalla | Lectura | Acciones |
|---|---|---|
| Tablero | `GET /api/estado`, `GET /api/cajas`, `GET /api/eventos?limite=12`, SSE `GET /api/eventos/stream` | — |
| Cobrar | `GET /api/cajas/:id`, `GET /api/productos?q=&pagina=&limite=`, `GET /api/tipo-cambio` | `POST /api/ventas`, `POST /api/ventas/:id/partidas`, `DELETE /api/ventas/:id/partidas/:producto`, `POST /api/ventas/:id/pago`, `POST /api/ventas/:id/revisar`, `POST /api/ventas/:id/cancelar` |
| Caja | `GET /api/cajas/:id` | `POST /api/simulacion/matar` |
| Venta / ticket | `GET /api/ventas/:id`, `GET /api/tickets/:folio` | `POST /api/tickets/:folio/cancelar`, `POST /api/tickets/:folio/devolucion` |
| Corte | `GET /api/corte?caja=&turno=&cajero=` | `POST /api/cajas/:id/turno/cerrar`, `POST /api/cajas/:id/turno` |
| Bitácora | `GET /api/eventos`, SSE `/api/eventos/stream` | — |
| Simulación | `GET /api/estado`, `GET /api/simulacion/carga` | `POST /api/simulacion/{terminal,impresora,matar,caos,carga}`, `POST /api/simulacion/escenarios/:letra` |

Reglas que la UI debe respetar: montos en **centavos enteros** (convertir el texto
"123.45" con `Dinero.aCentavos`, nunca con `parseFloat`); un **`operacion_id`
por intento de cobro**, reutilizado si se reintenta; HTTP 202 en el pago significa
"pendiente de revisión".

## 5. Exportación: qué descargar y dónde ponerlo

1. En Stitch, selecciona todas las pantallas → **Export** → **Download ZIP**
   (o "Code" → descargar por pantalla si tu versión no ofrece ZIP).
2. Descomprime en **`design/stitch/`** de este proyecto, dejando una carpeta por
   pantalla con los nombres de la sección 3:

   ```text
   design/stitch/
   ├── DESIGN.md                (si Stitch lo genera; si no, se crea con la paleta exportada)
   ├── dashboard/   code.html  screen.png
   ├── pos/         code.html  screen.png
   ├── caja/        code.html  screen.png
   ├── venta-ticket/code.html  screen.png
   ├── corte/       code.html  screen.png
   ├── bitacora/    code.html  screen.png
   └── simulacion/  code.html  screen.png
   ```

   Si Stitch nombra las carpetas de otra forma, renómbralas a las de arriba.
3. Guarda el **enlace del proyecto de Stitch** en `design/stitch/ENLACE.txt`.

## 6. Evidencias que debes capturar

Guárdalas en `design/evidencias/`:

- `stitch-proyecto.png`: el lienzo de Stitch con las 7 pantallas visibles y el
  nombre del proyecto.
- `stitch-prompt.png`: el prompt maestro dentro de Stitch.
- Después de la integración: `app-tablero.png`, `app-cobrar-celular.png`
  (modo responsivo del navegador a 390 px), `app-corte.png` y `app-caos.png`
  (tablero justo después de matar una caja).

## 7. Cómo se comprueba que la intervención terminó

```bash
ls design/stitch/*/code.html | wc -l      # debe dar 7
ls design/stitch/*/screen.png | wc -l     # debe dar 7
test -f design/stitch/ENLACE.txt && echo ok
```

Con eso, el siguiente paso (que hace el agente o el equipo) es adaptar cada
`code.html` a `priv/www/`, conectarlo con `js/api.js` y conservar la identidad
visual de Stitch.

## 8. Integración realizada

### 8.1 Exportación recibida

| Carpeta exportada por Stitch | Pantalla | Ruta en la app |
|---|---|---|
| `tablero_en_tiempo_real/` | Tablero en tiempo real | `#/` |
| `cobrar_caja_1/` | Cobrar | `#/cobrar/1` … `#/cobrar/4` |
| `detalle_de_caja_1/` | Detalle de caja | `#/caja/1` … `#/caja/4` |
| `detalle_de_venta_08942/` | Detalle de venta / ticket | `#/venta` (lista) y `#/venta/V-…` |
| `corte_de_caja_arqueo_x_z/` | Corte de caja (arqueo X/Z) | `#/corte[?caja=&turno=&cajero=]` |
| `bit_cora_de_eventos_y_alertas_otp/` | Bitácora | `#/bitacora` |
| `simulaci_n_de_fallas_otp/` | Simulación de fallas | `#/simulacion` |
| `frontera_pos_otp_monitor/DESIGN.md` | Sistema de diseño | `assets/` |

Se conservaron los nombres de carpeta que generó Stitch; la tabla hace la
correspondencia con los nombres propuestos en la sección 5.

### 8.2 Qué se conservó del diseño de Stitch

- **Configuración de Tailwind completa** (paleta de 47 colores, tipografías
  Inter / JetBrains Mono, escala tipográfica, radios y espaciados): se copió tal
  cual a `assets/tailwind.config.js`. Era idéntica en las 7 pantallas.
- Identidad "Frontera POS #59", encabezado con indicador *En vivo* y tipo de
  cambio, navegación de 7 secciones, tarjetas KPI, tarjetas de caja con pid y
  semáforo, insignias de estado con **icono + punto + texto**, ticket térmico de
  80 mm con "COMPROBANTE INTERNO — NO ES CFDI", línea de tiempo del
  `gen_statem`, arqueo con tres gavetas (MXN, USD, tarjeta) y modos X/Z, franja
  de peligro del modo simulación, árbol OTP y consola oscura.
- El **modo oscuro** se implementó con la paleta descrita en `DESIGN.md` (Stitch
  no exportó variantes `dark:`): los colores pasan a variables CSS y el botón
  de tema del encabezado alterna entre ambas.

### 8.3 Qué se adaptó y por qué

Stitch generó contenido de ejemplo que **no corresponde al sistema** o que
sería falso mostrar. Se sustituyó por los datos reales equivalentes:

| En el diseño de Stitch | En la app integrada | Motivo |
|---|---|---|
| Mnesia, "Latencia Mnesia", "disc_copies" | DETS, libro de movimientos | La persistencia real es DETS |
| Erlang/OTP 26 | Erlang/OTP 27 | Versión real |
| "MODO FISCAL ACTIVO", RFC, "IVA fronterizo 8 %" fijo | "Demo · comprobantes sin validez fiscal"; IVA según configuración | No hay integración fiscal; el 8 % es configurable y por verificar |
| Báscula, lector USB, teclas F2–F12, Verifone/PAX | Buscador y catálogo real (800 productos) | Hardware no simulado |
| Firmas con PIN, "Imprimir corte Z" | Cierre de turno real con efectivo contado | Funcionalidad existente |
| Uptime 99.998 %, MTTR, gráficas por hora | Reinicios reales por proceso, telemetría de recon | No inventar métricas |
| "Bucle infinito CPU", "Saturar mailbox", "badarith" | `exit(Pid, kill)` por caja y por servicio, modos de terminal, escenarios A–E y prueba de caos | Solo fallas que el backend sabe inyectar |
| Gráfica de volumen por hora (tablero) | Árbol de supervisión en vivo | Dato real más relevante para la demo |

Agregados que el diseño no tenía y la operación necesita: pestañas de caja en
*Cobrar*, banner de **cobro pendiente de revisión** con "Consultar al banco y
resolver", vista previa del cambio, botones −/+ por partida, panel de
cancelación/devolución, barra fija de total en celular (pedida por `DESIGN.md`)
y exportación de la bitácora a CSV.

### 8.4 Funcionamiento sin Internet

El HTML de Stitch carga Tailwind y las fuentes desde CDN. La demo no debe
depender de servicios externos, así que:

- El CSS se compila localmente (`scripts/construir_css.sh`, Tailwind 3.4.17) en
  `priv/www/css/stitch.css` (≈27 KB) y se versiona.
- Inter, JetBrains Mono y un subconjunto de Material Symbols (solo los iconos
  usados, ≈8 KB) se sirven desde `priv/www/fonts/` (licencias en
  `priv/www/fonts/LICENCIAS.md`).

### 8.5 Verificación

- Recorrido automatizado en **Chromium sin interfaz** (Playwright) y en jsdom
  sobre el backend real: todas las vistas, cobro mixto, cobro en USD, devolución,
  cierre Z, apertura de turno, filtros de bitácora, escenario C y modo oscuro,
  **sin errores de JavaScript**. Ese recorrido detectó y permitió corregir dos
  errores del backend (estado del turno en el corte cerrado y fecha del corte
  consolidado).
- Capturas de la app integrada: `design/evidencias/app-*.png`.
