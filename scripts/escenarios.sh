#!/usr/bin/env bash
# Escenarios A-E del problema (terminal, turno anterior, reintento, dolares,
# corte con ventas en proceso).
source "$(dirname "$0")/_comun.sh"
correr_erlang escenarios 'p59_escenarios:cli().'
