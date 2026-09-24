# SPEC 003 — Visor de ciudades locations.json sobre OSM para desarrollo

> **Estado:** Implementado

> **Depende de:** SPEC 001 (WorldMapWidget, Epsg3857NoRepeat, SunTerminator), SPEC 002 (MainScaffold, AppColors, Package by Layer)

> **Fecha:** 2026-09-24

> **Objetivo:** Proveer una herramienta web de desarrollo que renderiza `assets/data/locations.json` sobre OpenStreetMap en el navegador para validar visualmente la distribución y la Regla del Este sin afectar el bundle PWA.

---

## 1. Por qué existe esta especificación

`assets/data/locations.json:2` es la única fuente de verdad del catálogo (GeoNames `cities15000` + Savile Row manual, `~243` ciudades globales con `lat/lng/timezone` IANA). Hoy no hay forma rápida de inspeccionarlo salvo `cat` o `jq`; errores de `lng`, `timezone` o cobertura Este-Oeste solo se detectan al ejecutar `FoggRoute.validated` o al ver `WorldMapWidget` dentro de la app (`lib/presentation/widgets/world_map_widget.dart:58`).

Esta spec cubre el hueco de **tooling de desarrollo**: un visor en navegador, fuera del bundle PWA, sobre OSM (`MAP_TILE_URL` por defecto `https://tile.openstreetmap.org/{z}/{x}/{y}.png`), que permita a usted y a futuros contribuidores verificar en segundos si una regeneración de `docs/origenes/01_cities_to_json.py` rompe la Regla del Este, deja huecos en el Pacífico o duplica Savile Row. Sin esta herramienta cada cambio de `locations.json` exige `flutter run -d chrome` + analizar logs.

No es mecánica jugable ni afecta a `FoggCity`/`FoggRoute`/`BudgetService`/`TimeEngine`. Es `tools/` puro, ignorable en producción.

---

## 2. Alcance

**En:**

- **Muestra todos los markers de locations.json sobre OSM — `tools/locations-map/index.html + app.js` — mapa Leaflet con cluster y popups** — carga `assets/data/locations.json` y pinta un `L.marker` por ciudad en `L.map` OSM
  - **Mapa:** `Leaflet 1.9.4 CDN` + `leaflet.markercluster 1.4.1` + `L.tileLayer('https://tile.openstreetmap.org/{z}/{x}/{y}.png', {maxZoom:18, attribution:'© OpenStreetMap contributors'})` — `center [20,0] zoom 2`, `minZoom 2 maxZoom 18`
  - **Marker:** `L.marker([lat,lng])` agrupado en `L.markerClusterGroup({maxClusterRadius:50})`, `icon` círculo `#C0392B` `8px` borde blanco `2px`, `popup` con `name` + `asciiname` + `lat,lng` a 6 decimales + `timezone` IANA + enlace `https://www.openstreetmap.org/?mlat=lat&mlon=lng`
  - **Atribución:** `RichAttribution` OSM siempre visible, abajo-izquierda, no queda bajo controles

- **Filtra y lista ciudades por nombre y timezone — `tools/locations-map/index.html + app.js + style.css` — panel lateral con búsqueda y pan al marker** — `input[type=search]` filtra en tiempo real y lista sincronizada hace `map.setView`
  - **UI:** panel `width 320px` derecha, `input placeholder "Filtrar por nombre o timezone..."`, `ul` con `max-height 60vh overflow-y:auto`, cada `li` muestra `name — timezone — lat,lng`, `click → map.setView([lat,lng], 6) + openPopup`, `contador "243 ciudades (12 filtradas)"`
  - **Filtro:** `case-insensitive` sobre `city.name + city.asciiname + city.timezone`, debounce `150ms`, si `0` resultados muestra `"Sin coincidencias"` sin vaciar mapa
  - **Sync:** al pulsar marker, hace `highlight` en lista; sin acoplamiento a `lib/domain/entities/fogg_city.dart`

