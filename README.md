# PF — 80 Días · La Herencia de Phoebe

Flutter Web 3.22+ / Dart 3.4+ — PWA `eu.elarreglador.pf` — protagonista **Phoebe Fogg**.

## Configuración

Variables vía `--dart-define` o `SENSIBLE/.env` (copiar a `.env`):

- `START_DATE` — fecha inicio periplo.
- `TIME_SCALE` — solo dev, `assert(TIME_SCALE==1)` en prod (guardarraíl).
- `INITIAL_BUDGET` — `1_000_000 €` (BudgetService + Ledger).
- `MAP_TILE_URL` — `https://tile.openstreetmap.org/{z}/{x}/{y}.png` por defecto.
  > **Contraste terminador:** el overlay nocturno es `Color(0xFF000511).withValues(alpha:0.45)` (`AppColors.nightOverlay`) entre `TileLayer` y `PolylineLayer`. Con tiles claros OSM el contraste es óptimo; con tiles oscuros/satélite puede requerir ajustar `alpha` en `lib/utils/app_colors.dart`. No afecta a la ruta roja `#C0392B`.
- `OPEN_METEO_URL` — `https://api.open-meteo.com/v1/forecast` (sin key).

### Visor locations.json (solo dev)

Herramienta web que renderiza `assets/data/locations.json` sobre OpenStreetMap para validar la Regla del Este sin tocar el bundle PWA. Vanilla Leaflet 1.9.4, sin `node_modules` ni `flutter run` — markers individuales sin cluster.

```bash
./tools/serve_map.sh          # http://localhost:8090 — OSM + 230 markers
python3 -m http.server 8090 --directory tools/locations-map  # equivalente manual
```

- **MAP_TILE_URL** por defecto `https://tile.openstreetmap.org/{z}/{x}/{y}.png` (`L.tileLayer` `maxZoom:18`).
- Panel 320px derecha: filtro `name|asciiname|timezone` (debounce 150ms), lista `lat,lng` 6 decimales, click → `map.setView([lat,lng],6)`.
- Drag&drop de `locations.json` local sobre el mapa o `input[type=file]` — reemplaza markers en caliente sin escribir disco.
- `tools/locations-map/locations.json` es copia opcional para fallback `file://`.

Capa día/noche: `SunTerminatorService` (NOAA + `apsl_sun_calc` 0.0.4) genera 1 polígono curvo 183 vértices paso 2° (solsticios) o 2 rectángulos 4 vértices split antimeridiano (equinoccio |subLat|<0.5°) cada 5 min vía `sunTerminatorProvider` (`Provider.autoDispose<List<List<LatLng>>>`). Clamp Mercator `85.051°` y `Epsg3857NoRepeat` evitan salto/replica. Fix completo 2026-09-22.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
