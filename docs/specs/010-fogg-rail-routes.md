# SPEC 010 — Skill local de rutas ferroviarias reales con OpenRailRouting (5 ciudades más cercanas al Este)

> **Estado:** Implementado

> **Depende de:** `assets/data/locations.json` (257 ciudades, orden Este desenrollado), SPEC 004 (patrón de skill, `anchor_to_cities`, esquema de ruta anclada), SPEC 006 (patrón de pool, Regla del Este, fallback al Oeste, caché y cortesía), SPEC 008 (cobertura unión mar ∪ tierra), `TODO.md:28` (trazado GeoJSON real, OpenRailwayMap)

> **Fecha:** 2026-10-10

> **Objetivo (una frase):** Proveer una skill local Python que, usando la instancia pública de OpenRailRouting (GraphHopper ferroviario) con el perfil `non_tgv` a un máximo de 1 petición por segundo, calcule para cada ciudad de `locations.json` sus rutas ferroviarias hacia las 5 ciudades más cercanas al Este y las persista **ya simplificadas** en `assets/data/rail_routes.json` con el primer y el último vértice anclados a la ciudad.

---

## 1. Por qué existe esta especificación

El juego promete 80 días de viaje hacia el Este **sin avión**, con presupuesto y tiempo reales, y `TODO.md:28` nombra explícitamente **OpenRailwayMap** como fuente del trazado ferroviario real. Hoy el catálogo ya tiene mar (`sea_routes.json`, SPEC 004) y carretera (`car_routes.json`, SPEC 006/007/008); falta el ferrocarril, que en el juego es el modo lento, barato y de larga distancia por excelencia.

A diferencia del mar, no hay paquete offline equivalente a `searoute`, y a diferencia de la carretera, el servidor demo de OSRM **no sirve datos de tren** (SPEC 006 §6: `driving`, `foot` y `bike` devuelven respuestas byte-idénticas). La fuente realista sin credenciales es el **GraphHopper ferroviario de Geofabrik, OpenRailRouting**, que expone una instancia pública en `https://routing.openrailrouting.org` con perfiles de tren.

La investigación de campo (ver §10) fija cuatro hechos que condicionan todo el diseño: la instancia es **global** (no solo Europa), el perfil robusto es `non_tgv` (no `all_tracks`), **no existe `/matrix`** (no se puede podar candidatas con una tabla como en SPEC 006), y la geometría llega sin simplificar (hasta 30.896 vértices en Estambul→Bombay), por lo que **la skill debe simplificarla antes de escribir** — encargo explícito del Señor.

---

## 2. Alcance

**En:**

- **Traza rutas ferroviarias hacia el Este — `.opencode/skills/fogg-rail-routes/rail_route.py` — elige como mucho 5 destinos por origen** — para cada ciudad toma sus 5 vecinas más próximas por círculo grande que cumplan la Regla del Este, consulta a OpenRailRouting y se queda con las que tienen vía
  - **Pool acotado:** los candidatos salen de las 5 ciudades más cercanas, no de un recorrido hasta reunir 5 válidas
  - **Techo de peticiones:** como mucho `pool` `/route` por origen en dirección Este; sin `/matrix`, que el servidor no ofrece

- **Consulta el servidor sin pasarse de 1 petición por segundo — `rail_route.py:router_get` — espera 1,2 s entre llamadas y reintenta los 429** — `User-Agent: eu.elarreglador.pf/1.0`; backoff de 5 s, 15 s y 45 s con tres reintentos; timeout de 60 s
  - **Aviso de servicio:** la instancia es "experimental use only, not for production", sin SLA
  - **Corte por horas:** `--only N` escribe lo acumulado y sale con código 0

- **Fallback al Oeste — `rail_route.py:build_pool(direction)` — completa el mínimo si un origen no llega a 2 rutas Este** — pool oeste (`-180 <= deltaLng < 0`) que solo se consulta cuando faltan rutas para llegar a `minRoutesPerOrigin`
  - **Motivo:** una ciudad que no puede ser origen bloquea al jugador; la Regla del Este cede (precedente SPEC 006 §12)
  - **`heading`:** `east` o `west` coherente con el signo de `deltaLng`

- **Descarta lo que no tiene vía — `rail_route.py:build_route` — registra por qué se cae cada ruta** — `PointNotFound` (ciudad sin estación cerca), `NoRoute` (redes de tren no conectadas, p. ej. Bombay→Tokio por el vacío de Myanmar), `429` agotado, timeout
  - **Efecto colateral útil:** recuento de ciudades sin red, análogo a `citiesWithoutPort` (SPEC 004) y `unroutableCities` (SPEC 006)