- **Carga JSON fijo y por drag&drop local — `tools/locations-map/app.js:load` — fetch del asset y file input para comparar regeneraciones** — soporta `assets/data/locations.json` desde cualquier base path y JSON local arrastrado
  - **Fetch:** intenta `fetch('../../assets/data/locations.json')` luego `fetch('/assets/data/locations.json')` luego `fetch('./locations.json')` (copia opcional), parse `meta + cities`, valida `Array.isArray(cities) && cities[0].lat != null`; si falla muestra `banner error "No se pudo cargar locations.json — arrastra un JSON"` sin romper mapa
  - **Drag&drop:** `drop zone` sobre mapa + `input type=file accept=.json`, `FileReader` parsea, valida y reemplaza markers/poliínea en caliente; no persiste en disco, no toca `assets/data/locations.json` original
  - **Compat:** acepta `note?` opcional, ignora claves extra, `timezone` opaco (no valida IANA aquí)

- **Lanza el visor con un comando sin build — `tools/serve_map.sh + README` — servidor estático en 8090 sin node_modules ni Flutter** — `python3 -m http.server 8090 --directory tools/locations-map` documentado
  - **Script:** `tools/serve_map.sh` `chmod +x`, `port 8090` fijo, `echo "http://localhost:8090"` y `xdg-open` opcional, `trap SIGINT` limpio
  - **Estructura:** `tools/locations-map/index.html` `tools/locations-map/app.js` `tools/locations-map/style.css` + copia opcional `locations.json` para `file://` fallback; sin `package.json`, sin `node_modules`, sin `pubspec`
  - **Docs:** `README.md:Configuración` añade sección `"Visor locations.json (solo dev)"` con `MAP_TILE_URL` y comando `tools/serve_map.sh`; `SENSIBLE/` no tocado

- **Compartido:** tipografía y tokens desacoplados (`lib/utils/app_colors.dart:17` `foggRed #C0392B`, `offlineBg #F5F0E8` solo como referencia visual), `ThemeData` no usado (tool es HTML vanilla), `eu.elarreglador.pf` intacto, `Package by Layer` respetado (`tools/` fuera de `lib/`), `flutter analyze` no afectado si tool es standalone

**Fuera del alcance (para futuras especificaciones):**

- Edición drag-to-edit de markers y export a `locations.json` actualizado (requiere validación `timezone` IANA y escritura disco — spec dedicada si se necesita).
- Validación DST `TimezoneService.offsetAt` o `package:timezone` en el visor (solo muestra `timezone` string; validación real queda en `lib/services/timezone_service.dart`).
- Integración `WorldMapWidget` con `SunTerminatorService` nocturno o `Epsg3857NoRepeat` exacto (visor usa Leaflet `EPSG3857` estándar; replicar `Epsg3857NoRepeat` es follow-up si se quiere paridad 100%).
- PWA offline `Hive`, `manifest.json`, `service_worker` e instalable (visor es solo dev, no PWA).
- Persistencia de filtro/zoom en `localStorage` o `IndexedDB`.
- Autenticación, presupuesto `BudgetService` o `StoryGenerator`.
- Soporte satélite/oscuros `MAP_TILE_URL` alternativos salvo OSM por defecto (toggle satélite es follow-up).

---

## 3. Modelo de datos

Esta especificación **no introduce entidades de dominio persistidas**. Reutiliza `assets/data/locations.json` tal cual. Toda transformación es efímera en memoria del navegador.

```json
// assets/data/locations.json — fuente de verdad (extracto real)
{
  "meta": {
    "project": "eu.elarreglador.pf",
    "name": "Fogg Cities Catalog — La Herencia de Phoebe",
    "version": "1.0.1",
    "update": "2026-09-24",
    "source": "GeoNames cities15000 (CC-BY 4.0) + manual Savile Row",
    "attribution": "GeoNames CC-BY 4.0 — https://www.geonames.org"
  },
  "cities": [
    {
      "name": "Londres",
      "asciiname": "London",
      "lat": 51.50853,
      "lng": -0.12574,
      "timezone": "Europe/London"
    },
    {
      "name": "Bombay",
      "asciiname": "Mumbai",
      "lat": 19.07283,
      "lng": 72.88261,
      "timezone": "Asia/Kolkata",
      "note": "Nombre narrativo 'Bombay' (exónimo histórico)"
    }
  ]
}
```

