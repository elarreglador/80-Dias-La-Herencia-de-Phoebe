---
name: fogg-sea-routes
description: Skill local Python que resuelve el puerto de cada ciudad de locations.json con searoute, descarta las que están a más de 10 km del mar, aplica la Regla del Este sobre los puertos y persiste hasta 5 rutas marítimas más cortas por puerto en sea_routes.json (reescritura completa). Exclusiva proyecto eu.elarreglador.pf.
---

# Fogg Sea Routes — 5 rutas marítimas más cortas hacia el Este por puerto

Recorre `assets/data/locations.json` (304 ciudades), resuelve el puerto de cada una con `searoute`, descarta las que no están a `<= 10 km` del mar, aplica la Regla del Este **sobre los puertos** (no sobre las ciudades) y persiste las 5 rutas marítimas más cortas de cada puerto en `assets/data/sea_routes.json`.

**Estado actual:** `version 2.0.0`, 33 orígenes, 165 rutas, 271 ciudades descartadas, 17 cruces del antimeridiano, 9278 vértices, ~1,5 s de ejecución.

## Cuándo usar

```bash
pip install -r .opencode/skills/fogg-sea-routes/requirements.txt   # searoute==1.6.0

sea_route.py --dry-run                # todo el catálogo, no escribe
sea_route.py                          # regenera el JSON completo
sea_route.py --city "Lisboa" --dry-run  # sólo un origen (el pool sigue siendo completo)
sea_route.py --limit 3                # hasta 3 rutas por puerto
sea_route.py --out /tmp/prueba.json   # no toca assets/
```

**El script siempre reescribe el fichero entero.** No hay `--force` ni merge idempotente: el JSON es un artefacto derivado, se regenera desde cero y `meta.generated` refleja la fecha de esa generación. Si se cambia `THRESHOLD_KM` o `MAX_EAST_DEG`, se regenera todo.

## Fuentes

- **Primario (offline, sin key):** `assets/data/locations.json` — catálogo canónico `eu.elarreglador.pf`, 304 ciudades `{name, asciiname, lat, lng, timezone}`, orden Este desenrollado.
- **Routing marítimo:** `searoute==1.6.0` — `setup_M()` (malla, 9708 nodos) y `setup_P()` (WPI, 3955 puertos). `searoute([lng,lat],[lng,lat], units="km")` → GeoJSON `Feature`; `properties.length` en km, `geometry.coordinates` en `[lng, lat]`.
- **Destino:** `assets/data/sea_routes.json` — `{meta, routes[]}` (esquema abajo).

## Flujo

1. **Carga** `locations.json` y valida que cada ciudad tenga `name/lat/lng/timezone` numéricos.
2. **Resuelve el puerto de las 304 ciudades** (siempre todas, aunque se filtren orígenes con `--city`, porque el *pool* de destinos debe ser el completo):
   - `sea_snap_km()` enrutado a un punto sonda 0,7° al Este (o al Oeste si el Este pasa de 179°): distancia Haversine ciudad→primer vértice de la malla. Es la medida de "distancia al mar".
   - `> THRESHOLD_KM` (10) → ciudad descartada, se registra con su `seaKm`.
   - `resolve_port()` con `include_ports=True`: `properties.port_origin` da `{port, name, cty, x, y}` del WPI. El país se humaniza (`French_polynesia` → `French Polynesia`); el código es la clave.
3. **Ordena** los puertos válidos por `port.lng` ascendente (para que el JSON salga en orden Este reproducible).
4. **Selecciona** por puerto origen: candidatos con `0 < eastward_delta(portOrigin.lng, portDest.lng) <= 180`, ordenados por distancia de círculo grande.
   - **Poda por cota inferior:** en cuanto la gc del candidato supera la de la 5ª ya seleccionada, se para el bucle. La distancia marítima nunca es menor que la gc, así que es correcto por construcción y verificado idéntico a calcular el top-5 sin podar.
   - `searoute` de ciudad a ciudad con `include_ports=True`; excepción → `SKIP` con `WARN` y sigue.
   - Las 5 más cortas se ordenan por `distanceKm` ascendente.
5. **Normaliza** cada vértice con `normalize_lng()` a `[-180, 180]`. `searoute` entrega el marco desenrollado y se sale del rango (devuelve `lng` hasta `-208.8`); sin esto el visor **rechaza el fichero entero**.
6. **Valida** y, si no hay problemas, escribe con `indent=2, ensure_ascii=False` y revalida el JSON.

## Esquema `sea_routes.json` v2

```jsonc
{
  "meta": {
    "project": "eu.elarreglador.pf",
    "version": "2.0.0", "generated": "2026-09-26",
    "tool": "fogg-sea-routes", "searoute": "1.6.0",
    "units": "km",                    // obligatorio: lo exige el visor
    "thresholdKm": 10, "maxEastDeg": 180, "limitPerOrigin": 5,
    "origins": 33, "routes": 165, "citiesWithoutPort": 271,
    "crossesAntimeridian": 17,        // informativo
    "eastRule": "0 < deltaLng(portDest - portOrigin) <= 180 (desenrollado)",
    "geometry": "LineString [lng,lat] …",
    "source": "searoute (avoid land) + GeoNames cities15000"
  },
  "routes": [{
    "origin": "Sidney", "originLat": -33.86882, "originLng": 151.20929,
    "destination": "Apia", "destinationLat": -13.83452, "destinationLng": -171.76310,
    "distanceKm": 4706.1,
    "portOrigin": { "code": "AUSYD", "name": "Sydney", "country": "Australia",
                    "lat": -33.85, "lng": 151.2, "seaKm": 1.6 },
    "portDest":   { "code": "WSAPW", "name": "Apia", "country": "Samoa",
                    "lat": -13.85, "lng": -171.76, "seaKm": 2.6 },
    "geometry": { "type": "LineString", "coordinates": [[151.2, -33.85], …] }
  }]
}
```

