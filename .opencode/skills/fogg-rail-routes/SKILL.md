---
name: fogg-rail-routes
description: Skill local Python que calcula hasta 5 rutas ferroviarias hacia el Este por ciudad de locations.json con la instancia pública de OpenRailRouting (GraphHopper de Geofabrik, perfil non_tgv, 1 petición/s, User-Agent identificable), con fallback al Oeste si un origen no llega a 2 rutas, decodifica la polilínea points_encoded y la simplifica con Douglas-Peucker (tolerancia en metros) antes de persistirla anclada a la ciudad en rail_routes.json. Exclusiva proyecto eu.elarreglador.pf.
---

# Fogg Rail Routes — 5 rutas ferroviarias hacia el Este por ciudad

Recorre `assets/data/locations.json` (257 ciudades), toma por origen sus 5 vecinas más próximas por círculo grande que cumplan la Regla del Este (con pool oeste de reserva para no dejar a nadie sin salida), pregunta a OpenRailRouting cuáles tienen vía de tren con el perfil `non_tgv` y persiste como mucho 5 rutas por origen en `assets/data/rail_routes.json`.

**Estado actual:** `version 1.0.0`, esquema clonado de `car_routes.json` v1.1.0 con `railOrigin`/`railDest` (sin `name`) en lugar de `road*`, y `simplifyMeters`. **Lote 2026-10-10 (SPEC 010):** 257 orígenes, **307 rutas de 103 orígenes** (154 sin ruta: islas y redes inconexas, sobre todo interior de África, Oceanía y el Ártico), 1.320 descartes (1.214 `PointNotFound`, 106 `NoRoute`), 16 `heading west` de fallback, 0 cruces de antimeridiano, `meta.dataTimestamp` = `2026-10-10T04:00:00Z`. `LENGTH_TOLERANCE = 0,25` (0,10 inicial ajustado tras la primera corrida: Kampala→Nairobi, vía montañosa, recorta 14,6 % con `simplifyMeters = 1500`; precedente SPEC 006 §5).

## Cuándo usar

```bash
python3 .opencode/skills/fogg-rail-routes/rail_route.py --help
python3 .opencode/skills/fogg-rail-routes/rail_route.py --dry-run
python3 .opencode/skills/fogg-rail-routes/rail_route.py
python3 .opencode/skills/fogg-rail-routes/rail_route.py --city "Lisboa" --dry-run
python3 .opencode/skills/fogg-rail-routes/rail_route.py --only 20
python3 .opencode/skills/fogg-rail-routes/rail_route.py --resume
python3 .opencode/skills/fogg-rail-routes/rail_route.py --pair "Londres|París" --pair "París|Estambul"
python3 .opencode/skills/fogg-rail-routes/rail_route.py --profile tgv_all --city "París" --dry-run
python3 .opencode/skills/fogg-rail-routes/rail_route.py --out /tmp/prueba.json
```

`--pair "ORIGEN|DESTINO"` (repetible) fuerza un par curado a mano entre dos ciudades, aunque el origen ya tenga sus 5 rutas del lote. La ruta se marca `explicit: true`, **no cuenta para `limitPerOrigin`**, hace merge sobre el fichero existente y deriva `heading` del delta entre ciudades. Para el corredor del juego (Londres→París→Estambul→Bombay→Tokio) los pares que el pool automático no garantice se añaden aquí; las redes inconexas que no tienen vía se descartan por diseño (Bombay→Tokio no existe por el vacío ferroviario de Myanmar).

## Fuentes

- **Primario (solo lectura):** `assets/data/locations.json` — catálogo canónico `eu.elarreglador.pf`, 257 ciudades `{name, asciiname, lat, lng, timezone}`, orden Este desenrollado.
- **Routing ferroviario (con red, sin key):** instancia pública de OpenRailRouting `https://routing.openrailrouting.org` (GraphHopper ferroviario de Geofabrik, "experimental use only, not for production"). `GET /route?point={lat},{lng}&point={lat},{lng}&profile={p}&points_encoded=true`. `paths[0].distance` en metros, `paths[0].time` en ms, `paths[0].points.encoded` la polilínea, `info.road_data_timestamp` la versión de datos. **No hay `/matrix`**.
- **Destino:** `assets/data/rail_routes.json` — `{meta, routes[]}` (esquema abajo).
- **Caché:** `SENSIBLE/.cache/fogg-rail-routes/{profile}/{sha1(url)}.json` — respuesta cruda del servidor, nunca estructuras derivadas. `SENSIBLE/` está en `.gitignore` (SPEC 006, paso 1).

## Flujo

