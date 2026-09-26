# SPEC 006 — Skill local de rutas terrestres por carretera con OSRM (5 ciudades más cercanas al Este)

> **Estado:** Implementado
> **Ejecutado:** 2026-09-26 — lote completo de 304 orígenes: 999 rutas de 235 orígenes (69 sin ruta), 521 descartes, 0 cruces de antimeridiano, `assets/data/car_routes.json` v1.0.0 (3,3 MB). Desviaciones respecto al diseño: `meta.osrmDataVersion` queda `"unknown"` (la API no expone `data_version`) y `LENGTH_TOLERANCE` sube a 0,25 (el `simplified` recorta hasta 22,7 % en alta montaña).
> **Depende de:** `assets/data/locations.json` (304 ciudades, orden Este desenrollado), SPEC 004 (patrón de skill, `anchor_to_cities`, validación), SPEC 005 (contrato que el visor ya sabe leer), `TODO.md:28` (trazado GeoJSON real)
> **Fecha:** 2026-09-26
> **Objetivo:** Proveer una skill local Python que, usando el servidor demo de OSRM a un máximo de 1 petición por segundo, calcule para cada ciudad de `locations.json` las rutas por carretera hacia sus 5 ciudades más cercanas al Este y las guarde en `assets/data/car_routes.json` con el primer y el último vértice anclados a la ciudad.

---

## 1. Por qué existe esta especificación

El juego promete 80 días de viaje hacia el Este **sin avión**, con presupuesto y tiempo reales. Hoy solo existen rutas marítimas (`assets/data/sea_routes.json`, SPEC 004, 165 rutas). Falta el complemento terrestre: la opción por carretera que consume presupuesto, tiempo y una línea visible sobre el mapa.

La skill marítima resuelve el problema con `searoute`, que empaqueta su malla marítima en el paquete pip y por eso es offline. Para tierra no hay equivalente: la red de carreteras son cientos de millones de vértices OSM, inviables de empaquetar. La fuente viable sin credenciales es el servidor demo de OSRM, y su política de uso impone un diseño distinto al de `sea_route.py`: lo que se puede cachear son **respuestas**, no datos de entrada.

La investigación de campo (ver §10) fijó tres hechos que condicionan todo el diseño: el servidor **ignora el perfil** solicitado, la geometría `full` es 89× más grande que `simplified`, y las respuestas de tabla marcan con `null` los pares sin conexión terrestre.

---

## 2. Alcance

**En:**

- **Corrige el `.gitignore` antes de escribir nada — `.gitignore` — deja de versionar la caché de terceros** — añade `SENSIBLE/` y `.worktrees/`; hoy `SENSIBLE/.cache/city_enrich.json` está versionado
  - **Por qué primero:** con la regla en el primer commit la skill no repite el fallo de `fogg-city-enricher`, que versionó su caché

- **Traza rutas por carretera hacia el Este — `.opencode/skills/fogg-land-routes/land_route.py` — elige como mucho 5 destinos por origen** — para cada ciudad toma sus 5 vecinas más próximas por círculo grande que cumplan la Regla del Este, consulta a OSRM y se queda con las que tienen camino
  - **Pool acotado:** los candidatos salen de las 5 ciudades más cercanas, no de un recorrido hasta reunir 5 válidas
  - **Techo de peticiones:** 1 `/table` + como mucho 5 `/route` por origen, constante y demostrable

- **Consulta el servidor sin pasarse de 1 petición por segundo — `land_route.py:osrm_get` — espera 1,2 s entre llamadas y reintenta los 429** — `User-Agent: eu.elarreglador.pf/1.0`; backoff de 5 s, 15 s y 45 s con tres reintentos
  - **Lote completo:** 304 orígenes, como mucho 1.824 peticiones, unos 37 minutos
  - **Corte por horas:** `--only N` escribe lo acumulado y sale con código 0

- **Descarta lo que no tiene camino — `land_route.py:build_route` — registra por qué se cae cada ruta** — `NoRoute` (otro continente), `NoSegment` (isla sin carreteras), `TooBig`, `429` agotado, timeout
  - **Efecto colateral útil:** el recuento de ciudades sin red, análogo a `citiesWithoutPort` de la SPEC 004