```js
// tools/locations-map/app.js — estructuras efímeras (no persistidas)
// City leída tal cual del JSON:
const city = { name, asciiname, lat, lng, timezone, note? };

// Para Regla del Este desenrollada (mirroring FoggRoute:106):
let offset = 0;
let prevUnwrapped = citiesSorted[0].lng;
const latlngsEast = citiesSorted.map(c => {
  let curr = c.lng + offset;
  if (curr <= prevUnwrapped) { curr += 360; offset += 360; }
  prevUnwrapped = curr;
  return [c.lat, c.lng]; // Leaflet usa lng real para marker, unwrapped solo para validación
});

// Estado UI efímero (no Hive):
const uiState = { filterText: "", showEastTrace: true, selectedCity: null, violations: [] };
```

Convenciones:

- Coordenadas: `lat` en `[-90,90]`, `lng` en `[-180,180]` real en JSON; `lng` desenrollado solo en memoria para validación Este (puede superar `180` y llegar a `~540` en vuelta al mundo simulada).
- `timezone` IANA opaco (ej. `Europe/Paris`, `Asia/Tokyo`, `Pacific/Tarawa`); no se deriva offset numérico en visor.
- `order` no existe en `locations.json`; el visor ordena por `lng` desenrollado para trazo Este; `WorldMapWidget` seguirá usando `FoggCity.order` en app productiva.
- Sin persistencia entre sesiones: recarga resetea filtro y trazo.

Si en el futuro se necesita edición, se añadirá `tools/locations-map/export.js` que serializa `cities` a `JSON.stringify({meta, cities}, null, 2)` sin cambiar este modelo base.

---

## 4. Plan de implementación

Cada paso deja el repo ejecutable y `flutter analyze` verde (tool standalone no afecta a Flutter salvo docs).

1. **Crea la estructura del visor** — `tools/locations-map/index.html` esqueleto `<!DOCTYPE html>` con `head` Leaflet `1.9.4 CDN` (`leaflet.css` + `leaflet.js` + `leaflet.markercluster@1.4.1` CSS/JS), `div#map` `height 100vh`, `div#side-panel` `width 320px`, `div#drop-zone` oculto. Prueba: `python3 -m http.server 8090 --directory tools/locations-map` muestra mapa OSM gris sin markers pero con attribution y zoom 2.

2. **Implementa carga de locations.json con fallbacks** — `tools/locations-map/app.js:load` con `async function loadCities()` que intenta `fetch('../../assets/data/locations.json')`, luego `'/assets/data/locations.json'`, luego `'./locations.json'`, `JSON.parse`, valida `cities.length >0 && typeof cities[0].lat === 'number'`. Si falla, renderiza `banner error` + permite drag&drop. Prueba: `fetch` en Chrome carga 243 ciudades (ver `console.log(cities.length)`).

3. **Pinta markers con cluster y popups** — `tools/locations-map/app.js:markers` crea `L.markerClusterGroup` y `cities.forEach(c => L.marker([c.lat,c.lng]).bindPopup(...))`, añade a `map`. Prueba: zoom 2 muestra clusters numerados, zoom 6 desagrupa, click popup muestra `name / asciiname / lat,lng / timezone` + link OSM.

4. **Añade panel lateral con lista y filtro** — `tools/locations-map/style.css` + `app.js:filter` con `input#filter` `input event debounce 150ms`, `ul#city-list` render con `citiesFiltered.map`, `click li → map.setView([lat,lng],6)`, resaltado `li.active`. Prueba: escribir `"tokyo"` deja 1–2 resultados, lista y markers filtrados sincronizados, contador actualizado.

5. **Implementa trazo Este desenrollado y highlight violaciones** — `tools/locations-map/app.js:eastCheck` con algoritmo desenrollado idéntico a `FoggRoute._isEastward` (`lib/domain/entities/fogg_route.dart:106`), `L.polyline` segmentada por antimeridiano (si `lng` cruza `180→-180` crea nuevo polyline), `violations` array con `prev, curr, lngPrev, lngCurrUnwrapped`. Checkbox `#show-east` toggle. Prueba: con `locations.json` actual `0 violaciones`; con JSON de prueba `[{lng:10},{lng:5}]` resalta rojo discontinuo.

