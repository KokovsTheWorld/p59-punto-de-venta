# #59 — Punto de venta

**Dominio:** Comercio, finanzas y servicios

ventas concurrentes, corte de caja y tickets.

> Proyecto #59 del catálogo [tectijuana/erlang-proyectos](https://github.com/tectijuana/erlang-proyectos)
> (Programación Lógica y Funcional, TecNM Instituto Tecnológico de Tijuana). Este
> repositorio independiente parte del esqueleto original de ese catálogo (primer
> commit, autoría del profesor) y contiene el desarrollo de la etapa DEMO.
> Manual de uso: [Gist](https://gist.github.com/KokovsTheWorld/d7d67d71a4b4c5d96a17b6e746a88bfc).

Prototipo funcional (etapa **DEMO**) en Erlang/OTP: 4 cajas que cobran al mismo
tiempo sobre un inventario compartido de 800 productos. Acepta pesos, dólares,
tarjeta simulada y pagos mixtos. Registra cancelaciones y devoluciones con
trazabilidad, genera cortes de caja por caja, turno y cajero que siempre
cuadran, y se recupera sola cuando un proceso cae.

> Las integraciones con banco, impresora y tipo de cambio son **simuladas**. El
> ticket es un **comprobante interno, no un CFDI 4.0**: no hay timbrado ni
> conexión con SAT/PAC.

## Equipo

| Rol | Integrante |
|---|---|
| Backend (OTP) | |
| Frontend (Stitch + cowboy) | |
| Ops/QA | |

## Arranque rápido

```bash
git clone https://github.com/KokovsTheWorld/p59-punto-de-venta.git && cd p59-punto-de-venta
rebar3 compile          # sin warnings (warnings_as_errors)
rebar3 eunit            # 49 pruebas
scripts/demo.sh         # compila, prueba, genera el release y lo arranca
# abrir http://localhost:8059/
```

Otras formas:

```bash
rebar3 shell                                   # desarrollo (puerto 8059)
scripts/simular.sh                             # 4 cajas · 600 tickets · fallas inyectadas
scripts/escenarios.sh                          # escenarios A–E del problema
scripts/caos.sh                                # prueba de caos reproducible
_build/default/rel/p59_punto_de_venta/bin/p59_punto_de_venta stop
```

Requisitos: Erlang/OTP 27 (probado con 27.3.4.6) y rebar3 3.28.0. Dependencias
Hex: `cowboy 2.12.0` (HTTP, SSE) y `recon 2.5.6` (diagnóstico). Para JSON se
usa el módulo `json` incluido en OTP 27, sin dependencias extra. Instalación
paso a paso en WSL: [`docs/MANUAL.md`](docs/MANUAL.md).

## Estado de la demo

| Elemento | Estado | Evidencia |
|---|---|---|
| Aplicación OTP, árbol de supervisión, 4 cajas, 800 productos | ✅ | `src/`, `test/p59_punto_de_venta_tests.erl` |
| Ventas (`gen_statem`), pagos MXN/USD/tarjeta/mixto, tickets | ✅ | `test/p59_ventas_tests.erl` |
| Cancelaciones y devoluciones trazables; corte por caja, turno y cajero | ✅ | escenario B, `docs/evidencias/` |
| Idempotencia y concurrencia sobre el inventario | ✅ | escenario C, pruebas de concurrencia |
| API Cowboy + SSE en tiempo real + `/metrics` + recon | ✅ | `test/p59_http_tests.erl` |
| Simulación de 600 tickets, escenarios A–E y prueba de caos | ✅ | `docs/evidencias/03..05-*` |
| Release relx y unidad systemd (modo usuario) | ✅ release probado · systemd preparado sin instalar | `docs/evidencias/06-release.txt` |
| Diseño UIX en Google Stitch (7 pantallas + DESIGN.md) | ✅ generado por el equipo | `design/stitch/`, `design/evidencias/stitch-*.png` |
| Interfaz Stitch integrada y conectada a la API (HTTP + SSE), sin dependencias de Internet | ✅ | `priv/www/`, `design/evidencias/app-*.png`, `design/PROMPT_STITCH.md` §8 |
| Manual en GitHub Gist | ✅ publicado (público) | [Gist](https://gist.github.com/KokovsTheWorld/d7d67d71a4b4c5d96a17b6e746a88bfc) · fuente: `docs/MANUAL.md` |

## Arquitectura OTP

```text
p59_punto_de_venta_sup              rest_for_one
├── p59_pg                          grupos pg (difusión de eventos a SSE)
├── p59_servicios_sup               one_for_one: métricas, eventos, estado,
│                                   tipo de cambio, terminal e impresora simuladas
├── p59_almacen                     tablas DETS (persistencia local)
├── p59_inventario                  catálogo, existencias, reservas, libro, turnos
└── p59_sucursal_sup                rest_for_one
    ├── p59_ventas_sup              simple_one_for_one → p59_venta (gen_statem, transient)
    └── p59_cajas_sup               one_for_one → p59_caja_1..4 (gen_server)
```

- **Un proceso de inventario** serializa reservas y confirmaciones: dos cajas
  nunca consumen la misma unidad y las existencias nunca son negativas.
- **Un `gen_statem` por venta**, con los estados `abierta`, `procesando_pago`,
  `pendiente_de_revision`, `pagada` y `cancelada`. Su estado se guarda en DETS
  en cada transición; si el proceso cae, se reconstruye.
- **Un `gen_server` por caja** que *monitorea* su venta, sin enlazarse a ella.
  Si la caja cae, la venta sobrevive y la caja la recupera al reiniciarse.
- **Punto de no retorno:** el movimiento de la venta se escribe en el libro
  DETS con `sync`. Las existencias se derivan del libro.

Argumentación completa (decisiones, invariantes, idempotencia, recuperación,
límites, supuestos y cifras verificadas): **[`docs/ARQUITECTURA.md`](docs/ARQUITECTURA.md)**.

## Resultados verificados (2026-11-05, WSL2 · Ubuntu 26.04 · OTP 27.3.4.6)

- `rebar3 compile` sin warnings; `rebar3 eunit`: **49 pruebas, 0 fallas**.
- **Simulación:** 600 tickets confirmados en unos 10 s por 4 cajas en
  paralelo. Incluye efectivo MXN, USD, tarjeta y mixto; rechazos y caídas de
  terminal; 29 reintentos duplicados absorbidos; cambio de turno con
  cancelaciones del turno anterior y devoluciones; la caja 3 matada a mitad de
  la corrida y recuperada. **Todos los cortes cuadran, la invariante de
  inventario se cumple, hay una venta por ticket y los folios son únicos.** El
  descuadre de −$50.00 en la caja 3 está inyectado a propósito.
- **Escenarios A–E:** 34 de 34 verificaciones correctas.
- **Prueba de caos:** se mataron la caja, la venta y el inventario con una venta
  abierta. Los tres se recuperaron y la venta se cobró después; inventario y
  corte quedaron consistentes (22 de 22 verificaciones).

Salidas completas en [`docs/evidencias/`](docs/evidencias/). Las cifras exactas
varían ligeramente entre corridas porque dependen del intercalado real de las
cajas. Las invariantes no varían.

## API (resumen)

| Método y ruta | Uso |
|---|---|
| `GET /api/health`, `GET /api/estado`, `GET /api/diagnostico` | Salud, árbol de supervisión vivo, recon |
| `GET /api/productos[?q=&categoria=&pagina=&limite=]`, `GET /api/productos/:id` | Catálogo y existencias |
| `GET /api/cajas`, `GET /api/cajas/:id`, `POST /api/cajas/:id/turno`, `POST /api/cajas/:id/turno/cerrar` | Cajas y turnos |
| `POST /api/ventas`, `GET /api/ventas`, `GET /api/ventas/:id` | Ventas |
| `POST /api/ventas/:id/partidas`, `DELETE /api/ventas/:id/partidas/:producto` | Partidas |
| `POST /api/ventas/:id/pago`, `POST /api/ventas/:id/revisar`, `POST /api/ventas/:id/cancelar` | Cobro, revisión, cancelación |
| `GET /api/tickets`, `GET /api/tickets/:folio`, `POST /api/tickets/:folio/cancelar`, `POST /api/tickets/:folio/devolucion` | Tickets |
| `GET /api/corte[?caja=&turno=&cajero=]` | Corte de caja |
| `GET /api/eventos`, `GET /api/eventos/stream` (SSE) | Bitácora en tiempo real |
| `GET/POST /api/tipo-cambio` | Tipo de cambio simulado |
| `POST /api/simulacion/{terminal,impresora,matar,caos,carga}`, `POST /api/simulacion/escenarios/:letra` | Fallas inyectadas |
| `GET /metrics` | Prometheus (texto) |

Todos los montos van en **centavos enteros**. Ejemplos con `curl` en el manual.

## Organización

```text
src/        aplicación OTP (dominio puro, procesos y manejadores HTTP separados)
test/       eunit: cálculo, árbol, ventas, concurrencia, escenarios, caos, HTTP
config/     sys.config (parámetros de la demo) y vm.args
priv/www/   interfaz diseñada en Stitch (HTML, JS, CSS compilado, fuentes locales)
assets/     fuente de Tailwind (config exportada de Stitch + hoja de entrada)
scripts/    demo.sh, simular.sh, escenarios.sh, caos.sh, construir_css.sh, systemd/
docs/       ARQUITECTURA.md, MANUAL.md (para Gist), evidencias/
design/     PROMPT_STITCH.md, stitch/ (exportación de Stitch), evidencias/ (capturas)
problema/   enunciado original
```

## Pendiente

- [x] Diseñar pantallas en Stitch (`design/PROMPT_STITCH.md`)
- [x] Modelar el dominio: qué es un proceso, qué es un supervisor
- [x] Endpoints `/api/...` y tiempo real (SSE) con cowboy
- [x] Métricas `/metrics` y diagnóstico con recon
- [x] Release + systemd (unidad preparada en `scripts/systemd/`, no instalada)
- [x] Prueba de caos (matar procesos y verificar recuperación)
- [x] Integrar el HTML exportado de Stitch en `priv/www/`
- [x] Publicar `docs/MANUAL.md` como Gist: https://gist.github.com/KokovsTheWorld/d7d67d71a4b4c5d96a17b6e746a88bfc

## Diseño OTP sugerido (plantilla original)

- **Procesos:** gen_server por caja/terminal; gen_server de catalogo e inventario; gen_statem por venta (abierta, pagada, cancelada); generador de tickets
- **Supervision:** supervisor por sucursal; cajas independientes
- **API / tiempo real:** POST /api/ventas, POST /api/ventas/:id/pago, GET /api/corte?caja=
- **Metricas:** ventas por hora, ticket promedio, cancelaciones, descuadre de corte
- **Prueba de caos:** matar una caja con venta abierta: se recupera y el corte cuadra

Diferencias con la sugerencia, con su justificación:
- La caja no es la terminal: la terminal bancaria es un servicio simulado
  aparte, para poder inyectarle fallas.
- El "generador de tickets" no es un proceso: el folio se asigna dentro de la
  confirmación del inventario, para que folio y venta sean una sola escritura.
  La impresión sí es un proceso (`p59_impresora`), porque puede fallar sin
  afectar la venta.
- Se agregó el estado `pendiente_de_revision` para el caso de la terminal que
  cae a mitad del cobro.

## Licencia

[MIT](LICENSE), heredada del catálogo original © 2026 René Solis R. y colaboradores (TecNM / IT Tijuana).