- **Simplifica la geometría antes de escribirla — `rail_route.py:simplify` — Douglas-Peucker sobre la polilínea decodificada** — el servidor no ofrece `simplified` (a diferencia de OSRM); sin simplificar, un lote completo pesaría decenas de MB
  - **Entrada:** `points_encoded=true` (polilínea Google precision 5), la representación más compacta que sirve el servidor
  - **Tolerancia:** perpendicular Haversine en metros, `SIMPLIFY_M` por defecto; se eliminan vértices consecutivos duplicados antes y después

- **Ancla la geometría a la ciudad — `rail_route.py:anchor_to_cities` — el primer y el último vértice son los de `locations.json`** — el servidor devuelve el punto enganchado a la vía, no el centro urbano
  - **Paridad con `sea_routes.json`/`car_routes.json`:** el visor y Dart ya esperan geometrías de ciudad a ciudad
  - **Nunca sustituye:** antepone y pospone el vértice; el camino ferroviario intermedio queda intacto

- **Escribe un artefacto ferroviario — `assets/data/rail_routes.json` — clona el esquema `car_routes.json` v1.1.0** — `{meta, routes[]}` con `origin/destination/…/geometry` y `railOrigin`/`railDest` en lugar de `roadOrigin`/`roadDest`
  - **Campos nuevos:** `profile`, `dataTimestamp` (versión de datos del servidor) y `simplifyMeters` en `meta`

- **Añade el tiempo de trayecto — `routes[].durationHours` — dato que el servidor da gratis** — `paths[0].time` (ms) / 3.600.000, con un decimal; el juego lo necesita para `TimeEngine`

- **Rechaza perfiles que no sean del servidor — `rail_route.py:main` — solo la lista blanca `non_tgv|tgv_all|all_tracks|all_tracks_1435|tramtrain`** — cualquier otro valor sale con código 1 y el motivo, en lugar de escribir un fichero mentiroso
  - **Default `non_tgv`:** es el único perfil que engancha de forma fiable con coordenadas de ciudad (el resto cae en cocheras, metro o alta velocidad suelta)

- **Acepta pares curados — `rail_route.py --pair "ORIGEN|DESTINO"` — corredor explícito marcado `explicit: true`** — para asegurar trayectos que el pool no elige (p. ej. Londres→París→Estambul→Bombay); no cuenta para `limitPerOrigin` y hace merge sobre el fichero

- **Añade el raíl a la cobertura — `tools/route_coverage.py` — la unión pasa a ser mar ∪ tierra ∪ raíl** — carga `rail_routes.json` si existe y lo suma a `outbound`/`inbound`
  - **Sin regresión:** hoy la cobertura mar ∪ tierra está verde (0 pendientes); el raíl solo puede aumentar la cobertura

- **Documenta la skill — `.opencode/skills/fogg-rail-routes/SKILL.md` — política, perfiles, simplificación y riesgos medidos** — incluye la tabla de perfiles, el coste del lote y el estado real del servidor

**Compartido:** estilo de SPEC 006 (`--city`, `--dry-run`, `--out`, `--limit`, `--pool`, `--only`, `--resume`, `validate_dataset`, `[INFO]/[WARN]/[SKIP]/[ERROR]` en castellano); `locations.json` en solo lectura; helpers geodésicos con el modelo de `land_route.py` (`haversine`, `haversine_sum`, `eastward_delta`, `normalize_lng`, `anchor_to_cities`, `crosses_antimeridian`, `PROJECT_ROOT` con `parents[3]`); caché en `SENSIBLE/.cache/fogg-rail-routes/{profile}/`; `Package by Layer`; `eu.elarreglador.pf`; `flutter analyze` y `flutter test` verdes (la skill es Python, fuera de `lib/`).

**Fuera del alcance (para futuras especificaciones):**

- Botón, capa y color del visor `tools/locations-map` para rutas ferroviarias (spec propia, acordada).
- Consumo desde `WorldMapWidget`/`PolylineLayer`/`TransportMode.train`, `pubspec.yaml` o cualquier cambio en `lib/`.
- `rail_routes.json` con perfiles por ruta simultáneos, o alta velocidad y convencional en el mismo fichero.
- `--close-gaps` ferroviario (la cobertura ya está cerrada por mar ∪ tierra y la unión con raíl solo suma).
- OSRM propio, OpenRailRouting propio (`config.yml` + `.osm.pbf` + `graph-cache/`) o nuevas fuentes de datos.
- Precio del viaje, `BudgetService`, `Ledger`, `TimeEngine`, `EventEngine`.
- Estaciones como entidad separada: no se resuelven nombres de estación; la ciudad es el ancla (acuerdo del Señor).
- Ramas de git: la spec se implementa en la rama actual.