6. **Añade drag&drop y file input local** — `tools/locations-map/app.js:dragdrop` con `map.on('dragover')` + `drop` `FileReader.readAsText`, `JSON.parse` y re-render markers/polyline sin recargar página; `input#file` `change` equivalente. No escribe disco. Prueba: arrastrar `locations.json` editado con 1 ciudad nueva aparece marker instantáneo.

7. **Crea script de lanzamiento** — `tools/serve_map.sh` (`#!/usr/bin/env bash` + `python3 -m http.server 8090 --directory "$(dirname "$0")/locations-map"`), `chmod +x`, `README.md:Configuración` nueva sección `"Visor locations.json (solo dev)"` con `MAP_TILE_URL` y ejemplo `tools/serve_map.sh` + `http://localhost:8090`. Opcional copia `assets/data/locations.json` a `tools/locations-map/locations.json` para `file://` fallback. Prueba: `./tools/serve_map.sh` abre Chrome, `flutter analyze` sigue verde, `flutter test` sin regresión.

8. **Verificación visual y de calidad** — `flutter analyze` verde, `http://localhost:8090` sin errores consola, `L.markerCluster` no rompe en `lng ±180` (Evensk `159`, Beringovsky `179`, Egvekinot `-179`), attribution OSM visible, panel no tapa controles zoom. Actualiza `docs/specs/003-visor-locations-mapa.md` estado a `Implementado` si procede (sin secretos, diff limpio). tambien se deben hacer capturas del navegador para verificar correcto funcionamiento

---

## 5. Criterios de aceptación

- [ ] `tools/locations-map/index.html` existe y `http://localhost:8090` (o `python3 -m http.server 8090 --directory tools/locations-map`) carga mapa OSM sin errores en consola (status `200` para `leaflet.css/js` CDN).
- [ ] `L.tileLayer('https://tile.openstreetmap.org/{z}/{x}/{y}.png')` visible con `attribution '© OpenStreetMap contributors'` abajo-izquierda y `maxZoom 18`.
- [ ] Número de `L.marker` renderizados coincide exactamente con `assets/data/locations.json:10` `cities.length` (≈243) cuando no hay filtro; `L.markerClusterGroup` agrupa en zoom `2` y desagrupa en zoom `6`.
- [ ] Cada popup muestra `name` + `asciiname` + `lat,lng` a 6 decimales + `timezone` IANA + enlace `https://www.openstreetmap.org/?mlat=lat&mlon=lng` que abre OSM en nueva pestaña.
- [ ] `input#filter` filtra `case-insensitive` sobre `name|asciiname|timezone` con debounce `150ms`; lista lateral y clusters se actualizan, contador muestra `"243 ciudades (N filtradas)"`, `0` resultados muestra `"Sin coincidencias"` sin vaciar mapa base.
- [ ] Click en `li` de la lista hace `map.setView([lat,lng], 6)` y `openPopup` del marker correspondiente; click en marker resalta `li.active` en lista.
- [ ] `Checkbox "Mostrar trazo Este"` activo por defecto dibuja `L.polyline` roja `#C0392B` `weight 3` `opacity 0.95` siguiendo `lng` desenrollado (mismo algoritmo que `FoggRoute:106`); desmarcar oculta todas las polilíneas sin recargar markers.
- [ ] Cruce antimeridiano (`Beringovsky 179 → Egvekinot -179`, `Tokio 139 → Adak -176`) no genera línea parásita `180→-180` cruzando el mapa; se segmenta en dos `L.polyline` con quiebre en `180/-180` y lat interpolada Mercator (o al menos sin línea horizontal infinita).
- [ ] `violations` detectadas correctamente: con `locations.json` actual `0 violaciones` y con JSON sintético `[{lng:10},{lng:5}]` resalta `dashArray 6 6` rojo y lista `"1 violación: CityB lng 5 <= 10"`.
- [ ] `fetch` carga `assets/data/locations.json` desde `../../assets/data/locations.json` (cuando se sirve desde `tools/locations-map/`) y fallback `'/assets/data/locations.json'` sin `CORS` en `http://localhost:8090`; si `fetch` falla muestra `banner error` sin romper mapa.
- [ ] Drag&drop de un `locations.json` local sobre el mapa y `input type=file` reemplazan markers/polyline en caliente sin recargar página y sin escribir disco; `FileReader` valida `Array.isArray(cities)` y muestra `popup error` si JSON inválido.
- [ ] `tools/serve_map.sh` existe, es ejecutable (`chmod +x`), lanza `http://localhost:8090` y `flutter analyze` permanece verde (tool standalone no añade `pubspec.yaml` ni `node_modules`).
- [ ] `README.md` documenta sección `"Visor locations.json (solo dev)"` con `MAP_TILE_URL` y comando `tools/serve_map.sh`; sin secretos en repo, diff limpio.
- [ ] Panel lateral `320px` + controles zoom Leaflet `top-left` no quedan ocultos tras attribution y no tapan `◻○△` en Chrome móvil DevTools `412x915`; mapa es usable en `width 412` sin scroll horizontal.