- **Ancla la geometría a la ciudad — `land_route.py:anchor_to_cities` — el primer y el último vértice son los de `locations.json`** — OSRM devuelve coordenadas del punto enganchado a la calzada, no del centro urbano
  - **Paridad con `sea_routes.json` v3:** el visor y Dart ya esperan geometrías de ciudad a ciudad
  - **Nunca sustituye:** antepone y pospone el vértice, el camino intermedio queda intacto

- **Escribe un artefacto por vehículo — `assets/data/car_routes.json` — clona el esquema `sea_routes.json` v3** — `{meta, routes[]}` con `origin/destination/…/geometry`, y `roadOrigin`/`roadDest` en lugar de `portOrigin`/`portDest`
  - **Verificable:** el visor de `tools/locations-map` lo carga sin tocar `app.js`

- **Añade el tiempo de conducción — `routes[].durationHours` — dato que OSRM da gratis** — horas con un decimal; el juego las necesita para `TimeEngine`

- **Rechaza vehículos que OSRM no distingue — `land_route.py:main` — solo `car` en esta spec** — `--profile foot` sale con código 1 y el motivo, en lugar de escribir un fichero mentiroso
  - **Base:** `driving`, `foot` y `bike` devuelven hoy respuestas byte-idénticas

- **Documenta la skill — `.opencode/skills/fogg-land-routes/SKILL.md` — explica política, perfiles y riesgos medidos** — incluye la tabla de rate limit, el coste del lote y el estado real de los perfiles

**Compartido:** estilo de SPEC 004 (`--city`, `--dry-run`, `--out`, `--limit`, `validate_dataset`, `[INFO]/[WARN]/[SKIP]/[ERROR]` en castellano); `locations.json` solo lectura; helpers geodésicos con el modelo de `sea_route.py`; `Package by Layer`; `eu.elarreglador.pf`; `flutter analyze` y `flutter test` verdes (la skill es Python, fuera de `lib/`).

**Fuera del alcance (para futuras especificaciones):**

- Generar `foot.json`, `bike.json`, `horse.json` o `motorcycle.json`: el servidor demo solo sirve datos de coche, y su wiki avisa de que sus perfiles difieren de los de `osrm-backend`.
- Servir OSRM propio (`.osm.pbf` + `osrm-routed`) para eximirse del rate limit.
- `exclude=motorway`, `radiuses`, `bearings` u otras opciones de ajuste fino de OSRM.
- Modificar el visor para distinguir líneas terrestres de marítimas, o meter `car_routes.json` en `pubspec.yaml`.
- Consumo desde `WorldMapWidget`/`PolylineLayer`/`TransportMode.car`.
- Precio del viaje, combustible, `BudgetService`, `Ledger`, `TimeEngine`, `EventEngine`.
- Degradación offline o caché de `car_routes.json` para el jugador.
- Ramas de git: la spec se implementa en la rama actual.

---

## 3. Modelo de datos

### 3.1 `assets/data/car_routes.json` (nuevo, artefacto derivado)