1. **Carga** `locations.json` y valida `name/lat/lng/timezone` numéricos; calcula `lng_u` desenrollado como en `sea_route.py`.
2. **Rechaza** `--profile` fuera de la lista blanca `non_tgv|tgv_all|all_tracks|all_tracks_1435|tramtrain` con código 1: el servidor no sirve perfiles inventados y devuelve la lista de válidos; escribir un fichero con otro perfil sería un artefacto mentiroso.
3. **Construye el pool** por origen (`build_pool`): `0 < eastward_delta <= 180` sobre la **ciudad** (`direction="east"`), excluye el propio nombre, ordena por Haversine y corta a `--pool` (5). Techo demostrable: como mucho 5 `/route` por origen y dirección.
4. **Fallback al Oeste:** si al origen le quedan menos de `MIN_ROUTES_PER_ORIGIN` (2) rutas este, se consulta un segundo pool oeste (`-180 <= deltaLng < 0`) y se completan huecos hasta el mínimo. Prioridad: una ciudad que no puede ser origen deja al jugador bloqueado, así que la Regla del Este cede.
5. **Geometrías** (`build_route`): una `/route` por candidata; decodifica `points_encoded` con `decode_polyline5` (precision 5); deduce `railOrigin`/`railDest` (primer/último vértice) con su `snapKm`; **simplifica con `simplify_dp` (Douglas-Peucker, tolerancia en metros, dedup previo/posterior)**; `normalize_lng` en cada vértice tras el anclaje; `distanceKm = paths[0].distance/1000` (1 decimal), `durationHours = paths[0].time/3.600.000` (1 decimal); `heading` del delta entre ciudades. `length_ok` descarta las rutas cuya suma Haversine (menos los dos `snapKm` del anclaje) se desvía más de `LENGTH_TOLERANCE` (0,10) de `distanceKm`.
6. **Valida** (`validate_dataset`) y, si no hay problemas, escribe con `indent=2, ensure_ascii=False` y revalida el JSON tras escribir. La validación suma el raíl a la unión mar ∪ tierra ∪ raíl de `tools/route_coverage.py` (SPEC 010 §3.3).

**Nota sobre el 400 del servidor:** GraphHopper responde HTTP 400 con `{"message": ...}` para los fallos deterministas (`Cannot find point` → `PointNotFound`, `Connection between locations not found` → `NoRoute`). `router_get` devuelve ese JSON como payload para que `build_route` lo clasifique y lo **cacha**, así una regeneración no vuelve a la red por los pares sin vía.

**Por defecto reescribe el fichero entero.** `--resume` cambia a merge: carga las rutas existentes, salta los orígenes ya presentes y solo calcula los que falten; siembra `unroutableCities` del meta previo y deriva `origins`/`originsWithoutRoute` del fichero para que los contadores no se reinicien. El volcado periódico cada 10 orígenes protege los lotes largos sin flags.

## Política del servidor y coste del lote

| Regla | Valor |
|---|---|
| Servidor | `https://routing.openrailrouting.org` (demo, Geofabrik, experimental, sin SLA) |
| Ritmo máximo | 1 petición/s → pausa `MIN_INTERVAL_S = 1.2 s` entre llamadas |
| Identificación | `User-Agent: eu.elarreglador.pf/1.0` |
| `429` | Reintentos a 5 s, 15 s y 45 s; agotados, se registra y se sigue |
| Timeout | 60 s por petición |
| Techo por origen | ≤5 `/route` Este + ≤5 `/route` Oeste (fallback) = ≤10 peticiones |
| Lote completo | 257 orígenes × ≤10 = ≤2.570 peticiones, ~50 min a 1,2 s |
| Corte por horas | `--only N` escribe lo acumulado y sale con código 0 |

La caché hace que la segunda corrida idéntica no toque la red: dos llamadas al mismo `url` devuelven la segunda desde disco sin esperar el intervalo.

## Perfiles del servidor (2026-10-10, sondeo de la SPEC 010 §10)

| Perfil | Valoración |
|---|---|
| `non_tgv` (default) | Pasajeros sin alta velocidad: engancha de forma fiable con coordenadas de ciudad (Lisboa→Madrid, Chicago→LA, Sídney→Melbourne, Estambul→Ankara) |
| `tgv_all` | Solo alta velocidad; 323,0 km París→Bruselas (1,58 h) |
| `all_tracks` | Incluye cocheras y metro: engancha a componentes aisladas (Lisboa→Madrid → "Connection between locations not found") |
| `all_tracks_1435` | Ancho internacional (1435 mm); depende de la red regional |
| `tramtrain` | Tranvía-tren; cobertura mínima fuera de Europa |

Los 5 están en lista blanca pero solo `non_tgv` está garantizado; los demás quedan documentados como no recomendados.

## Esquema `rail_routes.json` v1.0.0