---

## 6. Decisiones tomadas y descartadas

- **Sí:** `Leaflet 1.9.4 CDN + leaflet.markercluster 1.4.1 vanilla JS sin bundler` en `tools/locations-map/`. Por qué: KISS/YAGNI, cero `node_modules`/`package.json`/`Vite`, arranca en `1s` con `python -m http.server`, suficiente para ~243 markers, CDN cacheado, sin afectar `pubspec.yaml`. No: `flutter_map` dev page en `lib/presentation/pages/dev_locations_map_page.dart` — descartado para MVP por obligar `flutter run` + recompilar + acoplar tooling dev al bundle PWA; se deja como follow-up si se quiere verificar `Epsg3857NoRepeat`+terminador conjunto. No: `MapLibre GL` — descartado por sobrediseño vectorial y token API innecesario para OSM raster.

- **Sí:** `tools/locations-map/` versionado fuera de `lib/` (Package by Layer respetado). Por qué: `tools/` es convención Dart/Flutter para scripts dev, no se publica en `flutter build web`, `flutter analyze` lo ignora, `git` lo versiona para que cualquier contribuidor tenga el visor sin instalación extra. No: carpeta `frontend/tools` o `web/tools` — descartado por no existir `frontend/` en este repo (`pubspec.yaml:1` raíz). No: `.worktrees/` o `SENSIBLE/` — ignorados por `.gitignore`, no versionados.

- **Sí:** `L.markerClusterGroup({maxClusterRadius:50})` obligatorio. Por qué: `243` markers globales son ilegibles sin cluster en zoom `2`; cluster reduce overdraw y mantiene `60fps` pan. No: `L.marker` plano sin cluster — descartado por colisión de labels en Europa (`Londres, París, Amsterdam` en `~5°`) y por coste `243` popups simultáneos.

- **Sí:** Trazo Este desenrollado en JS espejo de `FoggRoute._isEastward` `lib/domain/entities/fogg_route.dart:106` con `offset +=360`. Por qué: la Regla del Este solo es testeable desenrollando (Savile Row `-0.14` tras `Leningradsky 178` es Este si `lng_u = 359.85`), mismo invariante que `FoggRoute.validated`; visor debe validar igual que dominio. No: ordenar por `lng` `[-180,180]` sin desenrollar — descartado por falsos positivos en Pacífico (`Tokio 139 → Adak -176` parecería violación). No: reutilizar Dart `FoggRoute` vía `dart:js` — descartado por complejidad interop vs copiar `15` líneas JS.

- **Sí:** Segmentación polilínea por antimeridiano con dos `L.polyline` (quiebre `180→-180`). Por qué: `FoggRoute.polylineSegments:55` ya demuestra que `180→-180` genera línea parásita; Leaflet `wrapLng` replicaría trazo infinito si no se corta. No: `L.polyline` única con `noWrap false` — descartado por línea horizontal cruzando Atlántico en `Tokio→Adak`.