---

## 3. Modelo de datos

### 3.1 `assets/data/rail_routes.json` (nuevo, artefacto derivado)

```jsonc
{
  "meta": {
    "project": "eu.elarreglador.pf",
    "name": "Fogg Rail Routes — Herencia de Phoebe",
    "version": "1.0.0", "generated": "2026-10-10",
    "tool": "fogg-rail-routes", "profile": "non_tgv",
    "routerServer": "https://routing.openrailrouting.org",
    "engine": "OpenRailRouting (GraphHopper fork, Geofabrik)",
    "dataTimestamp": "2026-10-08T04:00:00Z",
    "units": "km", "limitPerOrigin": 5, "candidatePool": 5, "maxEastDeg": 180,
    "minRoutesPerOrigin": 2, "simplifyMeters": 150,
    "origins": 257, "routes": 0,
    "originsWithoutRoute": 0, "unroutableCities": 0,
    "crossesAntimeridian": 0,
    "eastRule": "heading east: 0 < deltaLng(cityDest - cityOrigin) <= 180 (desenrollado); heading west: -180 <= deltaLng < 0, solo como fallback cuando un origen tiene menos de minRoutesPerOrigin rutas al Este",
    "poolRule": "los pool candidatos más cercanos por círculo grande dentro de maxEastDeg en cada dirección; se descartan los que OpenRailRouting no puede enrutar; el pool oeste solo se consulta si el este no llega a minRoutesPerOrigin rutas",
    "geometry": "LineString [lng,lat] de ciudad a ciudad: el primer y el último vértice son las coordenadas de la ciudad de locations.json y entre medias va la vía de OpenRailRouting decodificada (points_encoded) y simplificada con Douglas-Peucker",
    "distanceNote": "distanceKm es paths[0].distance de GraphHopper /1000; durationHours es paths[0].time /3.600.000. Ninguno se recalcula desde la geometría",
    "attribution": "© OpenStreetMap contributors (ODbL); routing courtesy of OpenRailRouting (Geofabrik) / GraphHopper",
    "source": "OpenRailRouting demo (non_tgv) + GeoNames cities15000"
  },
  "routes": [
    {
      "origin": "Lisboa", "originLat": 38.72509, "originLng": -9.1498,
      "destination": "Madrid", "destinationLat": 40.4165, "destinationLng": -3.70256,
      "distanceKm": 687.7, "durationHours": 6.3,
      "heading": "east",
      "railOrigin": { "lat": 38.71395, "lng": -9.12247, "snapKm": 3.4 },
      "railDest":   { "lat": 40.40661, "lng": -3.69061, "snapKm": 2.1 },
      "geometry": { "type": "LineString", "coordinates": [[-9.1498, 38.72509], "…", [-3.70256, 40.4165]] }
    }
  ]
}
```

Convenciones:

- `coordinates` siempre en `[-180, 180]`, orden GeoJSON `[lng, lat]`, redondeadas a `COORD_PRECISION` (5 decimales).
- `originLat/originLng` conservan la precisión íntegra de `locations.json`; la igualdad con los extremos de la geometría es a 5 decimales, igual que en SPEC 004/006.
- `railOrigin/railDest` documentan el enganche a la vía: son el primer y el último vértice devueltos por el servidor (antes del anclaje), y `snapKm` la distancia Haversine centro→vía con 1 decimal. **Sin `name`:** GraphHopper no devuelve el nombre de la estación en `/route`.
- `durationHours = time_ms / 3.600.000`, un decimal. Sin modelo de tráfico ni horarios: es la estimación estática del perfil `non_tgv`.
- `heading` coherente con el signo de `eastward_delta(cityOrigin, cityDest)`; `explicit: true` solo en rutas de `--pair`.
- Sin `port*` ni `road*`; sin `weight`. Reescritura completa salvo con `--resume` (merge). `meta.generated` es la fecha de esa generación.

### 3.2 Estructuras efímeras (no persistidas)

