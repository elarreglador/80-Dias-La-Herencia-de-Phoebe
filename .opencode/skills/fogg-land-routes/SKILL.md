---
name: fogg-land-routes
description: Skill local Python que calcula hasta 5 rutas por carretera hacia el Este por ciudad de locations.json con el servidor demo de OSRM (1 petición/s, User-Agent identificable), con fallback al Oeste si un origen no llega a 2 rutas, descarta pares sin camino (verificándolos con /route cuando el /table devuelve nulos espurios) y persiste geometrías ancladas a la ciudad en car_routes.json. Solo perfil car. Exclusiva proyecto eu.elarreglador.pf.
---

# Fogg Land Routes — 5 rutas por carretera hacia el Este por ciudad

Recorre `assets/data/locations.json` (304 ciudades), toma por origen sus 5 vecinas más próximas por círculo grande que cumplan la Regla del Este (con pool oeste de reserva para no dejar a nadie sin salida), pregunta al servidor demo de OSRM cuáles tienen camino y persiste como mucho 5 rutas por origen en `assets/data/car_routes.json`.

**Estado actual:** `version 1.1.0`, esquema clonado de `sea_routes.json` v3 con `roadOrigin`/`roadDest` en lugar de `port*`, más `durationHours` y `heading`. **Lote completo 2026-09-26 + corrección 2026-10-07:** 304 orígenes, 1001 rutas de 236 orígenes (68 sin ruta), 525 descartes, 0 cruces de antimeridiano, `assets/data/car_routes.json` de 3,5 MB. `meta.osrmDataVersion` es `"unknown"`: la API v5.24 del demo no expone `data_version` en `/route` ni `/table`.

## Cuándo usar

```bash
python3 .opencode/skills/fogg-land-routes/land_route.py --help
python3 .opencode/skills/fogg-land-routes/land_route.py --dry-run
python3 .opencode/skills/fogg-land-routes/land_route.py
python3 .opencode/skills/fogg-land-routes/land_route.py --city "Lisboa" --dry-run
python3 .opencode/skills/fogg-land-routes/land_route.py --only 20
python3 .opencode/skills/fogg-land-routes/land_route.py --resume
python3 .opencode/skills/fogg-land-routes/land_route.py --close-gaps
python3 .opencode/skills/fogg-land-routes/land_route.py --pair "Tánger|Tripoli" --pair "Lisboa|Madrid"
python3 .opencode/skills/fogg-land-routes/land_route.py --out /tmp/prueba.json
```

`--pair "ORIGEN|DESTINO"` (repetible) fuerza un par curado a mano entre dos ciudades, aunque el origen ya tenga sus 5 rutas del lote. La ruta se marca `explicit: true`, **no cuenta para `limitPerOrigin`** (igual que las gapClosed) y hace merge sobre el fichero existente, así no desaparece en futuras regeneraciones. Deriva `heading` del delta entre ciudades (un par al Oeste se escribe con `heading: west`), reutiliza `build_route` y omite con aviso los pares ya presentes.

**Por defecto reescribe el fichero entero.** `--resume` cambia a merge: carga las rutas existentes, rellena `heading` en las del esquema 1.0.0 (todas `east`), salta los orígenes ya presentes y solo calcula los que falten; siembra `unroutableCities` del meta previo y deriva `origins`/`originsWithoutRoute` del fichero para que los contadores no se reinicien. El volcado periódico cada 10 orígenes protege los lotes largos sin flags.

## Fuentes

- **Primario (solo lectura):** `assets/data/locations.json` — catálogo canónico `eu.elarreglador.pf`, 304 ciudades `{name, asciiname, lat, lng, timezone}`, orden Este desenrollado.
- **Routing terrestre (con red, sin key):** servidor demo de OSRM `https://router.project-osrm.org` — servicios `/table/v1/car` (matriz, `null` si no hay camino) y `/route/v1/car` (`geometries=geojson&overview=simplified&steps=false`). `routes[0].distance` en metros, `routes[0].duration` en segundos, `waypoints[].name` la calle de enganche.
- **Destino:** `assets/data/car_routes.json` — `{meta, routes[]}` (esquema abajo).
- **Caché:** `SENSIBLE/.cache/fogg-land-routes/{profile}/{sha1(url)}.json` — respuesta cruda de OSRM, nunca estructuras derivadas. `SENSIBLE/` está en `.gitignore` (SPEC 006, paso 1).

