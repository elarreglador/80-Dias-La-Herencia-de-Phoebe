---
name: fogg-sea-routes
description: Skill local Python para calcular 5 rutas marítimas más cortas hacia el Este con searoute (offline, sin key), validando puerto <10 km Haversine y persistiendo GeoJSON LineString en sea_routes.json. Exclusiva proyecto eu.elarreglador.pf.
---

# Fogg Sea Routes — 5 rutas marítimas Este

Skill local que recorre `assets/data/locations.json` (304 ciudades, orden Este desenrollado) desde una ciudad origen, valida puerto cercano vía `searoute` (snap Haversine <10 km), calcula las 5 rutas marítimas más cortas (km) y persiste `assets/data/sea_routes.json` con merge idempotente `origin::destination`.

## Cuándo usar

- Generar `sea_routes.json` para una ciudad origen: `sea_route.py --city "Londres"`
- Validar sin escribir disco: `sea_route.py --city "Londres" --dry-run`
- Re-calcular forzando sobrescritura: `sea_route.py --city "Londres" --force`
- Origen inland debe fallar con sugerencias: `sea_route.py --city "Niamey"`

## Fuentes

- **Primario (offline, sin key):** `assets/data/locations.json` — catálogo canónico `eu.elarreglador.pf` v1.0.1, 304 ciudades, orden Este `lng` creciente con desenrollado `offset+=360` (idéntico a `fogg-city-enricher` y `lib/domain/entities/fogg_route.dart:_isEastward`). Campos `{name, asciiname, lat, lng, timezone}`.
- **Routing marítimo:** `searoute==1.6.0` PyPI — `searoute.searoute([lng,lat],[lng,lat], units="km") → GeoJSON Feature LineString` (avoid land, offline, sin key, depende de `shapely`/`geos`). `properties.length` (km) y `geometry.coordinates` `[lng,lat]`.
- **Destino:** `assets/data/sea_routes.json` — `{meta, routes:[{origin,destination,lat,lng,distanceKm,geometry}]}` con `meta.units=="km"`, `thresholdKm==10`, `searoute=="1.6.0"`.

## Flujo Este desenrollado + 10 km

1. **Normaliza** `--city` con NFD `casefold` (sin acentos) sobre `name` y `asciiname`; valida existencia en `locations.json` (exit 1 con 3 sugerencias si miss).
2. **Calcula `lng_u` desenrollado** para todo el catálogo: `offset=0`, `currUnwrapped=lng+offset`, si `currUnwrapped <= prevUnwrapped` → `offset+=360`. Determina `originIdx` e `originLng_u`.
3. **Valida origen costero (una vez):** invoca `searoute` a un destino Este cercano; mide `snapOriginKm` Haversine ciudad→`coords[0]`. Si `>100km` → aborta `exit 1 "origin has no port within 10km"` y lista 3 ciudades costeras Este sugeridas (<30km snap). Si `10< snap <=100` → `WARN` estuarino (ej. Londres Támesis 23.6 km, Bombay 16.6 km) y continúa — documentado en Riesgos.
4. **Recorre** `i=originIdx+1 .. len(cities)-1` (sin wrap en MVP). Para cada `dest` verifica `lng_u > origin_lng_u` (redundante si catálogo ordenado).
5. **Invoca `searoute`** por candidata. Si excepción (tierra profunda) → `SKIP` con `WARN`.
6. **Valida snap puerto:** `snapOriginKm` (ciudad origen→`coords[0]`) y `snapDestKm` (ciudad destino→`coords[-1]`) vía Haversine. Si `snapDestKm >10km` → `SKIP inland (>10km)`. `snapOriginKm>10` solo `WARN` estuarino (no descarta), salvo `>100km` global.
7. **Acumula candidatos válidos** `{city, distanceKm, geometry, snapOriginKm, snapDestKm}`.
8. **Ordena** por `distanceKm` ascendente y toma `limit` (default 5). Construye `route` con `origin/destination` (nombres canónicos), `originLat/originLng/destinationLat/destinationLng` numéricos, `distanceKm` (float 1 decimal, `properties.length`), `geometry: {type:"LineString", coordinates:[lng,lat]}`.
9. **Valida** cada ruta: `0<distanceKm<40000`, `coordinates.length>=2`, `lng∈[-180,180] lat∈[-90,90]`, suma Haversine segmentos ±20% de `distanceKm` (WARN si diverge).
10. **Merge idempotente** en `sea_routes.json`: clave `origin::destination` (case-sensitive `name` canónico). Reemplaza existentes, hace `append` nuevas, preserva otras. Actualiza `meta.generated` a hoy `YYYY-MM-DD` y bump `meta.version` `1.0.0→1.0.1` solo si hubo cambio real (`json.dumps(sort_keys=True)`).
11. **Escribe** `json.dump(indent=2, ensure_ascii=False)` si no `--dry-run`. `--dry-run` solo lista `OK`/`SKIP` sin tocar disco. `--force` recalcula aunque exista.

