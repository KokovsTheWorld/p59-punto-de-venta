#!/usr/bin/env bash
# Compila el CSS de la interfaz (diseño de Google Stitch) con Tailwind 3.4.17.
# El resultado, priv/www/css/stitch.css, se versiona: la demo no necesita este
# script ni Internet para funcionar; solo hace falta al cambiar la interfaz.
#   scripts/construir_css.sh            recompila el CSS
#   scripts/construir_css.sh --fuentes  ademas regenera el subconjunto de iconos
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION=3.4.17
HERR=_build/herramientas
TW="$HERR/tailwindcss-$VERSION"
mkdir -p "$HERR"
if [ ! -x "$TW" ]; then
  echo "Descargando Tailwind CLI $VERSION..."
  curl -fsSL -o "$TW" "https://github.com/tailwindlabs/tailwindcss/releases/download/v$VERSION/tailwindcss-linux-x64"
  chmod +x "$TW"
fi

if [ "${1:-}" = "--fuentes" ]; then
  CP="$HERR/material-symbols.codepoints"
  curl -fsSL -o "$CP" "https://raw.githubusercontent.com/google/material-design-icons/master/variablefont/MaterialSymbolsOutlined%5BFILL%2CGRAD%2Copsz%2Cwght%5D.codepoints"
  ICONOS=$(python3 - "$CP" <<'PY'
import re, sys
nombres = {l.split()[0] for l in open(sys.argv[1])}
texto = ''.join(open(f).read() for f in ['priv/www/index.html', 'priv/www/js/app.js', 'priv/www/js/ui.js'])
print(','.join(sorted(set(re.findall(r"['\">]([a-z][a-z0-9_]+)['\"<]", texto)) & nombres)))
PY
)
  UA='Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/124.0 Safari/537.36'
  URL=$(curl -fsSL -A "$UA" "https://fonts.googleapis.com/css2?family=Material+Symbols+Outlined:opsz,wght,FILL,GRAD@24,400,0,0&icon_names=$ICONOS&display=block" | grep -o 'https:[^)]*' | head -1)
  curl -fsSL -o priv/www/fonts/material-symbols-outlined.woff2 "$URL"
  echo "Iconos: $ICONOS"
fi

"$TW" -c assets/tailwind.config.js -i assets/entrada.css -o priv/www/css/stitch.css --minify
ls -l priv/www/css/stitch.css
