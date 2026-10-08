#!/usr/bin/env bash
# Visor locations.json — servidor estático en 8090 (solo dev)
# Uso: ./tools/serve_map.sh
set -e
PORT=8090
DIR="$(dirname "$0")/locations-map"
SRC="$(realpath "$DIR/../../assets/data/locations.json")"
DST="$DIR/locations.json"
if [ -f "$SRC" ]; then
  cp -f "$SRC" "$DST"
  CNT=$(python3 -c 'import json,sys; print(len(json.load(open(sys.argv[1]))["cities"]))' "$DST" 2>/dev/null || echo "?")
  echo "↻ Sincronizado $SRC → $DST ($CNT ciudades)"
fi
echo "→ Sirviendo visor en http://localhost:${PORT} (dir: ${DIR})"
echo "  Ctrl+C para detener"
# trap limpio
trap 'echo "✕ Servidor detenido"; exit 0' SIGINT SIGTERM
# apertura en incognito si hay un navegador conocido; si no, xdg-open normal
URL="http://localhost:${PORT}"
if [ -n "${DISPLAY:-}" ]; then
  (sleep 1 && {
    for b in google-chrome-stable google-chrome chromium chromium-browser; do
      if command -v "$b" >/dev/null 2>&1; then
        "$b" --incognito "$URL" >/dev/null 2>&1 && exit 0
      fi
    done
    if command -v firefox >/dev/null 2>&1; then
      firefox --private-window "$URL" >/dev/null 2>&1 && exit 0
    fi
    xdg-open "$URL" >/dev/null 2>&1
  } || true) &
fi
python3 -m http.server "${PORT}" --directory "${DIR}"