## Flujo

1. **Carga** `locations.json` y valida `name/lat/lng/timezone` numéricos; calcula `lng_u` desenrollado como en `sea_route.py`.
2. **Rechaza** `--profile distinto de car` con código 1: el servidor devuelve respuestas byte-idénticas para `driving`, `foot` y `bike` (`weight_name=routability`); escribir `foot.json` sería un fichero mentiroso.
3. **Construye el pool** por origen (`build_pool`): `0 < eastward_delta <= 180` sobre la **ciudad** (`direction="east"`), excluye el propio nombre, ordena por Haversine y corta a `--pool` (5). Techo demostrable: 1 `/table` + como mucho 5 `/route` por origen.
4. **Matriz** (`table_distances`): una llamada `/table` con origen + candidatas (como mucho 6 coordenadas). Un `null` de celda **no se descarta en la matriz**: el demo devuelve nulos espurios (Teresina→Salvador es enrutable con 1.146,5 km / 15,9 h y el `/table` lo niega), así que la verificación la hace `build_route` con `/route` (y `SNAP_MAX_KM` descarta los enganches fantasma a miles de km). El origen puede quedar con 0 rutas (islas, otro continente) sin que el lote falle.
4b. **Fallback al Oeste:** si al origen le quedan menos de `MIN_ROUTES_PER_ORIGIN` (2) rutas este, se consulta un segundo `/table` con el pool oeste (5 vecinas con `-180 <= deltaLng < 0`) y se completan huecos hasta el mínimo. Prioridad: una ciudad que no puede ser origen deja al jugador bloqueado, así que la Regla del Este cede.
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

## Cierre de huecos (SPEC 008, `--close-gaps`)

Pasada posterior al lote normal (no lo sustituye) que garantiza ≥1 salida y ≥1 entrada por ciudad en la **unión mar ∪ tierra**. Requiere que `assets/data/car_routes.json` ya exista (el cierre sobre un fichero vacío no tiene sentido).

- **Salidas:** para cada ciudad sin salida, pool este primero y pool oeste después (`GAP_POOL` 25 candidatas por Haversine); 1 `/table` + como mucho 1 `/route` por hueco. Si el `/table` da nulos espurios, se verifica con `/route` la candidata más cercana.
- **Entradas:** para cada ciudad sin entrada, candidatas origen por Haversine, primero con capacidad (`< limitPerOrigin` rutas **normales**; las `gapClosed` no cuentan para el límite); 1 `/table` compartida por hueco y hasta `MAX_GAP_ROUTE_TRIES = 5` intentos de `/route` (el primer candidato suele ser isla o par sin enganche rodado).
- **Guardias antifantasma:** `SNAP_MAX_KM` (50 km de enganche) y `gap_route_ok` (±25 % entre `distanceKm` y la suma Haversine); medido: Tarifa↔Tánger devuelve `distanceKm 1,3` con geometría anclada de 35,3 km.
- **Coste:** ≤ `huecos × (1 /table + 1 /route)` en salidas y ≤ `huecos × (1 /table + 5 /route)` en entradas, al ritmo de 1,2 s/petición (≈59 huecos ≈ 7 min).
- **Meta:** al escribir añade `meta.gapClosedRoutes` y `meta.coverage {cities, withoutOutbound, withoutInbound, exceptions}`.
- **Validación:** `validate_dataset` termina con los problemas de `tools/route_coverage.py` (unión mar ∪ tierra): cualquier ciudad sin salida o sin entrada y sin `excepción` registrada produce `[ERROR]` y no se escribe.

**Regla de excepciones:** `python3 tools/route_coverage.py --write-report` regenera `docs/ciudades-sin-rutas.md` conservando la columna `Decisión` a mano; una ciudad aceptada lleva `excepción — <motivo>`. `python3 tools/route_coverage.py` imprime los recuentos y sale con código 0 cuando no queda ninguna pendiente (código 2 en tanto la haya).

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

## Esquema `car_routes.json` v1.1.0

