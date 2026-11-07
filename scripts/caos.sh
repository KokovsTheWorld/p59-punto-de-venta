#!/usr/bin/env bash
# Prueba de caos: mata caja, venta e inventario con una venta abierta y verifica
# que todo se recupere con inventario y corte consistentes.
source "$(dirname "$0")/_comun.sh"
correr_erlang caos 'p59_caos:cli().'