```jsonc
{
  "meta": {
    "project": "eu.elarreglador.pf",
    "name": "Fogg Land Routes — Herencia de Phoebe",
    "version": "1.0.0", "generated": "2026-09-26",
    "tool": "fogg-land-routes", "profile": "car",
    "osrmServer": "https://router.project-osrm.org",
    "osrmWeightName": "routability", "osrmDataVersion": "2026-09-20T00:00:00Z",
    "units": "km", "limitPerOrigin": 5, "maxEastDeg": 180,
    "candidatePool": 5,
    "origins": 304, "routes": 0,
    "originsWithoutRoute": 0, "unroutableCities": 0,
    "crossesAntimeridian": 0,
    "eastRule": "0 < deltaLng(cityDest - cityOrigin) <= 180 (desenrollado)",
    "poolRule": "los 5 candidatos más cercanos por círculo grande dentro de maxEastDeg; se descartan los que OSRM no puede enrutar",
    "geometry": "LineString [lng,lat] de ciudad a ciudad: el primer y el último vértice son las coordenadas de la ciudad de locations.json y entre medias va la carretera de OSRM con overview=simplified",
    "distanceNote": "distanceKm es routes[0].distance de OSRM; NO es la suma Haversine de la geometría, que con overview=simplified queda hasta un 9% por debajo al recortar curvas",
    "attribution": "© OpenStreetMap contributors (ODbL); routing courtesy of the OSRM demo server sponsored by FOSSGIS",
    "source": "OSRM demo server (car) + GeoNames cities15000"
  },
  "routes": [
    {
      "origin": "Lisboa", "originLat": 38.72509, "originLng": -9.1498,
      "destination": "París", "destinationLat": 48.85341, "destinationLng": 2.3488,
      "distanceKm": 1735.5, "durationHours": 18.3,
      "roadOrigin": { "name": "Praça Marquês de Pombal (Rotunda)", "lat": 38.72494, "lng": -9.14965, "snapKm": 0.0 },
      "roadDest":   { "name": "Rue d'Arcole", "lat": 48.85363, "lng": 2.34921, "snapKm": 0.0 },
      "geometry": { "type": "LineString", "coordinates": [[-9.1498, 38.72509], "…", [2.3488, 48.85341]] }
    }
  ]
}
```

Convenciones:

- `coordinates` siempre en `[-180, 180]`, orden GeoJSON `[lng, lat]`, redondeadas a `COORD_PRECISION` (5 decimales).
- `originLat/originLng` conservan la precisión íntegra de `locations.json`; la igualdad con los extremos de la geometría es a 5 decimales, igual que en la SPEC 004.
- `roadOrigin/roadDest` documentan el enganche a calzada: `name` es la calle de OSRM, `snapKm` la distancia centro→calzada con 1 decimal.
- `durationHours = duration_s / 3600`, un decimal. Sin modelo de tráfico: es la estimación estática del perfil `car`.
- Sin `port*` a diferencia de la SPEC 004, y sin `weight`.
- Reescritura completa, no hay merge. `meta.generated` es la fecha de esa generación.

### 3.2 Estructuras efímeras (no persistidas)

```python
candidate = {"city": {...}, "gcKm": 1452.8, "roadKm": 1735500.0}  # gc ordena, roadKm decide
road      = {"name": "Rue d'Arcole", "lat": 48.85363, "lng": 2.34921, "snapKm": 0.0}
args      = {"profile": "car", "limit": 5, "pool": 5, "only": None, "resume": False, "dry_run": False}
```

- La caché guarda la respuesta cruda de OSRM indexada por `sha1(url)`, nunca estas estructuras.
- `snapKm` se escribe en el JSON porque explica el tramo ancla; también va al log cuando supera 1 km.

---

## 4. Plan de implementación

1. **Corrige `.gitignore` y crea la estructura** — añade `SENSIBLE/` y `.worktrees/`; `mkdir -p .opencode/skills/fogg-land-routes SENSIBLE/.cache/fogg-land-routes`; `SKILL.md` con `name`/`description`/`cuándo usar`/`fuentes`/`flujo`/`rate limit`/`ejemplos`/`riesgos medidos`; `requirements.txt` vacío (stdlib puro). Prueba: `git check-ignore -v SENSIBLE/.cache/x.json` casa con la regla nueva.

2. **Esqueleto y carga de catálogo** — `land_route.py` con `argparse --profile car --city --limit 5 --pool 5 --only N --resume --dry-run --out`; `load_locations()` con el modelo de `sea_route.py` (validación de campos y `lng_u` desenrollado); `eastward_delta`, `haversine`, `haversine_sum`, `normalize_lng`. Prueba: `python3 land_route.py --help` funciona y `--profile foot` sale con código 1 y el motivo.