```jsonc
{
  "meta": {
    "project": "eu.elarreglador.pf", "version": "1.1.0",
    "tool": "fogg-land-routes", "profile": "car",
    "osrmServer": "https://router.project-osrm.org",
    "osrmWeightName": "routability", "osrmDataVersion": "2026-09-20T00:00:00Z",
    "units": "km", "limitPerOrigin": 5, "candidatePool": 5, "maxEastDeg": 180,
    "minRoutesPerOrigin": 2,          // umbral del fallback al Oeste
    "origins": 304, "routes": 1001, "originsWithoutRoute": 68, "unroutableCities": 525,
    "crossesAntimeridian": 0,
    "eastRule": "heading east: 0 < deltaLng(cityDest - cityOrigin) <= 180 (desenrollado); heading west: -180 <= deltaLng < 0, solo como fallback …",
    "attribution": "© OpenStreetMap contributors (ODbL); routing courtesy of the OSRM demo server sponsored by FOSSGIS",
    "source": "OSRM demo server (car) + GeoNames cities15000"
  },
  "routes": [{
    "origin": "Lisboa", "destination": "París", "distanceKm": 1735.5, "durationHours": 18.3,
    "heading": "east",                // east|west, coherente con el signo de deltaLng
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

**Excepción `heading: "west"` (v1.1):** si un origen no llega a `minRoutesPerOrigin` (2) rutas este, se completa con las más cercanas al Oeste (`-180 <= deltaLng < 0`) y la ruta lleva `heading: "west"`. Prioridad: una ciudad que no puede ser origen deja al jugador bloqueado. `validate_dataset` exige coherencia entre `heading` y el signo del delta. Corrida 2026-10-07: Teresina, la única ciudad de interior del catálogo que era solo destino, obtuvo Teresina→Salvador (`east`, 1.146,5 km) y Teresina→Parauapebas (`west`, 956,5 km).

## Antimeridiano

`coordinates` siempre en `[-180, 180]`; el salto `179 → -179` lo segmenta el consumidor (`splitAntimeridian` en el visor, `FoggRoute.polylineSegments` en Dart). `meta.crossesAntimeridian` lo cuenta.

## Riesgos medidos

- **Servidor compartido sin SLA:** pausa de 1,2 s, `User-Agent`, backoff y `--only N`. Si la spec se repite mucho, el siguiente paso es un OSRM propio (fuera de alcance).
- **`simplified` subestima hasta ~23 % en alta montaña:** `distanceKm` es el de OSRM, `meta.distanceNote` lo declara, la validación tolera ±25 % (medido 2026-09-26: Nizhneyansk→Magadán −22,7 %, Lhasa→Chengdu −20,4 %, Tiksi→Magadán −20,2 %; las tres verificadas contra `overview=full` a ±0,3 %).
- **Enganche lejos del centro:** `snapKm` queda en el JSON y el log avisa por encima de 1 km; es un aviso, no un fallo. Pero por encima de 50 km (`SNAP_MAX_KM`) la ruta se descarta: medido en campo, OSRM cruza el mar hasta otra costa (Trípoli→Lampedusa, 294 km; Djanet→Lampedusa, 1.302 km; Regina→Baker Lake, 621,6 km) y devuelve la distancia desde allí, no desde la ciudad. Sin este tope, el tramo ancla rompe la tolerancia ±25 %.
- **Pool de 5 sin garantía de 5 rutas:** un origen rodeado de mar queda con 0 rutas; `originsWithoutRoute` y el log lo hacen visible. Desde v1.1 el pool oeste cubre el mínimo de 2, pero si tampoco hay camino el origen sigue quedando sin salida.
- **`/table` con nulos espurios:** el demo devuelve `null` en celdas que `/route` sí enruta (medido: Teresina→Salvador, 1.146,5 km / 15,9 h). Por eso un `null` de celda no descarta: la verificación es `build_route`. Coste: una petición extra por celda nula (cachéable).
- **`NoSegment` en islas sin red:** se cuenta en `unroutableCities`, el lote continúa.
- **Datos de terceros versionados:** `meta.attribution` (ODbL + FOSSGIS) y `meta.osrmDataVersion` delatan regeneraciones contra datos distintos.

## Archivos del proyecto

- `assets/data/locations.json` → catálogo solo lectura.
- `assets/data/car_routes.json` → artefacto derivado, reescrito por esta skill.
- `.opencode/skills/fogg-land-routes/land_route.py` → CLI principal (stdlib puro).
- `.opencode/skills/fogg-land-routes/requirements.txt` → vacío intencional.
- `SENSIBLE/.cache/fogg-land-routes/` → caché cruda (gitignored).
- `docs/specs/006-fog-car-routes.md` → especificación.