`v2` breaking: se añadió `portOrigin`/`portDest` y la Regla del Este pasó de las ciudades a los puertos, así que las 9 rutas de `v1.0.1` no son comparables (5 de ellas además eran westward).

## Regla del Este

`0 < deltaLng <= 180` con longitud **desenrollada**: `normalize_lng(b - a)`, de modo que Tokio → San Francisco es legal (cruza el antimeridiano hacia el Este) y Sidney → Lisboa no. Idéntico criterio a `FoggRoute.validated` / `_isEastward` en Dart, pero medido **de puerto a puerto**: con las ciudades, Denver (-104,99) y Ciudad de México (-99,13) quedan casi a la misma longitud, y Denver ganaría a Ciudad de México por 5,8° de diferencia.

## Antimeridiano

`geometry.coordinates` está **siempre en `[-180, 180]`** y una ruta que lo cruza tiene un salto `179 → -179` entre vértices. Segmentar es obligación del consumidor:

- Visor dev: `splitAntimeridian()` (`tools/locations-map/app.js:163`) inserta `[180, lat]` / `[-180, lat]` e interpola la latitud.
- Dart: `FoggRoute.polylineSegments` (`lib/domain/entities/fogg_route.dart:55`) hace lo mismo en Y Mercator.

De las 165 rutas, **17 cruzan** (Sidney, Townsville, Melbourne y Fukuoka hacia el Pacífico). De los 981 candidatos, 74 cruzan: hay que medir el cruce sobre el subconjunto que se escribe, no sobre el total.

## Umbral de mar

Sensibilidad medida con el mismo criterio (`orígenes` = ciudades a `<= t` km del mar; rutas = máximo 5 por origen):

| `THRESHOLD_KM` | orígenes | rutas |
|---|---|---|
| 5 | 17 | 85 |
| **10** | **33** | **165** |
| 15 | 50 | 250 |
| 20 | 75 | 375 |
| 30 | 97 | 485 |
| 50 | 112 | 560 |

Mediana de las 304 ciudades: 113,6 km al mar. A 10 km salen 33 puertos reales (Fukuoka→Hakata, Ciudad del Cabo→Cape Town, Hanga Roa→Isla de Pascua…); a 20–30 km entran Hamburgo, Dalian y Estocolmo, que no son puertos marítimos y sólo inflan el mapa.

## Límites y riesgos documentados

- **El WPI no sirve como filtro costero.** `include_ports` devuelve 3955 puertos, incluidos fluviales: Denver, Kansas City y Harare están a 0 km de un "puerto" (río Mississippi). El filtro es siempre `sea_snap_km <= THRESHOLD_KM`, nunca `include_ports`.
- **`searoute` entrega longitudes fuera de rango.** El marco desenrollado suma 360 al pasar el antimeridiano (`Denver → Sidney` termina en `-208.817139`). `normalize_lng()` es obligatorio: el visor valida `lng ∈ [-180,180]` en `app.js:136` y lanza `Rutas marítimas inválidas` para *todo* el fichero.
- **Cuidadoso con Haversine.** `sin²(Δλ/2)` es simétrico, así que un Δλ de 356° da el mismo resultado que uno de 4°: no hay que "arreglarlo", pero sí usar `eastward_delta` para no sumar 35.000 km en el salto `179 → -179`.
- **Sondeo de puerto ≠ el puerto de la ruta.** Con el punto sonda 0,7° al Este, Portsmouth resuelve a `GBCOW Cowes` (en la Isla de Wight, ~10 km). Es la respuesta del WPI para la dirección del sondeo, no un error: el `city` manda, `port` documenta.
- **Regla del Este sobre puertos ≠ sobre ciudades**, ver arriba. Y al revés: Honolulu (+157,85) queda al Este de Vancouver (-123,12) y de Ciudad de México (-99,13), lo que es correcto.
- **Sin consumidor Dart todavía.** `lib/` no lee este JSON (cero `rootBundle`). El único consumidor vivo es el visor dev; `TransportMode.ship` aún no lo consume.
- **Sin ruta:** `try/except` por candidata, `SKIP` con `WARN`, no aborta el lote. Sólo aborta si `--limit <= 0`, si la ciudad no existe en `locations.json` o si la validación falla.
- **Orden de escritura:** las rutas se ordenan por puerto origen (de Este a Oeste) y por `distanceKm` ascendente dentro de cada puerto, así que el diff entre regeneraciones es legible.

## Archivos del proyecto

- `assets/data/locations.json` → catálogo solo lectura.
- `assets/data/sea_routes.json` → artefacto derivado, reescrito por esta skill.
- `.opencode/skills/fogg-sea-routes/sea_route.py` → CLI principal.
- `.opencode/skills/fogg-sea-routes/requirements.txt` → `searoute==1.6.0`.
- `tools/locations-map/app.js` → visor dev: valida el JSON y segmenta el antimeridiano.
- `lib/domain/entities/fogg_route.dart` → invariante espejada (`validated`, `polylineSegments`).
