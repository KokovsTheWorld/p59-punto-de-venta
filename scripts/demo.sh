#!/usr/bin/env bash
# Compila, prueba, genera el release y lo arranca en segundo plano.
# Uso: scripts/demo.sh            (P59_PUERTO=9000 scripts/demo.sh para otro puerto)
set -euo pipefail
cd "$(dirname "$0")/.."
REL=_build/default/rel/p59_punto_de_venta
rebar3 compile
rebar3 eunit
rebar3 release
if "$REL/bin/p59_punto_de_venta" ping >/dev/null 2>&1; then
  echo "El release ya estaba corriendo; se reinicia para tomar los cambios."
  "$REL/bin/p59_punto_de_venta" stop
fi
"$REL/bin/p59_punto_de_venta" daemon
for _ in $(seq 1 30); do
  curl -sf "http://localhost:${P59_PUERTO:-8059}/api/health" >/dev/null && break
  sleep 0.5
done
curl -s "http://localhost:${P59_PUERTO:-8059}/api/health"; echo
echo "Interfaz: http://localhost:${P59_PUERTO:-8059}/"
echo "Detener:  $REL/bin/p59_punto_de_venta stop"
