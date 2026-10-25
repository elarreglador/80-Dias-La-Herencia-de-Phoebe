# PF — 80 Días · La Herencia de Phoebe

Flutter 3.47.5 stable · Dart 3.13.4 — app móvil (Android/iOS) y web · protagonista **Phoebe Fogg**.

Viaje transcontinental en tiempo simulado: Phoebe Fogg recorre el mundo hacia el Este sin avión, con descanso local, *sleeper*, cartas y la Regla del Este.

## Estado actual

**Implementado** (resumen vivo de `docs/specs/`):

- **SPEC 001** — Mapa Mercator + terminador solar (NOAA + `apsl_sun_calc`): `nightPolygons` (1 polígono curvo o 2 rectángulos split antimeridiano en equinoccio), clamp Mercator ±85.051°, `Epsg3857NoRepeat`.
- **SPEC 002** — Scaffold: `AppBar` + `NavigationBar` M3 de 5 destinos (Mapa, Diario, Fogg [central dinámico], Presupuesto, Ruta).
- **SPEC 003** — Visor dev de `locations.json` sobre OSM.
- **SPECs 004–011** — Rutas reales (marítimas, terrestres, ferroviarias) + marítimas ficticias y visores de cada una.
- **SPEC 008** — Cobertura de rutas por ciudad (≥1 salida y ≥1 entrada en el conjunto mar ∪ tierra ∪ raíl).
- **SPEC 012** — Núcleo de juego: `TimeEngine` (ciclo descanso 5–8 h, *sleeper*, aceleración), `BudgetService` + `Ledger`, `EventEngine` mock.
- **SPEC 013** — Consumo de rutas reales + `TransportSelector` (tarifas ship/train/car; sin avión, sin a pie).
- **SPEC 015** — Previsión meteorológica por vehículo (`WeatherService` Open-Meteo, `WeatherImpact`).
- **SPEC 016** — Ruta viva y movimiento de Phoebe: `RoutePath`, `CityCatalog` (257 ciudades), tramo activo en el mapa, llegada sola a `FoggArrived`.
- **SPEC 017** — Selección de destino y vehículo por tarjetas: `CityInfoCard`, `DestinationCard` (colapsada/expandida), «Iniciar trayecto».

**Pendiente** (checklist vivo en `TODO.md`): ruta completa de 5 ciudades hacia el Este, `DiaryService` + `StoryGenerator`, `InMemoryBackend`, `Hive`, PWA final, etc.

**Calidad:** `flutter analyze` (1 lint `info` preexistente) · `flutter test` (161 tests, todos verdes).

## Configuración

Solo se consume `--dart-define` (un único sitio: `MAP_TILE_URL` en `lib/presentation/widgets/world_map_widget.dart`).

- `MAP_TILE_URL` — `https://tile.openstreetmap.org/{z}/{x}/{y}.png` por defecto (fallback en el widget).
- `TIME_SCALE` — ya no se lee por `dart-define`: `debugTimeScale = 60.0` en `lib/presentation/providers/time_engine_provider.dart`; `TimeEngine` fuerza `kReleaseMode ? 1.0 : scale`.
- `INITIAL_BUDGET` — `1_000_000 €` por defecto (`BudgetService`).
- `OPEN_METEO_URL` — `https://api.open-meteo.com/v1/forecast` (sin key, en `WeatherService`).
- Fecha de inicio — `TimeEngine` recibe `startUtc` (`DateTime.now().toUtc()` hoy; QA: `_forcedSolsticeUtc` en `lib/main.dart`).

No hay `.env` ni `dotenv`: `--dart-define` es la única vía.

## Terminador solar

`lib/services/sun_terminator_service.dart` es matemática NOAA pura, sin `BuildContext`. Genera 1 polígono curvo de 183 vértices paso 2° (solsticios) o 2 rectángulos de 4 vértices split antimeridiano (equinoccio, |subLat| < 0.5°) cada 5 min vía `sunTerminatorProvider` (`Provider.autoDispose<List<List<LatLng>>>`). Latitud clampada a ±85.05112878 (límite Mercator). Usar siempre `nightPolygons` (plural); `nightPolygon` (singular) es legacy. El mapa debe usar `crs: Epsg3857NoRepeat` (`world_map_widget.dart:64`, `replicatesWorldLongitude => false`) junto a `_ContainWithFallback`.

