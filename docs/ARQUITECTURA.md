# Arquitectura y decisiones técnicas — #59 Punto de venta

Este documento es la argumentación técnica de la demo: qué procesos hay, quién
reinicia a quién, dónde vive cada dato y por qué cada decisión resuelve los casos
difíciles del problema (`problema/readme.md`).

## 1. Respuesta a las preguntas guía

**1. ¿En qué momento exacto una venta "ocurre" y ya no se puede perder?**
Cuando `p59_inventario` escribe `{{venta, VentaId}, Movimiento}` en la tabla DETS
`movimientos` y ejecuta `dets:sync/1` (`src/p59_inventario.erl`, función
`hacer_confirmacion/2`). Antes de ese punto la venta no existe para el libro y
puede reintentarse sin duplicar. Después, ninguna caída de proceso la borra: al
reiniciar, el libro se relee de disco. La respuesta HTTP con el folio solo se
envía después de ese `sync`.

**2. ¿Qué invariante debe cumplir el corte de caja siempre?**

```text
ventas − reembolsos = (efectivo MXN − cambio − reembolsos en efectivo)
                    + valor en MXN de los dólares (al TC de cada venta)
                    + (tarjeta − reversos a tarjeta)
```

y, para cada venta, `Σ pagos en MXN − cambio = total`. `p59_corte:calcular/2` lo
evalúa y lo reporta en `invariante.ok`. Lo verifican las pruebas, cada corte de
la simulación y los escenarios. El inventario cumple una invariante análoga:
`existencia = inicial − vendidas + devueltas ≥ reservado ≥ 0`
(`p59_inventario:verificar_existencias/0`).

## 2. Árbol de supervisión

```text
p59_punto_de_venta_sup              rest_for_one   (raíz)
├── p59_pg                          pg scope para difundir eventos a SSE
├── p59_servicios_sup               one_for_one
│   ├── p59_metricas                contadores ETS + /metrics
│   ├── p59_eventos                 bitácora (ETS) + difusión pg
│   ├── p59_punto_de_venta_server   estado del sistema / health
│   ├── p59_tipo_cambio             TC simulado y variable
│   ├── p59_terminal_bancaria       terminal simulada con fallas inyectables
│   └── p59_impresora               impresora simulada (puede atascarse)
├── p59_almacen                     dueño de las tablas DETS
├── p59_inventario                  catálogo, existencias, reservas, libro, turnos
└── p59_sucursal_sup                rest_for_one
    ├── p59_ventas_sup              simple_one_for_one → p59_venta (gen_statem, transient)
    └── p59_cajas_sup               one_for_one → p59_caja_1..4 (gen_server, permanent)
```

| Proceso | Tipo | Reinicio | Si falla… | Qué se recupera |
|---|---|---|---|---|
| `p59_caja_N` | gen_server | permanent | Solo esa caja se reinicia (`one_for_one`); las otras 3 siguen cobrando. | Su venta en curso, desde la tabla DETS `cajas`. |
| `p59_venta` | gen_statem | transient | Se reinicia sola; si terminó normal (pagada/cancelada) no se reinicia. | Su estado completo, desde la tabla DETS `ventas`. Si murió durante el cobro pasa a `pendiente_de_revision`. |
| `p59_ventas_sup` | supervisor | permanent | `rest_for_one` en la sucursal: se reinician después las cajas, que reanudan sus ventas. | Ventas abiertas reconstruidas desde DETS. |
| `p59_inventario` | gen_server | permanent | `rest_for_one` en la raíz: se reinician el inventario y la sucursal. | Existencias recalculadas desde el libro; reservas desde DETS; ventas desde DETS. |
| `p59_almacen` | gen_server | permanent | Se cierran y reabren las tablas DETS (`repair`); se reinicia todo lo que depende del disco. | Todo lo persistido. |
| Servicios | gen_server | permanent | Solo ese servicio. | Nada contable vive ahí (contadores y bitácora reciente se pierden; documentado). |

**¿Por qué `rest_for_one` en la raíz?** El orden refleja dependencias reales:
el inventario necesita las tablas del almacén, y las ventas y cajas necesitan el
inventario. Si cae un proceso de abajo hacia arriba, todo lo que depende de él
se reinicia con un estado limpio leído de disco. Si cae una caja, el problema no
sale de `p59_cajas_sup`.

**¿Por qué la venta es un proceso aparte y no está enlazada a la caja?** La caja
*monitorea* su venta, no se enlaza a ella. Así, matar la caja no mata la venta
(prueba de caos 1) y la caída de una venta no tumba la caja.

## 3. Concurrencia sobre el inventario (sin vender lo que no hay)

- El inventario es **un solo proceso**. Su buzón serializa `reservar/2`,
  `confirmar/1` y `reembolsar/4`, así que no se necesitan candados. Las lecturas
  del catálogo van directo a ETS (`read_concurrency`) y no pasan por el buzón.
- Al **agregar** una partida solo se valida contra lo disponible en ese
  momento, como aviso temprano. Al **iniciar el cobro** se **reservan**
  atómicamente todas las partidas: o todas o ninguna. La reserva persiste en
  DETS.
