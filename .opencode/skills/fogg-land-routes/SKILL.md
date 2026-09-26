---
name: fogg-land-routes
description: Skill local Python que calcula hasta 5 rutas por carretera hacia el Este por ciudad de locations.json con el servidor demo de OSRM (1 petición/s, User-Agent identificable), descarta pares sin camino y persiste geometrías ancladas a la ciudad en car.json. Solo perfil car. Exclusiva proyecto eu.elarreglador.pf.
---

# Fogg Land Routes — 5 rutas por carretera hacia el Este por ciudad

Recorre `assets/data/locations.json` (304 ciudades), toma por origen sus 5 vecinas más próximas por círculo grande que cumplan la Regla del Este, pregunta al servidor demo de OSRM cuáles tienen camino y persiste como mucho 5 rutas por origen en `assets/data/car.json`.

**Estado actual:** `version 1.0.0`, esquema clonado de `sea_routes.json` v3 con `roadOrigin`/`roadDest` en lugar de `port*`, más `durationHours`. **Lote completo 2026-09-26:** 304 orígenes, 999 rutas de 235 orígenes (69 sin ruta), 521 descartes, 0 cruces de antimeridiano, `assets/data/car.json` de 3,3 MB. `meta.osrmDataVersion` es `"unknown"`: la API v5.24 del demo no expone `data_version` en `/route` ni `/table`.

## Cuándo usar

```bash
python3 .opencode/skills/fogg-land-routes/land_route.py --help
python3 .opencode/skills/fogg-land-routes/land_route.py --dry-run
python3 .opencode/skills/fogg-land-routes/land_route.py
python3 .opencode/skills/fogg-land-routes/land_route.py --city "Lisboa" --dry-run
python3 .opencode/skills/fogg-land-routes/land_route.py --only 20
python3 .opencode/skills/fogg-land-routes/land_route.py --resume
python3 .opencode/skills/fogg-land-routes/land_route.py --out /tmp/prueba.json
```

**El script siempre reescribe el fichero entero.** No hay merge: el JSON es un artefacto derivado y `meta.generated` refleja la fecha de esa generación. `--resume` salta los orígenes ya presentes para recuperar un lote interrumpido; el volcado periódico cada 10 orígenes hace lo mismo sin flags.

## Fuentes

- **Primario (solo lectura):** `assets/data/locations.json` — catálogo canónico `eu.elarreglador.pf`, 304 ciudades `{name, asciiname, lat, lng, timezone}`, orden Este desenrollado.
- **Routing terrestre (con red, sin key):** servidor demo de OSRM `https://router.project-osrm.org` — servicios `/table/v1/car` (matriz, `null` si no hay camino) y `/route/v1/car` (`geometries=geojson&overview=simplified&steps=false`). `routes[0].distance` en metros, `routes[0].duration` en segundos, `waypoints[].name` la calle de enganche.
- **Destino:** `assets/data/car.json` — `{meta, routes[]}` (esquema abajo).
- **Caché:** `SENSIBLE/.cache/fogg-land-routes/{profile}/{sha1(url)}.json` — respuesta cruda de OSRM, nunca estructuras derivadas. `SENSIBLE/` está en `.gitignore` (SPEC 006, paso 1).

## Flujo