3. **Cliente OSRM con caché y cortesía** — `osrm_get(url)` envuelve `urllib.request` con `User-Agent`, caché en `SENSIBLE/.cache/fogg-land-routes/{profile}/{sha1}.json`, `sleep(MIN_INTERVAL_S = 1.2)` entre llamadas, reintentos de 5 s, 15 s y 45 s ante `429`, timeout de 60 s. Devuelve `None` en fallo irrecuperable y lo registra con su `code` (`NoRoute`, `NoSegment`, `TooBig`, `InvalidUrl`). Prueba: dos llamadas idénticas seguidas, la segunda sale de caché sin red.

4. **Pool de candidatos y matriz** — `build_pool()`: para el origen, `delta = eastward_delta(lng_ori, lng_dst)`; se queda con `0 < delta <= 180`, excluye el propio nombre, ordena por `haversine` y corta a los `pool` (5) primeros. `table_distances()`: una llamada `/table/v1/car/{ori};{cand…}?sources=0&annotations=distance` (como mucho 6 coordenadas). Prueba: `--city "Lisboa" --dry-run` muestra las 5 candidatas con su `gcKm`.

5. **Corta las no conectadas** — descarta del pool toda candidata cuyo `distances[i]` sea `null`, cuenta en `unroutableCities` y en `originsWithoutRoute`, y registra `[SKIP] <origen> → <ciudad>: sin camino terrestre`. Quedan como máximo 5 candidatas y como mínimo 0. Prueba: desde `Sidney` (151,2) no queda ninguna candidata al Este y se avisa sin error.

6. **Geometrías y anclaje** — `/route/v1/car/{ori};{dest}?geometries=geojson&overview=simplified&steps=false`; `normalize_lng` en cada vértice; `anchor_to_cities()` idéntico a la SPEC 004; `distanceKm` de `routes[0].distance` y `durationHours` de `routes[0].duration`. Prueba: `Lisboa → París` produce 23 vértices y `coordinates[0]` igual a la ciudad de `locations.json` redondeada.

7. **Validación, escritura y reanudación** — `validate_dataset()`: duplicados, `origin == destination`, rango de coordenadas, extremos anclados, Regla del Este, `|haversine_sum − distanceKm| / distanceKm ≤ 0.20` (la simplificación recorta curvas), como mucho `limit` rutas por origen, `distanceKm` ascendente por origen. `write_output()` revalida el JSON tras escribir. Cada 10 orígenes se vuelca a disco; `--resume` salta los orígenes ya presentes en el fichero. Prueba: dos corridas con `--resume` seguidas no duplican ni reprocesan.

8. **Documenta y verifica** — completa `SKILL.md` con la tabla de rate limit y los perfiles medidos; ejecuta un lote acotado `--only 20`, `python3 -m json.tool assets/data/car_routes.json`, `flutter analyze` y `flutter test`. Prueba: el lote escribe rutas, valida y deja el fichero legible; el diff no contiene secretos ni `SENSIBLE/`.

---

## 5. Criterios de aceptación