- **Sí:** `fetch` con triple fallback + drag&drop local, sin escritura disco. Por qué: el visor se sirve desde `tools/locations-map/` (`../../assets/...`) pero también puede servirse desde raíz (`/assets/...`); fallback cubre ambos sin config, y drag&drop permite comparar `docs/origenes/cities15000.no-alts.json` sin copiar a `assets/`. No: `dart:io` `File` read — descartado por ser solo `flutter run`, no `http.server`. No: `localStorage` persistencia del JSON arrastrado — descartado YAGNI, recarga resetea a `assets/data/locations.json` canónico.

- **Sí:** Solo lectura en MVP, sin `draggable marker → export`. Por qué: editar `lat/lng` en navegador invita a divergencia entre `assets/data/locations.json` canónico y copia local sin validación `timezone` IANA; edición requiere `strip_alternates.py` + `cities_to_json.py` pipeline — otra spec si se automatiza. No: `marker.dragging.enable() + JSON.stringify` export — descartado para MVP por riesgo de generar `locations.json` inválido sin `meta`/`asciiname`.

- **Sí:** Puerto fijo `8090` y `tools/serve_map.sh` bash con `python3`. Por qué: `8090` no colisiona con `flutter run 8080` ni `dart_frog 8080`, `python3` está en toda distro sin `npm`, `shell` es más portable que `Makefile`. No: `npx serve`/`vite` — descartado por requerir `node` y `npm install`. No: puerto aleatorio — descartado por romper bookmark `http://localhost:8090`.

- **Sí:** Documentación en `README.md:Configuración` junto a `MAP_TILE_URL`/`OPEN_METEO_URL`. Por qué: el visor es discoverable donde ya se documenta `MAP_TILE_URL`; evita `docs/tools.md` huérfano. No: `SENSIBLE/.env` — descartado por no haber secretos OSM.

- **Sí:** Definición rápida sin ronda exhaustiva de preguntas adicionales (usuario pidió "crea el documento completo"). Registrado aquí: se asumen recomendaciones de Fase 2 del plan; cualquier divergencia se ajusta en revisión `Borrador → Aprobado` sin bloquear entrega.

---

## 7. Riesgos identificados

| Riesgo | Mitigación |
| --- | --- |
| Tiles OSM `429 Too Many Requests` si `userAgentPackageName` falta o se abusa de `tile.openstreetmap.org` en dev | Usar `L.tileLayer` con `attribution` OSM obligatoria y `maxZoom 18` (no `19`), no precargar tiles fuera de viewport; si `429`, documentar fallback `MAP_TILE_URL` alternativo en `README.md` (ej. `https://{s}.tile.openstreetmap.org/...`) |
| `fetch` falla con `file://` (`CORS` nulo) si usuario abre `index.html` doble-click sin `http.server` | `try/catch` fetch + banner `"Abre con tools/serve_map.sh — file:// bloqueado por CORS"` + `drop zone` como vía alternativa que no requiere `fetch` |
| `leaflet.markercluster` rompe en `lng ±180` (Beringovsky `179`, Egvekinot `-179`, `lng 178.39` Leningradsky) | No usar `worldCopyJump true`; `L.map({worldCopyJump:false})` por defecto, cluster usa `lng` real `[-180,180]` sin desenrollar, solo polilínea usa unwrapped |
| Polilínea antimeridiano genera línea parásita `180→-180` cruzando mapa | Segmentar en dos `L.polyline` como `FoggRoute.polylineSegments:55` (quiebre `latAt180` interpolado Mercator-Y), test visual `Tokio→Adak` y `Leningradsky→Suva` |
| `243` markers + `241` segmentos polilínea degradan `60fps` en móvil | Cluster `maxClusterRadius 50` + polilínea `weight 3` sin `smoothFactor` alto (`smoothFactor 1.0`), `L.polyline` canvas `preferCanvas:true` si se detecta lag |
| `locations.json` futuro con `lat` `85.05` clamp Mercator excede `lat 90` y Leaflet corta tile | Validar `lat` en `[-85.051,85.051]` al cargar y `clamp` a `85.051` con `warn` en consola, igual que `FoggRoute._maxMercatorLat:27` |
| Usuario espera edición y exporta JSON divergente sin `meta.version` ni `asciiname` | MVP solo lectura documentado en `Fuera`; si en el futuro se añade export, se valida `meta` + `attribution GeoNames CC-BY` obligatoria antes de descargar |
| `flutter analyze` considera `tools/` como `lib/` y reporta `lint` JS como error Dart | `analysis_options.yaml` ya excluye `build/**`; añadir `exclude: - tools/**` si `analyzer` escanea JS (no debería, pero se deja nota en spec-impl) |