1. **Carga** `locations.json` y valida `name/lat/lng/timezone` numéricos; calcula `lng_u` desenrollado como en `sea_route.py`.
2. **Rechaza** `--profile distinto de car` con código 1: el servidor devuelve respuestas byte-idénticas para `driving`, `foot` y `bike` (`weight_name=routability`); escribir `foot.json` sería un fichero mentiroso.
3. **Construye el pool** por origen (`build_pool`): `0 < eastward_delta < = 180` sobre la **ciudad**, excluye el propio nombre, ordena por Haversine y corta a `--pool` (5). Techo demostrable: 1 `/table` + como mucho 5 `/route` por origen.
4. **Matriz** (`table_distances`): una llamada `/table` con origen + candidatas (como mucho 6 coordenadas). Todo `distances[i] == null` se descarta con `[SKIP] sin camino terrestre`; el origen puede quedar con 0 rutas (islas, otro continente) sin que el lote falle.
5. **Geometrías** (`build_route`): una llamada `/route` por candidata superviviente; `normalize_lng` en cada vértice; `anchor_to_cities()` antepone/pospone la ciudad sin sustituir el camino intermedio; `distanceKm = distance/1000` (1 decimal), `durationHours = duration/3600` (1 decimal); `roadOrigin/roadDest` con `name/lat/lng/snapKm` (aviso en log si `snapKm > 1 km`; descarte como `NoSegment` si `snapKm > 50 km`, ver riesgos).
6. **Valida** (`validate_dataset`) y, si no hay problemas, escribe con `indent=2, ensure_ascii=False` y revalida el JSON tras escribir.

## Política del servidor y coste del lote

| Regla | Valor |
|---|---|
| Servidor | `https://router.project-osrm.org` (demo, FOSSGIS, sin SLA) |
| Ritmo máximo | 1 petición/s → pausa `MIN_INTERVAL_S = 1.2 s` entre llamadas |
| Identificación | `User-Agent: eu.elarreglador.pf/1.0` |
| `429` | Reintentos a 5 s, 15 s y 45 s; agotados, se registra y se sigue |
| Timeout | 60 s por petición |
| Techo por origen | 1 `/table` + ≤5 `/route` = ≤6 peticiones |
| Lote completo | 304 × 6 = ≤1.824 peticiones, ~37 min a 1,2 s |
| Lote 2026-09-26 (medido) | 1.402 peticiones a ~1,5 s (~40 min); 9× `429` absorbidos por el backoff, 3 rutas agotaron reintentos → `[SKIP]` |
| Corte por horas | `--only N` escribe lo acumulado y sale con código 0 |

La caché hace que la segunda corrida idéntica no toque la red: dos llamadas al mismo `url` devuelven la segunda desde disco sin esperar el intervalo.

## Perfiles medidos (2026-09-26, sondeo de la SPEC 006)

| Prueba | Resultado |
|---|---|
| `driving` vs `foot` vs `bike` | Respuestas byte-idénticas, `weight_name: routability` |
| Conclusión | El demo solo sirve datos de coche; esta spec solo emite `car` |
| `overview=full` Lisboa→Madrid | 625,6 km, 4.895 vértices, 116 KB |
| `overview=simplified` Lisboa→Madrid | 625,6 km, 55 vértices, 1,3 KB |
| Lisboa→París `simplified` | 1.735,5 km, 18,3 h, 23 vértices |
| Lisboa→Tokio `simplified` | 13.432,6 km, 39 vértices, puente terrestre del norte |
| Suma Haversine de esa geometría | 12.237,7 km, −8,9 % bajo `distanceKm` (recorte de curvas) |
| `/table` Lisboa→Sídney | `null`, sin camino terrestre |

Por eso `overview=simplified` es fijo y sin flag (un lote en `full` pesaría ~160 MB), `distanceKm` es el dato de OSRM (nunca Haversine recalculado) y la validación tolera ±25 %: el `simplified` recorta hasta un 22,7 % en alta montaña (Nizhneyansk→Magadán, verificado contra `full` a ±0,3 %).

## Esquema `car.json` v1.0.0

