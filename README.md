# #59 — Punto de venta

**Dominio:** Comercio, finanzas y servicios

ventas concurrentes, corte de caja y tickets.

## Equipo

| Rol | Integrante |
|---|---|
| Backend (OTP) | |
| Frontend (Stitch + cowboy) | |
| Ops/QA | |

## Arranque

```bash
rebar3 compile
rebar3 eunit
rebar3 shell
```

## Pendiente

- [ ] Disenar pantallas en Stitch (`design/PROMPT_STITCH.md`)
- [ ] Modelar el dominio: que es un proceso, que es un supervisor
- [ ] Endpoints `/api/...` y WebSocket con cowboy
- [ ] Metricas `/metrics` y diagnostico con recon
- [ ] Release + systemd
- [ ] Prueba de caos (matar procesos y verificar recuperacion)

## Diseno OTP sugerido

- **Procesos:** gen_server por caja/terminal; gen_server de catalogo e inventario; gen_statem por venta (abierta, pagada, cancelada); generador de tickets
- **Supervision:** supervisor por sucursal; cajas independientes
- **API / tiempo real:** POST /api/ventas, POST /api/ventas/:id/pago, GET /api/corte?caja=
- **Metricas:** ventas por hora, ticket promedio, cancelaciones, descuadre de corte
- **Prueba de caos:** matar una caja con venta abierta: se recupera y el corte cuadra