- [x] `.gitignore` ignora `SENSIBLE/` y `.worktrees/`, y `git status` deja de ofrecer `SENSIBLE/.cache/city_enrich.json`.
- [x] `.opencode/skills/fogg-land-routes/SKILL.md` existe con `name: fogg-land-routes` y documenta la política de 1 petición/s, el `User-Agent`, el coste del lote, `overview=simplified` y que el servidor solo sirve datos de coche.
- [x] `land_route.py` usa solo stdlib: `python3 land_route.py --help` funciona en un intérprete sin `pip install`.
- [x] `land_route.py --profile foot` sale con código 1 y explica que el servidor devuelve datos de coche; no escribe ningún fichero.
- [x] Entre dos peticiones consecutivas al servidor hay al menos 1,2 s (medible en el log de tiempos).
- [x] Ante un `429` el script reintenta con esperas de 5 s, 15 s y 45 s; agotados los tres, registra el fallo y no aborta el lote.
- [x] Cada origen consulta como mucho 1 `/table` y 5 `/route`; el total del lote completo no supera 1.824 peticiones.
- [x] El pool de candidatos de cada origen contiene como mucho 5 ciudades, ordenadas por `haversine`, y solo con `0 < deltaLng <= 180`.
- [x] Ningún origen propone un destino a su Oeste, ni siquiera cruzando el antimeridiano.
- [x] `assets/data/car_routes.json` es JSON válido y tiene `meta.units == "km"`, `meta.profile == "car"`, `meta.candidatePool == 5` y `meta.limitPerOrigin == 5`.
- [x] Cada ruta tiene `origin/destination` canónicos, `distanceKm > 0`, `durationHours > 0`, `roadOrigin`/`roadDest` con `snapKm`, y `geometry.type == "LineString"` con al menos 2 vértices `[lng, lat]`.
- [x] Para toda ruta, `geometry.coordinates[0]` coincide con `originLat/originLng` y `[-1]` con `destinationLat/destinationLng`, a 5 decimales.
- [x] Ningún origen tiene más de 5 rutas, y sus `distanceKm` están en orden ascendente.
- [x] Un origen sin ninguna ruta por tierra (isla, o al otro lado de un océano) aparece con 0 rutas y el motivo en el log; el script no falla.
- [x] `|suma Haversine de la geometría − distanceKm| / distanceKm ≤ 0.25` en todas las rutas, con `distanceKm` tomado de OSRM y nunca recalculado. (Ajustado de ±20 % a ±25 % el 2026-09-26: el `simplified` recorta hasta 22,7 % en alta montaña — Nizhneyansk→Magadán −22,7 %, Lhasa→Chengdu −20,4 %, Tiksi→Magadán −20,2 % — y las tres se verificaron contra `overview=full` a ±0,3 %, o sea la distancia OSRM es real.)
- [x] Las coordenadas están siempre en `[-180, 180]`; si alguna ruta cruza el antimeridiano, `meta.crossesAntimeridian` lo cuenta y el salto queda para que lo segmenten el visor (`splitAntimeridian`) y Dart (`FoggRoute.polylineSegments`).
- [x] `meta.attribution` cita a los colaboradores de OpenStreetMap (ODbL) y al servidor OSRM patrocinado por FOSSGIS.
- [x] `python3 land_route.py --city "Lisboa" --dry-run` no escribe nada y lista candidatos, descartes y rutas previstas.
- [x] Reanudar con `--resume` no duplica rutas ni vuelve a preguntar al servidor lo que ya está en caché. (Matiz medido 2026-09-26: `--resume` preserva las rutas, pero `meta.unroutableCities` y `meta.originsWithoutRoute` quedan parciales — 345 frente a 521 — porque solo cuentan los orígenes reprocesados. Para métricas ciertas, lote completo sin `--resume`.)
- [x] `tools/locations-map` carga `assets/data/car_routes.json` mediante el selector de rutas sin cambiar `app.js` (comprobado con Chromium headless vía Playwright: 999 rutas cargadas, 999 polilíneas renderizadas, sin errores ni banner).
- [x] `flutter analyze` y `flutter test` terminan correctamente; no se toca `pubspec.yaml` ni `lib/`.
- [x] El diff no contiene secretos, ni `SENSIBLE/`, ni datos generados fuera de alcance.

---

## 6. Decisiones