- `disponible = existencia − reservado`. Una reserva se libera si el cobro
  falla o la venta se cancela, y se consume al confirmar.
- Prueba: 50 procesos piden simultáneamente 1 de 2 unidades y exactamente 2
  ganan. Otra prueba pone a 4 cajas a pagar a la vez las 2 últimas piezas: 2 se
  confirman, 2 reciben `sin_existencia` y la existencia queda en 0, nunca
  negativa (`test/p59_ventas_tests.erl`).

## 4. Idempotencia (reintentos de red)

| Operación | Clave | Garantía |
|---|---|---|
| Crear venta | `operacion_id` o cabecera `Idempotency-Key` → DETS `idempotencia` | Mismo id → misma venta. |
| Pagar | `operacion_id` del intento de cobro | Mismo id sobre venta pagada → mismo ticket (200). Otro id → `409 venta_ya_pagada`. |
| Confirmar en el libro | `{venta, VentaId}` con `dets:insert_new` | Aunque lleguen dos confirmaciones, solo una crea movimiento. |
| Cobro con tarjeta | Referencia `VentaId-Intento` en el "banco" | El banco simulado no cobra dos veces la misma referencia. |
| Cancelar ticket | `{cancelacion, Folio}` | Una sola cancelación por ticket. |
| Devolución | `operacion_id` | Repetirla devuelve el mismo movimiento. |

Las peticiones duplicadas simultáneas se serializan en el `gen_statem` de la
venta. La segunda llega cuando el proceso ya terminó y se responde desde el
estado en disco.

## 5. Terminal bancaria que cae a mitad del cobro

Secuencia del cobro en `p59_venta`:

1. Validar pagos y capturar el tipo de cambio (`p59_importes:aplicar_pagos/3`).
2. Guardar en DETS con `sync` el estado `procesando_pago` **con la referencia
   del cargo**, *antes* de hablar con la terminal.
3. Reservar existencias.
4. Si hay tarjeta, llamar a la terminal con timeout.
   - Si responde `aprobado`, se confirma en el libro y queda `pagada`.
   - Si responde `rechazada` o `fuera_de_linea`, se libera la reserva y la
     venta vuelve a `abierta`. Se sabe con certeza que no hubo cargo.
   - Si no responde (timeout o proceso caído), la venta pasa a
     `pendiente_de_revision` **conservando la reserva**. No se registra ningún
     pago.
5. Al **revisar**, o al reintentar el pago, primero se consulta al banco por la
   referencia: si el cargo existe se confirma sin volver a cobrar; si no
   existe, la venta vuelve a `abierta`.

Una venta nunca queda `pagada` sin cargo confirmado. Tampoco se cobra dos veces.

## 6. Dinero, impuestos y moneda

- **Centavos enteros en todo el sistema**, incluida la API. Nada de flotantes:
  la UI convierte el texto "123.45" con aritmética de enteros.
- **IVA por partida** con redondeo a medio centavo hacia arriba. El total del
  ticket es la suma de importes de partida; redondear por total puede diferir en
  centavos, y se eligió por partida porque así se imprime el ticket.
- Las tasas se manejan en puntos base: `16 % = 1600`. Los alimentos básicos y
  frutas y verduras usan 0 % (tasa cero). La tasa general es configurable.
- El **tipo de cambio** se expresa en diezmilésimos (`18.2000 = 182000`), se
  **captura al iniciar el cobro** y se guarda en la venta y en el ticket. Los
  dólares se valoran a **piso**, para que la tienda nunca acredite de más. El
  **cambio se entrega siempre en MXN**.
- La **tarjeta no puede exceder el total**: no se da cambio de un cargo a
  tarjeta.

## 7. Cancelaciones, devoluciones y turnos

- Una venta pagada **no cambia de estado** jamás. Cancelarla o devolver piezas
  crea un **movimiento nuevo** (`cancelacion` o `devolucion`) que referencia el
  folio, la caja y el turno originales.
- **El turno contable de un movimiento es el turno vigente de la caja al
  confirmarse.** Una cancelación de un ticket del turno 1 hecha en el turno 2
  cuenta en el 2, y el corte del turno 1, ya cerrado, no cambia (escenario B).
- **Reembolsos:** primero se revierte a tarjeta lo que se cobró con tarjeta y el
  resto se entrega en efectivo MXN. Nunca se entregan dólares.
- **Devoluciones parciales exactas:** el monto de cada devolución se calcula con
  acumulados (`p59_dinero:acumulado/3`), así que la suma de todas las
  devoluciones de un ticket es exactamente su total, sin centavos perdidos.
- Las piezas devueltas regresan al inventario. Supuesto de la demo: no se
  modela la merma.

## 8. Corte de caja y ventas en proceso

- El corte se calcula **dentro del proceso de inventario**, así que ninguna
  confirmación se intercala mientras se calcula: es una vista consistente.
- Las ventas `abierta`, `procesando_pago` y `pendiente_de_revision` se listan en
  `en_proceso` y **no se suman** (escenario E).