```python
candidate = {"city": {...}, "gcKm": 1452.8}                     # ordena por Haversine; no hay distancia de red previa
snapped   = {"lat": 38.71395, "lng": -9.12247, "snapKm": 3.4}   # primer/último vértice de la polilínea decodificada
args      = {"profile": "non_tgv", "limit": 5, "pool": 5, "only": None, "resume": False, "dry_run": False}
```

- La caché guarda la respuesta cruda del servidor indexada por `sha1(url)`, nunca estas estructuras.
- `points_encoded=true` viaja por la red; el decodificador produce la lista `[lng, lat]` que consume `simplify`.

### 3.3 Adición a `tools/route_coverage.py`

```python
RAIL_ROUTES_PATH = PROJECT_ROOT / "assets" / "data" / "rail_routes.json"
# compute_coverage(cities, sea, car, rail): la unión pasa a ser mar ∪ tierra ∪ raíl,
# cargando rail_routes.json solo si existe (para no romper si aún no se ha generado).
```

---

## 4. Plan de implementación

1. **Crea la estructura y el esqueleto** — `mkdir -p .opencode/skills/fogg-rail-routes SENSIBLE/.cache/fogg-rail-routes`; `SKILL.md` con `name`/`description`/`cuándo usar`/`fuentes`/`flujo`/perfiles/coste/riesgos; `requirements.txt` vacío (stdlib puro); `rail_route.py` con `argparse --profile non_tgv --city --limit 5 --pool 5 --only N --resume --dry-run --pair --out`. Prueba: `python3 rail_route.py --help` funciona y `--profile foo` sale con código 1 listando la lista blanca.

2. **Carga de catálogo y geometría básica** — `load_locations()` con el modelo de `land_route.py` (validación de campos y `lng_u` desenrollado); `eastward_delta`, `haversine`, `haversine_sum`, `normalize_lng`, `crosses_antimeridian`. Prueba: `--city "Lisboa" --dry-run` lista las 5 candidatas Este con su `gcKm` sin tocar la red.

3. **Cliente HTTP con caché y cortesía** — `router_get(url)` envuelve `urllib.request` con `User-Agent`, caché en `SENSIBLE/.cache/fogg-rail-routes/{profile}/{sha1}.json`, `sleep(MIN_INTERVAL_S = 1.2)` entre llamadas, reintentos de 5 s, 15 s y 45 s ante `429`, timeout de 60 s. Registra `PointNotFound` y `NoRoute` como descartes con su `code`. Prueba: dos llamadas idénticas seguidas, la segunda sale de caché sin red.

4. **Decodificador y simplificador** — `decode_polyline5(s)` (polilínea Google precision 5, stdlib puro) y `simplify(coords, tol_m)` (Douglas-Peucker con distancia perpendicular Haversine en metros, dedup previo y posterior). Prueba: `Londres→París` decodifica y pasa de ~3.800 a unos cientos de vértices conservando la longitud dentro de `LENGTH_TOLERANCE`.

5. **Pool de candidatas y fallback** — `build_pool(origin, direction)`: `delta = eastward_delta(lng_ori, lng_dst)`; se queda con `0 < delta <= 180` (Este) o `-180 <= delta < 0` (Oeste), excluye el propio nombre, ordena por `haversine` y corta a los `pool` (5) primeros. El pool oeste solo se calcula si el Este no alcanza `minRoutesPerOrigin` (2). Prueba: desde una isla al Este no queda ninguna candidata y se avisa sin error.

6. **Geometrías y anclaje** — `GET /route?point={ori}&point={dest}&profile={p}&points_encoded=true`; decodifica, deduce `railOrigin`/`railDest` (primer/último vértice) con su `snapKm`, simplifica, `normalize_lng` en cada vértice, `anchor_to_cities()` antepone y pospone la ciudad (modelo de SPEC 004); `distanceKm = paths[0].distance/1000` y `durationHours = paths[0].time/3.600.000`; `heading` del delta de ciudades. Prueba: `Lisboa → Madrid` produce una LineString con `coordinates[0]` igual a la ciudad y `distanceKm > 0`.

7. **Validación, escritura y reanudación** — `validate_dataset()`: duplicados, `origin == destination`, rango de coordenadas, extremos anclados, coherencia de `heading`, `|haversine_sum(geom) − snapKm(ori) − snapKm(dest) − distanceKm| / distanceKm ≤ LENGTH_TOLERANCE`, como mucho `limit` rutas por origen, `distanceKm` ascendente por origen. `write_output()` revalida el JSON tras escribir. Cada 10 orígenes se vuelca a disco; `--resume` fusiona saltando orígenes ya presentes y sembrando contadores del meta previo. Prueba: dos corridas `--resume` seguidas no duplican ni reprocesan.

