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
- `Cargar rutas terrestres`, `Cargar rutas marítimas` y `Cargar rutas marítimas ficticias` son tres selectores independientes, sin carga automática: el primero espera `assets/data/car_routes.json` (polilínea amarilla `#F9A825`), el segundo `assets/data/sea_routes.json` (polilínea azul `#1E88E5`) y el tercero un fichero de rutas marítimas ficticias con el mismo esquema que las marítimas (polilínea verde `#2E7D32`). Cada ruta se dibuja como línea discontinua animada con popup de origen, destino, distancia, duración (solo si el fichero trae `durationHours`, hoy únicamente el terrestre) y vértices. Las tres capas conviven a la vez, se leen localmente, no se escriben ni se persisten, y **ninguna carga mueve la cámara** (`center`/`zoom` intactos).
- Las rutas se reemplazan atómicamente por capa al cargar un archivo válido; un JSON inválido conserva exactamente la última carga válida de esa capa y no toca la otra. El visor también segmenta travesías que cruzan el antimeridiano.
- `tools/locations-map/locations.json` es copia opcional para fallback `file://`.

Capa día/noche: `SunTerminatorService` (NOAA + `apsl_sun_calc` 0.0.4) genera 1 polígono curvo 183 vértices paso 2° (solsticios) o 2 rectángulos 4 vértices split antimeridiano (equinoccio |subLat|<0.5°) cada 5 min vía `sunTerminatorProvider` (`Provider.autoDispose<List<List<LatLng>>>`). Clamp Mercator `85.051°` y `Epsg3857NoRepeat` evitan salto/replica. Fix completo 2026-09-22.

### Cobertura de rutas (SPEC 008)

Toda ciudad de `locations.json` debe tener ≥1 ruta de salida y ≥1 de entrada en la **unión** de `sea_routes.json` y `car_routes.json` (no importa si es por mar o por tierra):

```bash
python3 tools/route_coverage.py                 # recuentos; código 2 mientras haya pendientes
python3 tools/route_coverage.py --write-report  # regenera docs/ciudades-sin-rutas.md conservando Decisión
python3 .opencode/skills/fogg-land-routes/land_route.py --close-gaps    # cierra huecos por carretera
python3 .opencode/skills/fogg-sea-routes/sea_route.py --close-gaps      # cierra huecos por mar
```

- Las rutas de cierre llevan `gapClosed: true`; no cuentan para `limitPerOrigin`. Ambos `meta` añaden `gapClosedRoutes` y `coverage`.
- `validate_dataset` de las dos skills falla con `[ERROR]` si queda una ciudad descubierta sin excepción: no se escriben datasets con huecos.
- **Excepciones:** el único fichero es `docs/ciudades-sin-rutas.md`; edítese solo la columna `Decisión` con `excepción — <motivo>`. Regenerar con `--write-report` conserva esa columna. `test/data/route_coverage_test.dart` aplica la misma regla en `flutter test`.
- Presupuesto `--close-gaps` (OSRM demo, 1 petición/s): ≤1 `/table` + ≤1 `/route` por hueco de salida y ≤1 `/table` + ≤5 `/route` por hueco de entrada; la pasada marítima es offline (`searoute`).

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