- El efectivo esperado es `fondo + efectivo MXN − cambio − reembolsos en
  efectivo`. Los dólares se esperan **en dólares**, en una gaveta aparte, y no
  se reconvierten con un tipo de cambio distinto al de cada venta.
- Al cerrar el turno se registran el efectivo contado y la diferencia. Un
  descuadre distinto de cero queda como alerta en la bitácora y en `/metrics`.

## 9. Persistencia: qué se guarda y qué no

| Dato | Dónde | ¿Sobrevive a caídas? |
|---|---|---|
| Libro de movimientos (ventas, cancelaciones, devoluciones) | DETS `movimientos` + `sync` | Sí. Es la fuente de verdad. |
| Existencias | Derivadas: catálogo determinista + libro | Sí (se recalculan). |
| Reservas de cobros en curso | DETS `reservas` + `sync` | Sí. |
| Estado de cada venta | DETS `ventas` (`sync` antes de cobrar) | Sí. |
| Turnos y cortes cerrados | DETS `turnos`, `cortes` | Sí. |
| Venta en curso de cada caja | DETS `cajas` | Sí. |
| Claves de idempotencia | DETS `idempotencia` | Sí. |
| Autorizaciones del "banco" | DETS `banco_simulado` | Sí (simula el registro externo del banco). |
| Bitácora reciente, contadores de métricas | ETS | No (informativo). |

**Límites honestos de la solución:**

- No hay una transacción atómica entre varias tablas DETS. Se diseñó para que
  no haga falta: hay **una sola escritura decisiva** (el movimiento del libro) y
  todo lo demás es derivable o se reconcilia al arrancar. Por ejemplo, una
  reserva de una venta ya confirmada se descarta.
- DETS es local a un nodo: no hay replicación ni alta disponibilidad entre
  máquinas. Si el disco se pierde, se pierden los datos.
- Un `kill -9` del sistema operativo justo entre `dets:insert` y `dets:sync`
  podría perder esa última venta. En ese caso el cliente no recibió el ticket, y
  la venta queda en revisión o reintentable con su `operacion_id`.

## 10. Simulaciones (no son integraciones reales)

Terminal bancaria, banco, impresora y tipo de cambio son **simulados**. No hay
integración con SAT, PAC, bancos ni impresoras. El ticket es un **comprobante
interno de la demo y no es un CFDI 4.0**: no lleva sello digital ni timbre.

## 11. Observabilidad

- `GET /metrics` en formato de texto de Prometheus, sin dependencias. Expone
  ventas, cancelaciones, devoluciones, importe, ventas en proceso, cajas
  activas, productos, agotados, errores de pago, ventas en revisión, reintentos
  absorbidos, descuadres, reinicios por proceso y solicitudes y latencia
  acumulada por ruta HTTP.
- `GET /api/diagnostico` usa **recon** (`recon:proc_count/2` por memoria, buzón
  y reducciones).
- `GET /api/estado` devuelve el árbol de supervisión **vivo**, con los pids
  reales. Así se ve cambiar el pid de una caja tras matarla.
- La bitácora (`/api/eventos`) se transmite en tiempo real por **SSE**
  (`/api/eventos/stream`) mediante grupos `pg`.

## 12. Supuestos propios

1. Cuatro cajas fijas (`num_cajas`) y un solo nodo por sucursal.
2. Una venta en curso por caja a la vez.
3. Los precios del catálogo son **antes de IVA**.
4. Catálogo generado con semilla fija (`semilla_catalogo = 59`) para que sea
   reproducible. 1 de cada 40 productos tiene solo 2 piezas y 1 de cada 97 está
   inactivo.
5. El tipo de cambio inicial es de 18.2000 MXN/USD, **simulado**, con una
   variación aleatoria de ±0.3 % cada 30 s.
6. El fondo de caja por omisión es de $1,000.00.
7. Para contar existencias, las devoluciones regresan al inventario.
8. La simulación acelera el tiempo: 600 tickets en segundos, no en 24 h.

## 13. Cifras del problema y su verificación

| Cifra | Uso en la demo | Verificación |
|---|---|---|
| IVA general 16 % | Valor por omisión (`iva_general_pb = 1600`) | LIVA art. 1; tasa general vigente. |
| IVA 8 % región fronteriza norte | Configurable (`iva_general_pb = 800`) | Fuentes secundarias (prensa y consultorías, consultadas el 2026-11-05) indican que un decreto publicado en el DOF el 31-dic-2025 prorrogó el estímulo durante 2026. No se verificó el texto en el DOF; **verifíquelo antes de usarlo como dato real**. Aplica a contribuyentes inscritos en el padrón del estímulo, no automáticamente. |
| Tasa 0 % en alimentos básicos | Categorías Abarrotes y Frutas y verduras | LIVA art. 2-A (simplificado para la demo). |
| CFDI 4.0 con timbrado por PAC | **No implementado** | Solo se aclara en el ticket. |
| 4 cajas, 600 tickets, 800 productos | Simulación | Cifras del enunciado (orden de magnitud). |
| 1–2 min por cliente | No se modela (tiempo acelerado) | — |
