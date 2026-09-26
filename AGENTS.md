# AGENTS.md — PF (80 Días · La Herencia de Phoebe)

Instrucciones repo-específicas para OpenCode. Complementa a `~/.config/opencode/AGENTS.md` (global); si hay conflicto, prevalece este archivo.

## Estado real del repo (leído del código, no de la documentación)

- **Una sola app Flutter en la raíz.** El paquete Dart se llama **`pf`** → los imports son `package:pf/...`. **No existen** `frontend/`, `shared_models/`, `backend/`. El layout es `lib/{presentation,domain,services,utils}` + `test/` espejo.
- `eu.elarreglador.pf` (dominio inverso) aparece **solo** como `userAgentPackageName` de OSM (`lib/presentation/widgets/world_map_widget.dart:277`) y en el campo `meta.project` de los JSON de datos. No es el nombre del paquete Dart.
- **El MVP está muy por delante de lo que el plan sugiere, y por detrás en lo que el plan promete.** Implementado: mapa Mercator + terminador solar, scaffold con NavigationBar, `TimezoneService`, catálogo de ciudades, visor dev.
  **NO existe todavía** (no lo busques, no lo asumas): `TimeEngine`, `BudgetService`, `EventEngine`, `TransportSelector`, `Ledger`, `InMemoryBackend`, `StoryGenerator`, `Hive`, ningún `service_worker`, `shared_models`. Son ítems abiertos de `TODO.md`, que es la fuente de verdad del plan.
- Tres de las cinco pestañas de `MainScaffold` son `*Placeholder` (`lib/presentation/pages/placeholder_pages.dart`).
- Flutter verificado: 3.47.5 stable. Sin CI, sin pre-commit, sin hooks.

## Comandos

```bash
flutter analyze                 # lint + typecheck (analysis_options.yaml excluye tools/** y plataformas)
flutter test                    # 85 tests, ~6s, todos verdes
flutter test test/services/sun_terminator_service_test.dart          # un archivo
flutter test --plain-name "nombre exacto del test"                   # un solo test
flutter run -d chrome
./tools/serve_map.sh            # visor dev en :8090
```

- `flutter analyze` **ya sale con 1 lint `info` preexistente** (`prefer_const_constructors` en `test/services/sun_terminator_service_test.dart:291`). No lo introduzcas tú y no lo confundas con tu cambio.
- `flutter test` imprime un aviso de política de tiles de OSM de `flutter_map` en casi todos los tests. Es ruido esperado, no un fallo.

## Invariantes de dominio — verificados en código

- **Regla del Este**: se valida con `assert` en `FoggRoute.validated` (`lib/domain/entities/fogg_route.dart:12`) vía `_isEastward`. Usa **longitud desenrollada**, así que cruzar el antimeridiano hacia el este es legal (Tokio → San Francisco) y `order` debe ser consecutivo. **Usa siempre `FoggRoute.validated(...)`** para rutas nuevas; el constructor `const` no valida. Cubierto por `test/domain/fogg_route_test.dart`.
- **Sin avión**: `TransportMode` tiene exactamente 8 valores (`train, ship, car, balloon, horse, camel, foot, motorcycle`). No añadas `flight`. Nota: `balloon` usa `Icons.air` y `camel` reutiliza `Icons.pets` (igual que `horse`); se distinguen por `label`. No lo "corrijas" sin consultar.
- **Naming**: `Fogg*` / `Phoebe` (`FoggRoute`, `FoggCity`, `FoggLeg`, `FoggStatus`, `foggPositionProvider`, `Ciclo Fogg`). Nunca `Traveler` genérico.
- **Idioma**: identificadores y código en inglés; docstrings, comentarios y textos de UI en castellano.
- **Hora civil**: `TimezoneService.init()` se llama una vez en `main()`; todo offset se **deriva** de IANA con `package:timezone` (DST-correcto), nunca se persiste.

## Terminador solar — la zona más frágil (regresiones caras)

`lib/services/sun_terminator_service.dart` es matemática NOAA pura, sin `BuildContext`. Si tocas esto, lee antes los 3 archivos de test (`test/services/sun_terminator_service_test.dart`, `test/widgets/world_map_terminator_test.dart`, `test/widgets/world_map_widget_test.dart`).