8. **Integra el raíl en la cobertura** — `tools/route_coverage.py` carga `rail_routes.json` si existe y lo suma a la unión; `docs/ciudades-sin-rutas.md` se regenera. Prueba: `python3 tools/route_coverage.py` sigue verde con el raíl sumado; borrar una salida de una copia de prueba lo pone rojo.

9. **Documenta y verifica** — completa `SKILL.md` con la tabla de perfiles y el coste del lote; ejecuta un lote acotado `--only 20`, `python3 -m json.tool assets/data/rail_routes.json`, `flutter analyze` y `flutter test`. Prueba: el lote escribe rutas, valida y deja el fichero legible; el diff no contiene secretos ni `SENSIBLE/`.

---

## 5. Criterios de aceptación

- [x] `.opencode/skills/fogg-rail-routes/SKILL.md` existe con `name: fogg-rail-routes` y documenta la política de 1 petición/s, el `User-Agent`, el coste del lote, la simplificación Douglas-Peucker y que la instancia es experimental y sin SLA.
- [x] `rail_route.py` usa solo stdlib: `python3 rail_route.py --help` funciona en un intérprete sin `pip install`.
- [x] `rail_route.py --profile foo` sale con código 1 y lista la lista blanca `non_tgv|tgv_all|all_tracks|all_tracks_1435|tramtrain`; no escribe ningún fichero.
- [x] Entre dos peticiones consecutivas al servidor hay al menos 1,2 s (medible en el log de tiempos).
- [x] Ante un `429` el script reintenta con esperas de 5 s, 15 s y 45 s; agotados los tres, registra el fallo y no aborta el lote.
- [x] Cada origen consulta como mucho `pool` (5) `/route` al Este y otros `pool` (5) al Oeste; no se usa `/matrix` en ningún punto del código.
- [x] El pool de candidatas de cada origen contiene como mucho 5 ciudades, ordenadas por `haversine`, y solo con `0 < deltaLng <= 180` (Este) o `-180 <= deltaLng < 0` (Oeste); el pool oeste solo se consulta si faltan rutas para `minRoutesPerOrigin`.
- [x] Ningún origen propone un destino a su Oeste, ni siquiera cruzando el antimeridiano; el `heading` coincide con el signo de `deltaLng`.
- [x] La geometría se decodifica desde `points_encoded=true` y se simplifica antes de escribir: ningún `LineString` conserva los miles de vértices crudos del servidor (Estambul→Bombay pasa de ~30.900 a un orden de cientos).
- [x] `assets/data/rail_routes.json` es JSON válido y tiene `meta.units == "km"`, `meta.profile == "non_tgv"`, `meta.candidatePool == 5`, `meta.limitPerOrigin == 5` y `meta.simplifyMeters > 0`.
- [x] Cada ruta tiene `origin/destination` canónicos, `distanceKm > 0`, `durationHours > 0`, `heading`, `railOrigin`/`railDest` con `snapKm` y `geometry.type == "LineString"` con al menos 2 vértices `[lng, lat]`.
- [x] Para toda ruta, `geometry.coordinates[0]` coincide con `originLat/originLng` y `[-1]` con `destinationLat/destinationLng`, a 5 decimales.
- [x] Ningún origen tiene más de 5 rutas normales, y sus `distanceKm` están en orden ascendente; las rutas `explicit` no cuentan para el límite.
- [x] `|haversine_sum(geometry) − snapKm(origin) − snapKm(dest) − distanceKm| / distanceKm ≤ LENGTH_TOLERANCE` en todas las rutas, con `distanceKm` tomado de GraphHopper y nunca recalculado. (Valor inicial 0,10; se ajustará y documentará con la primera corrida completa si la simplificación o el anclaje lo exigen, siguiendo el precedente de SPEC 006 §5.)
- [x] Un origen sin ninguna vía (isla, o red no conectada — Bombay→Tokio por el vacío de Myanmar) aparece con 0 rutas y el motivo en el log; el script no falla.
- [x] `meta.dataTimestamp` copia el `info.road_data_timestamp` de la respuesta para delatar un artefacto viejo.
- [x] Las coordenadas están siempre en `[-180, 180]`; si alguna ruta cruza el antimeridiano, `meta.crossesAntimeridian` lo cuenta y el salto queda para que lo segmenten el visor (`splitAntimeridian`) y Dart (`FoggRoute.polylineSegments`).
- [x] `meta.attribution` cita a los colaboradores de OpenStreetMap (ODbL) y a OpenRailRouting/GraphHopper.
- [x] `python3 rail_route.py --city "Lisboa" --dry-run` no escribe nada y lista candidatas, descartes y rutas previstas.
- [x] Reanudar con `--resume` no duplica rutas ni vuelve a preguntar al servidor lo que ya está en caché.
- [x] `tools/route_coverage.py` carga `rail_routes.json` si existe y lo suma a la unión mar ∪ tierra ∪ raíl; con los datos actuales sigue con 0 pendientes.
- [x] `flutter analyze` y `flutter test` terminan correctamente; no se toca `pubspec.yaml`, `lib/` ni `tools/locations-map/`.
- [x] El diff no contiene secretos, ni `SENSIBLE/`, ni datos generados fuera de alcance.

