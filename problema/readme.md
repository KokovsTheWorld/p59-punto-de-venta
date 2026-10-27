# #59 — Punto de venta: el problema

## Contexto
Una tienda tiene varias cajas que cobran al mismo tiempo sobre el mismo inventario, y en Tijuana se acepta pesos y dolares, con tipo de cambio variable. El corte de caja debe cuadrar al centavo, y cada venta debe poder demostrarse para el SAT.

## Datos del mundo real
- IVA general de 16 %; en la region fronteriza el decreto de estimulo fiscal ha permitido una tasa de 8 % (verifica la vigencia del decreto antes de usarlo).
- En Mexico las ventas se facturan con CFDI (version 4.0), con timbrado de un proveedor autorizado (PAC); si el timbrado falla, la venta ya ocurrio y la factura se emite despues.
- Un ticket tiene una estructura clara: partidas, descuentos, impuestos, total, forma de pago (efectivo, tarjeta, mixto, dolares). Redondeos por partida vs. por total pueden diferir en centavos.
- Una tienda mediana atiende 200-1,000 tickets diarios con 2-6 cajas; en horas pico, una caja cobra 1 cliente por ~1-2 minutos.
- Las terminales de tarjeta fallan, las impresoras se atoran y se va la luz: una venta puede quedar a medias.
- Al corte de caja se concilia efectivo contado vs. efectivo esperado; una diferencia pequeña es normal, una grande requiere explicacion.

## El problema
Registrar ventas simultaneas desde varias cajas sin vender mas de lo que hay, calcular impuestos y totales con precision, soportar pago mixto y en dos monedas, permitir cancelaciones y devoluciones con trazabilidad, y generar el corte de caja por turno y por cajero.

## Escenario a simular
- 4 cajas, 600 tickets al dia, 800 productos.
- Terminal bancaria que cae a mitad de un cobro.
- Cancelacion de un ticket del turno anterior.

## Casos dificiles
- Venta repetida por reintento de red.
- Pago en dolares con vuelto en pesos y tipo de cambio del momento.
- Corte de caja con ventas aun en proceso.

## Preguntas guia
1. ¿En que momento exacto una venta "ocurre" y ya no se puede perder?
2. ¿Que invariante debe cumplir el corte de caja siempre?

## Que debes entregar (sin que aqui se de la solucion)
- Un diseño OTP explicado brevemente: procesos, supervisores y quien reinicia a quien, justificando cada decision frente a los casos dificiles de arriba.
- La simulacion del escenario descrito, con datos generados y fallas inyectadas.
- Una lista de supuestos propios y de las cifras de este documento que verificaste.
- Una prueba de caos: que mataste, que esperabas y que ocurrio.
- `rebar3 compile` y `rebar3 eunit` en verde; capturas de Stitch y de la app real si hay interfaz.

---
*Las cifras son de referencia (ordenes de magnitud). Verifica la fuente vigente antes de citarlas en tu entrega y anota las que uses en tu README.*