- **Exige `DateTime.utc`**: hay `assert(utc.isUtc)` en `subsolarPoint` y `nightPolygons`. Pasar hora local revienta los asserts.
- `nightPolygons` (plural) devuelve **2 polígonos** en el caso general: el terminador se parte en `lng = 0` para evitar la arista 360° `180 → -180` que triangula una diagonal a la esquina inferior derecha. En equinoccio (`|subLat| < 0.5°`) devuelve 1-2 rectángulos partidos por el antimeridiano.
- Latitud clampada a ±`85.05112878` (límite Mercator).
- **Usa siempre `nightPolygons`.** `nightPolygon` (singular) es legacy: aplana y **devuelve solo el primer polígono**, silenciosamente incorrecto para render.
- El mapa **debe** usar `crs: Epsg3857NoRepeat` (`world_map_widget.dart:64`, `replicatesWorldLongitude => false`) junto a `_ContainWithFallback`. Volver al `Epsg3857` por defecto reintroduce el bug de envoltura infinita del antimeridiano. Cubierto por test.
- **El orden de capas está asertado**: `children[0]` `TileLayer`, `children[1]` `PolygonLayer`, `children[2]` `PolylineLayer`. El overlay nocturno va entre tiles y ruta. No reordenes.
- `currentUtcProvider` emite cada 5 min, **pero en `flutter test` devuelve un único valor** (detecta `TestWidgetsFlutterBinding`) para no dejar `Timer.periodic` pendiente (`binding.dart` `!timersPending`). Los tests que necesitan periodicidad usan `overrideWith`. **No introduzcas un `Timer.periodic` en un provider** sin ese mismo guard, o romperás `flutter test`.
- `lib/main.dart` tiene el hook `_forcedSolsticeUtc` para QA de solsticio; `main.dart` es el único sitio que inyecta `ProviderScope` overrides.
- `lib/utils/app_colors.dart` (`AppColors.nightOverlay` = `#000511` α0.45) es la fuente de verdad de tokens; `world_map_widget.dart` aún tiene consts privados duplicados (`_foggRed`, `_offlineBg`…). La migración de tokens está a medias: no asumas que todo pasa por `AppColors`.

## Datos y visor de desarrollo

- `assets/data/locations.json` — 304 ciudades `{meta, cities:[{name, asciiname, lat, lng, timezone}]}`. Está declarado en `pubspec.yaml` pero **ningún código Dart lo lee** (verificado: cero `rootBundle`/`loadString` en `lib/`). Solo lo consume el visor dev.
- `assets/data/sea_routes.json` — 9 rutas `{meta, routes:[{origin, destination, distanceKm, geometry: LineString}]}`. **No** está en los assets de `pubspec.yaml`.
- `tools/locations-map/` es Leaflet 1.9.4 vanilla: sin build, sin `node_modules`, sin `flutter run`. `serve_map.sh` **copia** `assets/data/locations.json` → `tools/locations-map/locations.json` antes de servir, y esa copia **está versionada**: si la regeneras, revisa el diff.
- `docs/origenes/cities15000.txt` (8.2 MB, GeoNames) es el origen versionado; los derivados pesados (`cities15000.json`, `.no-alts.json`) están gitignored y se regeneran con `docs/origenes/01_cities_to_json.py` y `02_strip_alternates.py`.
- GeoNames es **CC-BY 4.0**: la atribución es obligatoria y ya se renderiza en el mapa vía `RichAttributionWidget`. Si redistribuyes datos derivados, no la quites.
- Skills Python locales en `.opencode/skills/fogg-city-enricher/` y `.opencode/skills/fogg-sea-routes/` (esta última requiere `searoute==1.6.0`, offline, sin key). Ambas opera sobre `locations.json` sin mutarlo.

## Trampas de configuración (verificadas — la documentación anterior mentía)

- **`.gitignore` NO ignora `SENSIBLE/` ni `.env` ni `.worktrees/`.** No hay ninguna línea para ellos, y `SENSIBLE/.cache/city_enrich.json` **está versionado**. Si creas secretos, añade tú la regla antes de escribir nada, o versionarás una credencial. Confía en el fichero, no en la prosa.
- **Solo se consume `--dart-define`**, y en un único sitio: `String.fromEnvironment('MAP_TILE_URL')` (`world_map_widget.dart:21`). **No hay carga de `.env`**: no existe `dotenv` ni dependencia equivalente. `START_DATE`, `TIME_SCALE`, `INITIAL_BUDGET`, `OPEN_METEO_URL` que documenta el README **no se leen en ninguna parte** todavía.
- Hay **dos** `.spec-config.yml`: `docs/specs/` (canónico) y `specs/` (legacy duplicado). `specs/` está vacío salvo la config.

## Workflow

- **Specs**: `docs/specs/NN-slug.md`, con `> **Estado:**` en la cabecera. Máquina de estados `Borrador → Aprobado → Implementado`. La skill `/spec-impl` **solo arranca si el estado es Aprobado**, deriva la rama del nombre de fichero (`005-visor-...md` → `spec-005-visor-...`) y `AutoCreateBranch: true` en `docs/specs/.spec-config.yml` la crea sin preguntar.
- Actualiza `TODO.md` (secciones `Features` / `Fix` / `Tareas finalizadas`) al cerrar trabajo. Ojo: afirmaba que `shared_models` era el andamiaje planificado y ya no existe tal cual.
- No commits ni pushes sin petición explícita. Los mensajes de este repo son en castellano, imperativo, y en su mayoría **sin** Conventional Commits (solo algunos `feat(scope):`).
- `.opencode/node_modules/` y `node_modules/` (Playwright, solo devDependency raíz) no tienen nada que ver con la app Flutter: no los uses para "compilar" nada.