- **Sí:** el pool de candidatos son las 5 ciudades más cercanas por círculo grande, y de ellas se conservan las que tienen camino. Por qué: fija un techo de peticiones demostrable (6 por origen) y coincide con el encargo del Señor. No: enrutar candidatos en orden de gc hasta reunir 5 válidas, que era mi lectura inicial — pide una cota variable de peticiones y puede gastar muchas en un origen rodeado de destinos sin camino. No: las 5 más cercanas de todo el catálogo sin filtrar por Este — produciría destinos al Oeste y rompería la Regla del Este.
- **Sí:** `assets/data/car_routes.json`, un fichero por vehículo. Por qué: el Señor lo decidió, separa el perfil del nombre del artefacto y evita colisiones cuando existan más perfiles. No: `land_routes.json` con `meta.profiles[]` — mezclaría perfiles en un mismo array y obligaría al consumidor a filtrar. No: un directorio `assets/data/routes/car_routes.json` — más orden, pero `pubspec.yaml` declara los assets de uno en uno y esta spec no lo toca.
- **Sí:** solo perfil `car`, y `--profile` distinto de `car` aborta. Por qué: el servidor demo devuelve respuestas byte-idénticas para `driving`, `foot` y `bike`, con `weight_name=routability`; escribir `foot.json` sería un fichero mentiroso. No: aceptar `--profile` y avisar solo en el log — un aviso en un log es justo lo que nadie lee.
- **Sí:** la Regla del Este se mide sobre la **ciudad**, no sobre el punto enganchado a la calzada. Por qué: a diferencia de la SPEC 004, donde el puerto podía estar a 10 km y cambiar el orden entre ciudades casi alineadas, aquí la corrección del enganche es de decenas de metros. No: medir sobre el enganche, por simetría con la SPEC 004.
- **Sí:** `overview=simplified` fijo, sin flag. Por qué: 55 vértices frente a 4.895 en Lisboa→Madrid (1,3 KB frente a 116 KB), comparable a la media de 58 de las marítimas, y un lote completo en `full` pesaría del orden de 160 MB. No: `overview=full`, por fidelidad de trazado.
- **Sí:** `distanceKm` es el campo `distance` de OSRM, y la suma Haversine de la geometría solo se usa como aserción con ±20 %. Por qué: la polilínea simplificada recorta curvas y queda hasta un 9 % por debajo (12.238 km frente a 13.433 km medidos en Lisboa→Tokio); la distancia que se persiste es la que el vehículo recorre. No: recalcular `distanceKm` como la suma Haversine, que convertiría un dato con significado en otro sin él.
- **Sí:** Regla del Este `0 < deltaLng <= 180` sin tope extra de distancia. Por qué: Lisboa→Tokio son 13.432 km por el puente terrestre del norte y responde `code: Ok`. El juego dura 80 días, así que una travesía eurasiática es contenido, no un fallo. No: un tope de 3.000 km, que recortaría precisamente la ruta que da sentido al juego.
- **Sí:** errores de enrutado por ruta (`try/except` por candidata) y el lote solo falla si `--limit <= 0`, `--profile != car` o la validación del dataset encuentra problemas. Por qué: replica `sea_route.py` y con 304 orígenes es seguro que habrá islas. No: abortar el lote al primer `NoRoute`.
- **Sí:** `data_version` de OSRM se copia a `meta.osrmDataVersion`. Por qué: es un campo opcional documentado y la única forma de saber si una regeneración comparó dos versiones distintas de los datos. **Corrección 2026-09-26:** la API v5.24 del demo no expone `data_version` en las respuestas de `/route` ni `/table` (verificado en las 1.402 respuestas del lote); `meta.osrmDataVersion` queda `"unknown"` y así se documenta, en lugar de inventar un valor.
- **Sí:** `--resume` y volcado periódico cada 10 orígenes, en lugar de un `--force`. Por qué: el lote son unos 37 minutos contra un servidor compartido; poder interrumpirlo y seguir es la diferencia entre una noche perdida y un lote recuperable. No: atomicidad transaccional, que es KISS para un artefacto derivado y reescribible.
- **Sí:** la caché cruda en `SENSIBLE/.cache/`, con las reglas de `.gitignore` corregidas en el primer paso. Por qué: es donde ya guarda `fogg-city-enricher`, pero el repo no lo ignoraba. No: cachear solo en `/tmp`, que obliga a pagar la red en cada ejecución y no sobrevive a un reinicio.
- **No:** `exclude=motorway` ni otros ajustes del perfil. Por qué: KISS, y el juego quiere la opción rápida y barata, no la pintoresca.
- **No:** degradar a un motor propio si el servidor cae. Por qué: es una spec de datos, no de infraestructura; documentamos el rate limit y su coste y decidimos cuando duela.

---

## 7. Riesgos