## Rate limiting

- `searoute` es offline (malla marítima empaquetada), sin key, sin `sleep` ni `429`. No requiere throttling.
- Si futuro fallback de puertos usa red (WPI/Overpass) → añadir `sleep 1` y `429 backoff` como `fogg-city-enricher`.

## Archivos del proyecto

- `assets/data/locations.json` → catálogo solo lectura (fuente de verdad Este).
- `assets/data/sea_routes.json` → destino persistido (creado por esta skill, merge idempotente).
- `.opencode/skills/fogg-sea-routes/sea_route.py` → CLI principal.
- `.opencode/skills/fogg-sea-routes/requirements.txt` → `searoute==1.6.0`.
- `lib/domain/entities/fogg_route.dart:_isEastward` → invariante espejada (desenrollado).

## Ejemplos

```bash
pip install -r .opencode/skills/fogg-sea-routes/requirements.txt

python3 .opencode/skills/fogg-sea-routes/sea_route.py --help
# uso: --city "Londres" [--limit 5] [--dry-run] [--force]

python3 .opencode/skills/fogg-sea-routes/sea_route.py --city "Londres" --dry-run
# [INFO] Origin: Londres (-0.12574, 51.50853) lng_u -0.13
# [OK] 01 Genova 3.2km dest 4080.9km
# [SKIP] 02 París inland snapDest 152.9km >10
# [SKIP] 03 Bruselas inland 54.9km >10
# ...

python3 .opencode/skills/fogg-sea-routes/sea_route.py --city "Londres"
# [INFO] 33 candidatos válidos, seleccionando 5 más cortas
# [INFO] Saved 5 routes to assets/data/sea_routes.json
# cat assets/data/sea_routes.json | python3 -m json.tool

python3 .opencode/skills/fogg-sea-routes/sea_route.py --city "Londres" --limit 3 --dry-run
# solo 3 más cortas

python3 .opencode/skills/fogg-sea-routes/sea_route.py --city "Niamey" --dry-run
# [ERROR] origin has no port within 10km (snap 798.5km) — sugiere: Malabo, Libreville, Kano
```

## Límites y Riesgos documentados

- **Snap estuarino >10km falso negativo:** `searoute` hace snap al mar pero para puertos fluviales (Londres Támesis 23.6 km, Amsterdam 16.0 km, Bombay 16.6 km, Suez 26.9 km) la distancia Haversine ciudad→`coords[0]` supera 10 km. Mitigación: `snapOrigin` solo `WARN` (no `SKIP`), permitiendo rutas; `snapDest` sigue estricto 10 km. Si sistemáticamente bloquea puertos reales, subir umbral a 15-30 km en revisión (constante `THRESHOLD_KM`).
- **Antimeridiano:** `geometry.coordinates` conserva `lng∈[-180,180]` con salto `178→-179`; consumidor Flutter debe segmentar con `polylineSegments` (como `FoggRoute`), no se segmenta en esta spec.
- **Origen inland:** si `snapOrigin>100km` (ej. Niamey 798 km) aborta con `exit 1` y 3 sugerencias costeras Este cercanas.
- **`searoute` sin ruta:** `try/except` por candidata, `SKIP` con `WARN`, no aborta batch; batch solo falla si origen inexistente o 0 rutas halladas.
- **Persistencia:** `sea_routes.json` es la caché; sin `SENSIBLE/.cache` en MVP. Merge idempotente evita duplicados `origin::destination`.
