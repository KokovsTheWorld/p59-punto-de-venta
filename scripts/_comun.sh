# Utilidades compartidas por los scripts de la demo. Se usa con "source".
set -euo pipefail
RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$RAIZ"

# Corre una funcion Erlang sobre un nodo nuevo con datos aislados en
# _build/corridas/<nombre> (se borran al empezar: cada corrida es reproducible).
correr_erlang() {
  local nombre="$1" funcion="$2"
  rebar3 compile >/dev/null
  export P59_DATA_DIR="$RAIZ/_build/corridas/$nombre"
  export P59_PUERTO="${P59_PUERTO:-0}"
  rm -rf "$P59_DATA_DIR"
  mkdir -p "$P59_DATA_DIR" logs
  erl -noshell -pa _build/default/lib/*/ebin -config config/sys.config \
      -kernel logger_level warning -eval "$funcion"
}