---

## 6. Decisiones

- **Sí:** OpenRailRouting (`https://routing.openrailrouting.org`, GraphHopper de Geofabrik) como fuente real. Por qué: es la única instancia pública de enrutado **ferroviario** sin credenciales, es global (verificado en cuatro continentes) y expone la fecha de datos. **No:** OSRM demo — no sirve tren (SPEC 006 §6). **No:** Overpass + grafo propio + Dijkstra — control y offline a cambio de mucha ingeniería y de un grafo OSM pesado; se descarta en esta iteración. **No:** ficción tipo `fogg-sea-routes-fiction` — el encargo es "encontrar rutas ferroviarias", no inventarlas.
- **Sí:** perfil `non_tgv` por defecto, con lista blanca de los 5 perfiles del servidor. Por qué: `non_tgv` engancha de forma fiable con coordenadas de ciudad (Lisboa centro→Madrid, Chicago→LA, Sídney→Melbourne, Estambul→Ankara); `all_tracks` falla en las mismas ciudades porque engancha a cocheras y metro, y `tgv_all` solo cubre alta velocidad. **No:** fijar el perfil en duro — el coste de aceptar los 5 reales es nulo y documenta la fragilidad de los demás.
- **Sí:** artefacto `assets/data/rail_routes.json`, un fichero por modo. Por qué: el Señor lo decidió y sigue el patrón `sea_routes.json`/`car_routes.json`; evita colisiones cuando existan más perfiles. **No:** mezclar perfiles en `routes[]` con un campo `profile` por ruta.
- **Sí:** Regla del Este medida sobre la **ciudad**, con fallback al Oeste hasta `minRoutesPerOrigin = 2`. Por qué: idéntico a SPEC 006 §12; el enganche a la vía es de metros y no altera el orden entre ciudades casi alineadas. **No:** medir sobre el enganche.
- **Sí:** `points_encoded=true` + decodificador propio + **Douglas-Peucker** antes de escribir. Por qué: el servidor no ofrece geometría simplificada y las polilíneas crudas son enormes (30.896 vértices en Estambul→Bombay); el fichero completo sin simplificar se iría a decenas de MB. **No:** `points_encoded=false` (GeoJSON directo pero ~2,8× más bytes por la red). **No:** guardar la geometría completa (viola el encargo de "ya simplificadas").
- **Sí:** `distanceKm` y `durationHours` de GraphHopper (`distance`/1000, `time`/3.600.000), nunca recalculados. Por qué: separar dato con significado de la suma Haversine de una polilínea ya simplificada. La suma Haversine solo se usa como aserción, descontando los tramos de anclaje (`snapKm`).
- **Sí:** sin `/matrix`, un `/route` por candidata del pool. Por qué: el servidor no tiene endpoint de tabla; se acepta el techo de `pool` peticiones por origen y dirección. **No:** podar con una tabla que no existe.
- **Sí:** `--pair "ORIGEN|DESTINO"` con `explicit: true` y merge. Por qué: el corredor del juego (Londres→París→Estambul→Bombay) no lo garantiza el pool de vecinas; el mecanismo ya existe en `fogg-land-routes`. **No:** depender solo del pool acotado.
- **Sí:** la ciudad es el ancla; **sin** resolución de estaciones ni entidad `Station`. Por qué: acuerdo del Señor — "no hay gap entre el puerto y la estación, ambos usan la ciudad como origen/destino". **No:** resolver el nombre de la estación — GraphHopper no lo devuelve en `/route` y añadiría una fuente extra (Overpass/ORM), con su fragilidad. Se conserva `railOrigin`/`railDest` (lat/lng/snapKm) solo como diagnóstico del enganche.
- **Sí:** el raíl entra en la **unión** de `tools/route_coverage.py` (Q-A = a). Por qué: un solo verificador para todos los modos; hoy está verde y el raíl solo puede aumentar la cobertura. **No:** `--close-gaps` ferroviario — la cobertura ya está cerrada y sería alcance de otra spec.
- **Sí:** caché cruda en `SENSIBLE/.cache/fogg-rail-routes/`, ya cubierta por `.gitignore`. **No:** cachear solo en `/tmp`.
- **Sí:** errores de enrutado aislados por ruta (`try/except` por candidata); el lote solo falla por validación o por argumentos inválidos. Por qué: con 257 orígenes es seguro que habrá islas y redes inconexas.