---

## 8. Lo que **no** está en esta especificación

- Edición de coordenadas por arrastre y exportación de `locations.json` (otra spec si se automatiza el pipeline `docs/origenes/`).
- Validación IANA `timezone` con `package:timezone` o cálculo `offsetIANA(utc, city.timezone)` DST-correcto (queda en `lib/services/timezone_service.dart`).
- Capa día/noche `SunTerminatorService` ni `Epsg3857NoRepeat` exacto en Leaflet (el visor usa `EPSG3857` estándar; paridad 100% con `WorldMapWidget:58` es follow-up).
- PWA offline `Hive`, `manifest.json`, `service_worker`, instalable o `display:standalone`.
- Persistencia de filtro/zoom, `localStorage`, `IndexedDB` o `Hive` para preferencias del visor.
- Presupuesto `BudgetService`+`Ledger`, `EventEngine`, `DiaryService`/`StoryGenerator` o integración Open-Meteo.
- Toggle satélite, tiles oscuros o ajuste `AppColors.nightOverlay` `alpha 0.45` en el visor (OSM claro por defecto).
- Backend `InMemoryBackend` / `Dart Frog` / `Supabase` y `TimetableService`/`PositionService`.

> Cada uno de ellos, si aterriza, irá en su propia spec.

---

## 9. Referencias

- `assets/data/locations.json:2` catálogo canónico (GeoNames CC-BY 4.0 + Savile Row manual, `243` ciudades, `version 1.0.1`)
- `lib/domain/entities/fogg_city.dart:1` `FoggCity` (`name`, `lat`, `lng`, `timezone` IANA, `order`)
- `lib/domain/entities/fogg_route.dart:55` `polylineSegments` y `lib/domain/entities/fogg_route.dart:106` `_isEastward` desenrollado (invariante Regla del Este)
- `lib/presentation/widgets/world_map_widget.dart:58` `Epsg3857NoRepeat` y `lib/presentation/widgets/world_map_widget.dart:240` orden capas (Tile < Polygon < Polyline < Marker)
- `lib/utils/app_colors.dart:11` `nightOverlay #000511 alpha 0.45` y `lib/services/sun_terminator_service.dart:1` terminador solar (referencia visual, no implementado en visor)
- `README.md:Configuración` `MAP_TILE_URL` `https://tile.openstreetmap.org/{z}/{x}/{y}.png` y `OPEN_METEO_URL` sin key
- `AGENTS.md` — `Package by Layer`, `eu.elarreglador.pf`, Regla del Este, Sin avión, Ciclo Fogg, `TIME_SCALE` solo dev
- `TODO.md:12` y `TODO.md:14` ruta Este 5 ciudades MVP (Hoy `mockFoggRoute` 6 ciudades, visor valida catálogo completo)
- `docs/origenes/01_cities_to_json.py` y `docs/origenes/02_strip_alternates.py` pipeline generación `locations.json`
- Leaflet `https://leafletjs.com` y `leaflet.markercluster` `https://github.com/Leaflet/Leaflet.markercluster` (CDN `unpkg.com`)

---

## 10. Preguntas abiertas (resueltas por esta spec)

- Tool standalone Leaflet vanilla sin bundler en `tools/locations-map/` ✅
- Puerto `8090` + `tools/serve_map.sh` con `python3 -m http.server` ✅
- `markerCluster` obligatorio + popup `name/asciiname/lat,lng/timezone` ✅
- Trazo Este desenrollado `FoggRoute` espejo + highlight violaciones ✅
- Fetch triple fallback + drag&drop local, solo lectura ✅
- Documentado en `README.md:Configuración`, sin tocar `SENSIBLE`, sin nuevas deps ✅

> Siguiente paso tras aprobar esta spec: ejecutar `spec-impl 003-visor-locations-mapa` (pasos §4) con TDD visual + `flutter analyze` verde.