| Riesgo | Mitigación |
| --- | --- |
| 1.824 peticiones a un servidor compartido cuya política es "uso razonable, no comercial" puede parecer abuso, aunque se respete 1 req/s | Pausa de 1,2 s, `User-Agent` identificable, backoff ante 429 y `--only N` para cortar el lote por horas. Si esta spec se repite mucho, el siguiente paso es un OSRM propio. |
| La Regla del Este genera pares largos: Lisboa→Tokio por Rusia, 13.432 km | Es correcto por diseño (el puente terrestre del norte, y el juego dura 80 días) y así queda documentado en `meta.eastRule`. El pool acotado a 5 limita el ruido. |
| La geometría simplificada subestima la longitud hasta un ~9 % y el consumidor podría mostrar una línea más corta que el dato | `distanceKm` es el de OSRM, `meta.distanceNote` lo declara y la validación tolera ±20 %. Documentado también en `SKILL.md`. |
| El enganche al centro urbano puede quedar lejos de la calzada en ciudades sin calle céntrica catalogada | `roadOrigin.snapKm` queda en el JSON y el log avisa por encima de 1 km. Un `snapKm` grande es un aviso, no un fallo. |
| El pool de 5 puede quedarse corto: un origen con las 5 ciudades más cercanas en otro continente se queda sin rutas aunque más lejos las tuviera | Correcto por construcción: son 5 rutas como máximo, no 5 rutas garantizadas. `originsWithoutRoute` y el log lo hacen visible. |
| Una ciudad del catálogo no engancha (`NoSegment`): islas sin red rodada | Se registra y se cuenta en `unroutableCities`; el origen queda con 0 rutas y el lote continúa. |
| El servidor puede estar caído, lento o con datos atrasados: no hay SLA | Cada fallo se aísla por ruta y el lote solo muere por validación. `meta.osrmDataVersion` y `meta.generated` delatan un artefacto viejo. |
| Una ruta puede cruzar el antimeridiano en longitud y producir el salto `179 → -179` | Se detecta con el mismo criterio que la SPEC 004, se cuenta en `meta.crossesAntimeridian` y lo segmenta el consumidor. |
| Los datos de carretera son de terceros y se versionan en el repo | `meta.attribution` con OpenStreetMap (ODbL) y FOSSGIS, igual que el visor ya hace con GeoNames. Solo se versiona la geometría derivada, nunca un fichero de OSM. |
| El rate limit real puede ser más estricto que 1 req/s en horas punta | El backoff con tres reintentos absorbe los `429`; el script no insiste en un origen fallido, lo registra y sigue. |

---

## 8. Lo que **no** está en esta especificación

- `foot.json`, `bike.json`, `horse.json`, `camel.json` o `motorcycle.json`.
- Un OSRM propio, con `.osm.pbf` y `osrm-routed`, y todo lo que implica.
- Cambios en `tools/locations-map`, en `pubspec.yaml` o en `assets/data/sea_routes.json`.
- Consumo desde Flutter: `WorldMapWidget`, `PolylineLayer`, `TransportMode.car`, `TransportSelector`.
- Precio del viaje, combustible, `BudgetService`, `Ledger`, `TimeEngine`, `EventEngine`.
- Cualquier elemento de la Regla del Este distinto del que ya existe en `FoggRoute.validated`.

Cada uno, si aterriza, irá en su propia especificación.

---

## 9. Referencias

- `docs/specs/004-fogg-sea-routes.md:227` — addendum de geometría de ciudad a ciudad que esta spec replica.
- `.opencode/skills/fogg-sea-routes/sea_route.py:245` — `anchor_to_cities` a espejar.
- `.opencode/skills/fogg-sea-routes/sea_route.py:350` — `validate_dataset` como referencia de invariantes.
- `AGENTS.md` — Regla del Este desenrollada, sin avión, ciclo Fogg.
- `lib/domain/entities/fogg_route.dart:55` — `polylineSegments`, el consumidor del salto del antimeridiano.
- `https://github.com/Project-OSRM/osrm-backend/wiki/Demo-server` — perfiles patrocinados por FOSSGIS, política de 1 petición/s, sin garantías de disponibilidad.
- `https://project-osrm.org/docs/v5.24.0/api/` — servicios `route`, `table`, `nearest`; `distances` en metros con `null` cuando no hay camino; `waypoints[].distance` es la distancia al enganche.
- `https://routing.openstreetmap.de/about.html` — condiciones de uso (en alemán).
- `TODO.md:28` — trazado GeoJSON real (OpenRailwayMap + rutas marítimas).