Capa día/noche: el overlay nocturno es `Color(0xFF000511).withValues(alpha:0.45)` (`AppColors.nightOverlay`) entre `TileLayer` y `PolylineLayer`. Con tiles claros OSM el contraste es óptimo; con tiles oscuros/satélite puede requerir ajustar `alpha` en `lib/utils/app_colors.dart`. No afecta a la ruta roja `#C0392B`.

Fix completo: 2026-09-22.

## Visor locations.json (solo dev)

Herramienta web que renderiza `assets/data/locations.json` sobre OpenStreetMap para validar la Regla del Este sin tocar el bundle de la app. Vanilla Leaflet 1.9.4, sin `node_modules` ni `flutter run` — markers individuales sin cluster.

```bash
./tools/serve_map.sh          # http://localhost:8090 — OSM + 257 markers
python3 -m http.server 8090 --directory tools/locations-map  # equivalente manual
```

- **MAP_TILE_URL** por defecto `https://tile.openstreetmap.org/{z}/{x}/{y}.png` (`L.tileLayer` `maxZoom:18`).
- Panel 320px derecha: filtro `name|asciiname|timezone` (debounce 150ms), lista `lat,lng` 6 decimales, click → `map.setView([lat,lng],6)`.
- Drag&drop de `locations.json` local sobre el mapa o `input[type=file]` — reemplaza markers en caliente sin escribir disco.
- Los cuatro selectores independientes no disparan carga automática: «Cargar rutas terrestres» (`car_routes.json`, polilínea amarilla `#F9A825`), «Cargar rutas marítimas» (`sea_routes.json`, `#1E88E5`), «Cargar rutas marítimas ficticias» (`sea_routes_fiction.json`, `#2E7D32`) y «Cargar rutas ferroviarias» (`rail_routes.json`, `#6A1B9A`). Cada ruta se dibuja como línea discontinua animada con popup de origen, destino, distancia, duración (si el fichero trae `durationHours`) y vértices. Las cuatro capas conviven a la vez, se leen localmente, no se escriben ni se persisten, y **ninguna carga mueve la cámara** (`center`/`zoom` intactos).
- Las rutas se reemplazan atómicamente por capa al cargar un archivo válido; un JSON inválido conserva exactamente la última carga válida de esa capa y no toca la otra. El visor también segmenta travesías que cruzan el antimeridiano.
- `tools/locations-map/locations.json` es copia opcional para fallback `file://`.

## Cobertura de rutas (SPEC 008)

Toda ciudad de `locations.json` debe tener ≥1 ruta de salida y ≥1 de entrada en la **unión** de las capas de rutas:

```bash
python3 tools/route_coverage.py                 # recuentos; código 2 mientras haya pendientes
python3 tools/route_coverage.py --write-report  # regenera docs/ciudades-sin-rutas.md conservando Decisión
python3 .opencode/skills/fogg-land-routes/land_route.py --close-gaps    # cierra huecos por carretera
python3 .opencode/skills/fogg-sea-routes/sea_route.py --close-gaps      # cierra huecos por mar
```

- Las rutas de cierre llevan `gapClosed: true`; no cuentan para `limitPerOrigin`. Ambos `meta` añaden `gapClosedRoutes` y `coverage`.
- `validate_dataset` de las skills falla con `[ERROR]` si queda una ciudad descubierta sin excepción: no se escriben datasets con huecos.
- **Excepciones:** el único fichero es `docs/ciudades-sin-rutas.md`; edítalo solo la columna `Decisión` con `excepción — <motivo>`. Regenerar con `--write-report` conserva esa columna. `test/data/route_coverage_test.dart` aplica la misma regla en `flutter test`.
- Presupuesto `--close-gaps` (OSRM demo, 1 petición/s): ≤1 `/table` + ≤1 `/route` por hueco de salida y ≤1 `/table` + ≤5 `/route` por hueco de entrada; la pasada marítima es offline (`searoute`).

## Getting Started

```bash
flutter pub get
flutter run -d <serial>   # `flutter devices` para el serial; el Redmi del proyecto: 5lcqy54d4l4ltspz
flutter analyze
flutter test
./tools/serve_map.sh
```

- `flutter run -d chrome` NO funciona hoy: `WeatherService` instancia `HttpClient` de `dart:io`, que en web revienta con `Unsupported operation: Platform._version`. Para ver la app: teléfono (Android) o `flutter run -d linux`.

## Documentación

- `TODO.md` — checklist vivo (Features / Fix / Tareas finalizadas).
- `docs/specs/` — especificaciones con estado `Borrador → Aprobado → Implementado`.