```jsonc
{
  "meta": {
    "project": "eu.elarreglador.pf", "version": "1.0.0",
    "tool": "fogg-rail-routes", "profile": "non_tgv",
    "routerServer": "https://routing.openrailrouting.org",
    "engine": "OpenRailRouting (GraphHopper fork, Geofabrik)",
    "dataTimestamp": "2026-10-08T04:00:00Z",
    "units": "km", "limitPerOrigin": 5, "candidatePool": 5, "maxEastDeg": 180,
    "minRoutesPerOrigin": 2, "simplifyMeters": 1500,
    "origins": 257, "routes": 0, "originsWithoutRoute": 0,
    "unroutableCities": 0, "crossesAntimeridian": 0,
    "eastRule": "…", "poolRule": "…", "geometry": "…", "distanceNote": "…",
    "attribution": "© OpenStreetMap contributors (ODbL); routing courtesy of OpenRailRouting (Geofabrik) / GraphHopper",
    "source": "OpenRailRouting demo (non_tgv) + GeoNames cities15000"
  },
  "routes": [{
    "origin": "Lisboa", "originLat": 38.72509, "originLng": -9.1498,
    "destination": "Madrid", "destinationLat": 40.4165, "destinationLng": -3.70256,
    "distanceKm": 687.7, "durationHours": 6.3, "heading": "east",
    "railOrigin": {"lat": 38.71395, "lng": -9.12247, "snapKm": 3.4},
    "railDest":   {"lat": 40.40661, "lng": -3.69061, "snapKm": 2.1},
    "geometry": {"type": "LineString", "coordinates": [[-9.1498, 38.72509], "…", [-3.70256, 40.4165]]}
  }]
}
```

### Variaciones respecto a `car_routes.json`

- `railOrigin`/`railDest` → **sin `name`** (GraphHopper no devuelve el nombre de la estación en `/route`) y con `snapKm` como diagnóstico del enganche.
- `meta.simplifyMeters` documenta la tolerancia Douglas-Peucker; `meta.dataTimestamp` es `info.road_data_timestamp` del servidor.
- `meta.distanceNote`: `distanceKm = paths[0].distance/1000` y `durationHours = paths[0].time/3.600.000`; ninguno se recalcula desde la geometría.
- `geometry.coordinates[0]` son las de `origin` y `[-1]` las de `destination`, redondeadas a 5 decimales; `distanceKm` no incluye corrección por el tramo de anclaje.

## Regla del Este

`0 < deltaLng <= 180` con longitud desenrollada, medida **sobre la ciudad** (idéntico a SPEC 006 §12: el enganche a la vía es de metros y no altera el orden entre ciudades casi alineadas). **Excepción `heading: "west"`:** si un origen no llega a `minRoutesPerOrigin` (2) rutas este, se completa con las más cercanas al Oeste. `validate_dataset` exige coherencia entre `heading` y el signo del delta.

## Antimeridiano

`coordinates` siempre en `[-180, 180]`; el salto `179 → -179` lo segmenta el consumidor (`splitAntimeridian` en el visor, `FoggRoute.polylineSegments` en Dart). `meta.crossesAntimeridian` lo cuenta.

## Riesgos medidos y asumidos

- **Instancia experimental sin SLA:** pausa de 1,2 s, `User-Agent`, backoff ante `429` y `--only N`. Si la spec se repite mucho, el siguiente paso es un OpenRailRouting propio (fuera de alcance).
- **Sin `/matrix`:** no se puede podar candidatas con una tabla; el techo sube a `pool` peticiones por origen y dirección (acotado y documentado arriba).
- **Perfiles distintos de `non_tgv` pobres o vacíos:** lista blanca con aviso; el default es `non_tgv`.
- **Enganche lejos del centro:** `snapKm` queda en el JSON y el log avisa por encima de 1 km (es un aviso, no un fallo); `length_ok` descarta rutas cuyo anclaje rompe la tolerancia de longitud.
- **Redes inconexas e islas:** `PointNotFound`/`NoRoute` se registran y no abortan el lote; un origen queda con 0 rutas y aparece en `originsWithoutRoute`. Bombay→Tokio por el vacío de Myanmar es contenido del juego (sin vía), no un fallo.
- **Simplificación y longitud:** Douglas-Peucker con tolerancia en metros y `LENGTH_TOLERANCE` (0,25, ajustado de 0,10 tras la primera corrida: Kampala→Nairobi recorta 14,6 %) verificada sobre la geometría; si una ruta falla, se registra y se ajusta el valor (precedente SPEC 006 §5). Decisión del Señor (2026-10-10): `simplifyMeters = 1500` para cumplir el criterio de "un orden de cientos de vértices" en Estambul→Bombay (30.896 → 574) y mantener el fichero en pocos MB (1,9 MB).
- **Datos de terceros versionados:** `meta.attribution` (OSM ODbL + OpenRailRouting/GraphHopper) y `meta.dataTimestamp` delatan regeneraciones contra datos distintos. Solo se versiona geometría derivada, nunca un extracto OSM.

## Archivos del proyecto

- `assets/data/locations.json` → catálogo solo lectura.
- `assets/data/rail_routes.json` → artefacto derivado, reescrito por esta skill.
- `.opencode/skills/fogg-rail-routes/rail_route.py` → CLI principal (stdlib puro).
- `.opencode/skills/fogg-rail-routes/requirements.txt` → vacío intencional.
- `SENSIBLE/.cache/fogg-rail-routes/` → caché cruda (gitignored).
- `docs/specs/010-fogg-rail-routes.md` → especificación.