---

## 10. Mediciones de campo (2026-09-26, 13 peticiones de sondeo espaciadas)

| Prueba | Resultado |
| --- | --- |
| Política oficial | Máximo 1 petición por segundo, uso razonable y no comercial, sin SLA |
| Latencia real | 235–442 ms por petición |
| Lisboa→Madrid (`-9.14,38.72;-3.70,40.42`), `overview=full` | 625,6 km, 4.895 vértices, 116 KB |
| Lisboa→Madrid, `overview=simplified` | 625,6 km, 55 vértices, 1,3 KB |
| Lisboa→París, `simplified` | 1.735,5 km, 18,3 h, 23 vértices |
| Lisboa→Tokio, `simplified` | 13.432,6 km, 39 vértices, cruza Asia por Rusia, no cruza el antimeridiano |
| Suma Haversine de esa geometría | 12.237,7 km, un 8,9 % por debajo de `distanceKm` |
| `/table` con 50 coordenadas | `code: Ok` en 442 ms, 2 pares con `null` |
| Lisboa→Sídney en `/table` | `null`, no hay camino terrestre |
| `driving` vs `foot` vs `bike` | Respuestas byte-idénticas, `weight_name: routability` |
| `routing.openstreetmap.de` | HTTP 404 en `/route/v1/{perfil}/…`; solo `router.project-osrm.org` responde |
| Lisboa→Tokio en `/route` | `code: Ok`, no `NoRoute` |
| Coste estimado del lote | 304 × (1 tabla + ≤5 rutas) = ≤1.824 peticiones, unos 37 min a 1,2 s |
| Lote completo 2026-09-26 (medido) | 304 orígenes, 1.402 peticiones a ~1,5 s (~40 min); 999 rutas de 235 orígenes, 69 orígenes sin ruta (islas, otro continente), 521 descartes, 0 cruces de antimeridiano; `car_routes.json` v1.0.0 de 3,3 MB; distancias 1,8–8.222,8 km, duraciones 0,1–372,5 h |
| Tolerancia ±20 % → ±25 % | Lhasa→Chengdu −20,4 %, Tiksi→Magadán −20,2 %, Nizhneyansk→Magadán −22,7 %; las tres verificadas con `overview=full` (12k–27k vértices) a ±0,3 %: la distancia OSRM es real, la que pierde es la polilínea `simplified` en alta montaña |
| `429` en el lote real | 9 avisos absorbidos por el backoff; 3 rutas (Tarawa→Suva, Parauapebas→Two Boats, Horta→Porta Delgada) agotaron los 3 reintentos → `[SKIP]`, el lote continúa |
| Guarda `SNAP_MAX_KM` en campo | Regina→Baker Lake descartada como `NoSegment` (enganche a 621,6 km: OSRM cruzó a otra costa); tope `snapKm` máximo real en el lote: 15,1 km (djanet, pista del desierto) |

---

## 11. Preguntas abiertas (resueltas por esta especificación)

- Pool acotado a las 5 ciudades más cercanas → sí, techo de 6 peticiones por origen
- Perfil único `car`, el resto aborta → sí
- Artefacto `assets/data/car_routes.json` → sí
- Lote de los 304 orígenes con pausas → sí
- Caché en `SENSIBLE/.cache` y `.gitignore` arreglado → sí
- Distancia de OSRM, no Haversine → sí
- `durationHours` incluido → sí
- `roadOrigin`/`roadDest` con `snapKm` en lugar de puertos → sí
- Geometría `simplified` → sí
- Tope de distancia por ruta → ninguno

> Siguiente paso tras aprobar esta spec: ejecutar `/spec-impl 006-fog-car-routes` (pasos §4) con validación `json.tool` + `flutter analyze` verde.
