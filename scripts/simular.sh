#!/usr/bin/env bash
# Simulacion del escenario: 4 cajas, 600 tickets, 800 productos, fallas inyectadas.
# Uso: scripts/simular.sh            (P59_TICKETS=1000 scripts/simular.sh para otro volumen)
source "$(dirname "$0")/_comun.sh"
correr_erlang simulacion 'p59_simulacion:cli().'
