#!/usr/bin/env bash
# Visor locations.json — servidor estático en 8090 (solo dev)
# Uso: ./tools/serve_map.sh
set -e
PORT=8090
DIR="$(dirname "$0")/locations-map"
echo "→ Sirviendo visor en http://localhost:${PORT} (dir: ${DIR})"
echo "  Ctrl+C para detener"
# trap limpio
trap 'echo "✕ Servidor detenido"; exit 0' SIGINT SIGTERM
# xdg-open opcional si existe y hay DISPLAY
if command -v xdg-open >/dev/null 2>&1 && [ -n "${DISPLAY:-}" ]; then
  (sleep 1 && xdg-open "http://localhost:${PORT}" >/dev/null 2>&1 &) || true
fi
python3 -m http.server "${PORT}" --directory "${DIR}"