```jsonc
{
  "meta": {
    "project": "eu.elarreglador.pf", "version": "1.0.0",
    "tool": "fogg-land-routes", "profile": "car",
    "osrmServer": "https://router.project-osrm.org",
    "osrmWeightName": "routability", "osrmDataVersion": "2026-09-20T00:00:00Z",
    "units": "km", "limitPerOrigin": 5, "candidatePool": 5, "maxEastDeg": 180,
    "origins": 304, "routes": 0, "originsWithoutRoute": 0, "unroutableCities": 0,
    "crossesAntimeridian": 0,
    "attribution": "© OpenStreetMap contributors (ODbL); routing courtesy of the OSRM demo server sponsored by FOSSGIS",
    "source": "OSRM demo server (car) + GeoNames cities15000"
  },
  "routes": [{
    "origin": "Lisboa", "destination": "París", "distanceKm": 1735.5, "durationHours": 18.3,
    "roadOrigin": {"name": "…", "lat": 38.72494, "lng": -9.14965, "snapKm": 0.0},
    "roadDest":   {"name": "…", "lat": 48.85363, "lng": 2.34921, "snapKm": 0.0},
    "geometry": {"type": "LineString", "coordinates": [[-9.1498, 38.72509], "…", [2.3488, 48.85341]]}
  }]
}
```

### Geometría de ciudad a ciudad

`geometry.coordinates[0]` son las coordenadas de `origin` y `[-1]` las de `destination`, redondeadas a 5 decimales. OSRM devuelve el punto enganchado a la calzada; `anchor_to_cities` lo conserva en medio y añade la ciudad en cada extremo. `distanceKm` no incluye corrección alguna por ese tramo: es `routes[0].distance` tal cual.

## Regla del Este

`0 < deltaLng <= 180` con longitud desenrollada, medida **sobre la ciudad** (a diferencia de la SPEC 004, que medía sobre el puerto: aquí el enganche es de metros, no de kilómetros, y no altera el orden). Lisboa→Tokio por Rusia es legal y es contenido del juego de 80 días, no un fallo.

## Antimeridiano

`coordinates` siempre en `[-180, 180]`; el salto `179 → -179` lo segmenta el consumidor (`splitAntimeridian` en el visor, `FoggRoute.polylineSegments` en Dart). `meta.crossesAntimeridian` lo cuenta.

## Riesgos medidos

- **Servidor compartido sin SLA:** pausa de 1,2 s, `User-Agent`, backoff y `--only N`. Si la spec se repite mucho, el siguiente paso es un OSRM propio (fuera de alcance).
- **`simplified` subestima hasta ~23 % en alta montaña:** `distanceKm` es el de OSRM, `meta.distanceNote` lo declara, la validación tolera ±25 % (medido 2026-09-26: Nizhneyansk→Magadán −22,7 %, Lhasa→Chengdu −20,4 %, Tiksi→Magadán −20,2 %; las tres verificadas contra `overview=full` a ±0,3 %).
- **Enganche lejos del centro:** `snapKm` queda en el JSON y el log avisa por encima de 1 km; es un aviso, no un fallo. Pero por encima de 50 km (`SNAP_MAX_KM`) la ruta se descarta: medido en campo, OSRM cruza el mar hasta otra costa (Trípoli→Lampedusa, 294 km; Djanet→Lampedusa, 1.302 km; Regina→Baker Lake, 621,6 km) y devuelve la distancia desde allí, no desde la ciudad. Sin este tope, el tramo ancla rompe la tolerancia ±25 %.
- **Pool de 5 sin garantía de 5 rutas:** un origen rodeado de mar queda con 0 rutas; `originsWithoutRoute` y el log lo hacen visible.
- **`NoSegment` en islas sin red:** se cuenta en `unroutableCities`, el lote continúa.
- **Datos de terceros versionados:** `meta.attribution` (ODbL + FOSSGIS) y `meta.osrmDataVersion` delatan regeneraciones contra datos distintos.

## Archivos del proyecto

- `assets/data/locations.json` → catálogo solo lectura.
- `assets/data/car.json` → artefacto derivado, reescrito por esta skill.
- `.opencode/skills/fogg-land-routes/land_route.py` → CLI principal (stdlib puro).
- `.opencode/skills/fogg-land-routes/requirements.txt` → vacío intencional.
- `SENSIBLE/.cache/fogg-land-routes/` → caché cruda (gitignored).
- `docs/specs/006-fog-car-routes.md` → especificación.