---

## 7. Riesgos

| Riesgo | Mitigación |
| --- | --- |
| La instancia es "experimental use only, not for production", sin SLA y sin cabecera de rate limit visible | Pausa de 1,2 s, `User-Agent` identificable, backoff ante `429`, `--only N` para cortar el lote. Si la spec se repite mucho, el siguiente paso es un OpenRailRouting propio (fuera de alcance). |
| La calidad depende del enganche: la misma ciudad puede caer en un ramal aislado según el perfil | Perfil `non_tgv` (pasajeros, sin cocheras) elegido por medición; `snapKm` en el JSON y en el log avisa de enganches lejanos; `PointNotFound`/`NoRoute` se registran y no abortan. |
| El servidor no ofrece `/matrix`: el coste sube a `pool` peticiones por origen y dirección | Techo acotado y documentado (~2.570 peticiones para 257 orígenes, ~50 min a 1,2 s); la caché hace que la segunda corrida no toque la red. |
| La simplificación podría recortar longitud y romper la tolerancia | Douglas-Peucker con tolerancia en metros (no en grados) y `LENGTH_TOLERANCE` verificada sobre la primera corrida; si una ruta falla, se registra y se ajusta el valor (precedente SPEC 006 §5). |
| Los datos de tren son de terceros y se versionan en el repo | `meta.attribution` (OSM ODbL + OpenRailRouting/GraphHopper) y `meta.dataTimestamp` delatan regeneraciones contra datos distintos. Solo se versiona geometría derivada, nunca un extracto OSM. |
| Una ruta puede cruzar el antimeridiano y producir el salto `179 → -179` | Se detecta con el mismo criterio que SPEC 004/006, se cuenta en `meta.crossesAntimeridian` y lo segmenta el consumidor. |
| Los perfiles distintos de `non_tgv` pueden dar resultados pobres o vacíos | Están en la lista blanca pero documentados como no recomendados; el default es `non_tgv`. |
| Un origen sin vía cercana engancha a kilómetros de distancia y añade un tramo de anclaje largo | `snapKm` queda en el JSON y el log avisa por encima de 1 km; el tramo se descuenta de la aserción de longitud. Es un aviso, no un fallo. |

---

## 8. Lo que **no** está en esta especificación

- El botón/capa/color del visor `tools/locations-map` para rutas ferroviarias.
- Consumo desde Flutter: `WorldMapWidget`, `PolylineLayer`, `TransportMode.train`, `TransportSelector`, `pubspec.yaml`.
- `--close-gaps` ferroviario y estaciones como entidad separada.
- Otros perfiles simultáneos, OpenRailRouting propio o nuevas fuentes de trazado.
- Precio del viaje, `BudgetService`, `Ledger`, `TimeEngine`, `EventEngine`.
- Editar `assets/data/locations.json`, `sea_routes.json`, `car_routes.json` o `sea_routes_fiction.json`.

Cada uno, si aterriza, irá en su propia especificación.

---

## 9. Referencias

- `assets/data/locations.json` — 257 ciudades, fuente del catálogo (meta version 1.0.1).
- `assets/data/car_routes.json` — esquema 1.1.0 clonado (`meta`, `roadOrigin`/`roadDest`, `heading`, `gapClosed`, `explicit`).
- `.opencode/skills/fogg-land-routes/land_route.py` — `build_pool(direction)`, `anchor_to_cities`, `validate_dataset`, `PROJECT_ROOT` con `parents[3]`: modelo a replicar.
- `tools/route_coverage.py` — verificador de cobertura y unión mar ∪ tierra que pasa a incluir raíl.
- `docs/specs/006-fog-car-routes.md` — patrón de skill, pool, Regla del Este y fallback al Oeste.
- `docs/specs/004-fogg-sea-routes.md:227` — addendum de geometría de ciudad a ciudad.
- `lib/domain/entities/fogg_route.dart:55` — `polylineSegments`, consumidor del salto del antimeridiano.
- `TODO.md:28` — trazado GeoJSON real (OpenRailwayMap + rutas marítimas).
- `https://github.com/geofabrik/OpenRailRouting` — motor de enrutado ferroviario (GraphHopper fork) sobre OSM.
- `https://github.com/geofabrik/OpenRailRouting-doc` — documentación del API REST (base GraphHopper Directions).
- `https://routing.openrailrouting.org` — instancia pública de demostración ("experimental use only, not for production").

---

## 10. Mediciones de campo (2026-10-10, ~30 peticiones de sondeo)

| Prueba | Resultado |
| --- | --- |
| Endpoint | `GET /route?point={lat},{lng}&point={lat},{lng}&profile={p}&points_encoded=` responde JSON GraphHopper; `/matrix` → HTTP 404 |
| Perfiles del servidor | `tgv_all, non_tgv, tramtrain, all_tracks, all_tracks_1435` (perfil inexistente devuelve la lista) |
| `all_tracks` Paris→Brussels | 336,4 km, 2,16 h |
| `tgv_all` Paris→Brussels | 323,0 km, 1,58 h |
| `non_tgv` Paris→Brussels | 318,2 km, 3,06 h |
| `non_tgv` Lisboa centro→Madrid | 686,1 km, 6,25 h (engancha con coordenadas de ciudad) |
| `all_tracks` Lisboa centro→Madrid | `Connection between locations not found` (engancha a componente aislada) |
| `non_tgv` Londres→París | 477,6 km, 4,3 h |
| `non_tgv` París→Estambul | 2.929,3 km, 31,4 h, 17.469 vértices crudos |
| `non_tgv` Estambul→Bombay | 10.114,5 km, 101,5 h, **30.896 vértices crudos** |
| `non_tgv` Chicago→LA | 3.522,9 km, 33,9 h |
| `non_tgv` Sídney→Melbourne | 953,4 km, 9,2 h |
| `non_tgv` Delhi→Bombay | 1.390,8 km, 11,9 h |
| `non_tgv` Johannesburgo→Ciudad del Cabo | 1.511,1 km, 15,2 h |
| `non_tgv` El Cairo→Alejandría | 239,4 km, 3,7 h |
| `non_tgv` Bombay→Tokio | `Connection between locations not found` (no hay vía por Myanmar; es contenido, no un fallo) |
| `non_tgv` Honolulu / Nuakchot | `Cannot find point` (islas sin red; se descartan) |
| Tamaño de la geometría | Paris→Brussels `points_encoded=true` 18,6 KB frente a `false` 52,6 KB (~2,8×) |
| Metadatos útiles | `info.road_data_timestamp` (versión de datos) y `paths[0].time` en ms; `hints` de nodos visitados |
| Cortesía | 3 peticiones rápidas seguidas → 200; sin cabecera de rate limit visible; la web declara uso experimental |
| Coste estimado del lote | 257 orígenes × (≤5 + ≤5) = ≤2.570 peticiones, ~50 min a 1,2 s (menos en la práctica, porque el pool oeste solo se consulta si falta el mínimo) |

---

## 11. Preguntas abiertas (resueltas por esta especificación)

- ¿Fuente de rutas ferroviarias? → OpenRailRouting (`routing.openrailrouting.org`), real y global.
- ¿Perfil? → `non_tgv` por defecto; los otros 5 en lista blanca, no recomendados.
- ¿Selección de candidatas? → 5 vecinas más cercanas al Este por Haversine + fallback al Oeste hasta 2, con `heading` en el signo del delta.
- ¿Geometría? → `points_encoded=true`, decodificada y simplificada con Douglas-Peucker antes de escribir.
- ¿Anclaje? → a la ciudad, con `railOrigin`/`railDest` (lat/lng/snapKm) como diagnóstico; sin entidad estación.
- ¿Artefacto? → `assets/data/rail_routes.json` v1.0.0, clon del esquema `car_routes.json` v1.1.0.
- ¿Cobertura? → el raíl se suma a la unión de `tools/route_coverage.py`; sin `--close-gaps` ferroviario.
- ¿Visor y Flutter? → fuera de alcance; el botón del visor es otra spec.
- Próximo número de spec: `010`. Slug: `fogg-rail-routes`.

> Siguiente paso tras aprobar esta spec: ejecutar `/spec-impl 010-fogg-rail-routes` (pasos §4) con validación `json.tool` + `flutter analyze` verde.
