---
name: fogg-sea-routes
description: Skill local Python que resuelve el puerto de cada ciudad de locations.json con searoute, descarta las que están a más de 10 km del mar (más 9 costeras forzadas por costa real), aplica la Regla del Este sobre los puertos con fallback al Oeste si un origen no llega a 2 rutas, y persiste hasta 5 rutas marítimas más cortas por puerto en sea_routes.json (reescritura completa o merge con --resume). La LineString arranca y termina en las coordenadas de la ciudad, no en el puerto. Exclusiva proyecto eu.elarreglador.pf.
---

# Fogg Sea Routes — 5 rutas marítimas más cortas hacia el Este por puerto

Recorre `assets/data/locations.json` (304 ciudades), resuelve el puerto de cada una con `searoute`, descarta las que no están a `<= 10 km` del mar (más las 9 de `FORCED_COASTAL_KM`), aplica la Regla del Este **sobre los puertos** (no sobre las ciudades) con fallback al Oeste para que ningún origen se quede sin salida, y persiste las 5 rutas marítimas más cortas de cada puerto en `assets/data/sea_routes.json`.

**Estado actual:** `version 3.1.0`, 42 orígenes (33 por umbral + 9 forzadas), 210 rutas, 262 ciudades descartadas, 29 cruces del antimeridiano, 11257 vértices, ~1,5 s de ejecución.

## Cuándo usar

```bash
pip install -r .opencode/skills/fogg-sea-routes/requirements.txt   # searoute==1.6.0

sea_route.py --dry-run                # todo el catálogo, no escribe
sea_route.py                          # regenera el JSON completo
sea_route.py --resume                 # merge: conserva lo escrito y solo calcula orígenes nuevos
sea_route.py --city "Lisboa" --dry-run  # sólo un origen (el pool sigue siendo completo)
sea_route.py --city "Miami" --resume  # añade rutas de una ciudad concreta sin tocar las demás
sea_route.py --limit 3                # hasta 3 rutas por puerto
sea_route.py --close-gaps             # cierre de huecos de cobertura (SPEC 008)
sea_route.py --out /tmp/prueba.json   # no toca assets/
```

**Por defecto reescribe el fichero entero.** `--resume` cambia a merge: carga las rutas existentes, rellena `heading` en las del esquema 3.0.0 (todas `east`), salta los orígenes ya presentes y solo calcula los nuevos. `meta.generated` refleja la fecha de la última escritura. Si se cambia `THRESHOLD_KM` o `MAX_EAST_DEG`, lo normal es regenerar todo (sin `--resume`).

## Fuentes

- **Primario (offline, sin key):** `assets/data/locations.json` — catálogo canónico `eu.elarreglador.pf`, 304 ciudades `{name, asciiname, lat, lng, timezone}`, orden Este desenrollado.
- **Routing marítimo:** `searoute==1.6.0` — `setup_M()` (malla, 9708 nodos) y `setup_P()` (WPI, 3955 puertos). `searoute([lng,lat],[lng,lat], units="km")` → GeoJSON `Feature`; `properties.length` en km, `geometry.coordinates` en `[lng, lat]`.
- **Destino:** `assets/data/sea_routes.json` — `{meta, routes[]}` (esquema abajo).

## Flujo

1. **Carga** `locations.json` y valida que cada ciudad tenga `name/lat/lng/timezone` numéricos.
2. **Resuelve el puerto de las 304 ciudades** (siempre todas, aunque se filtren orígenes con `--city`, porque el *pool* de destinos debe ser el completo):
   - `sea_snap_km()` enrutado a un punto sonda 0,7° al Este (o al Oeste si el Este pasa de 179°): distancia Haversine ciudad→primer vértice de la malla. Es la medida de "distancia al mar".
   - `> THRESHOLD_KM` (10) → ciudad descartada, se registra con su `seaKm`, **salvo que esté en `FORCED_COASTAL_KM`**: 9 costeras reales (km a la costa con Natural Earth 1:50m, umbral de clasificación 50 km) cuya malla está poco resuelta y cuyo `seaKm` es ficticio (11,8–152,9 km). Sin esa lista no tendrían ninguna ruta de salida y un jugador atrapado en ellas bloquearía la partida.
   - `resolve_port()` con `include_ports=True`: `properties.port_origin` da `{port, name, cty, x, y}` del WPI. El país se humaniza (`French_polynesia` → `French Polynesia`); el código es la clave.
3. **Ordena** los puertos válidos por `port.lng` ascendente (para que el JSON salga en orden Este reproducible).
4. **Selecciona** por puerto origen: primero candidates con `0 < eastward_delta(portOrigin.lng, portDest.lng) <= 180` (`heading: "east"`), ordenados por distancia de círculo grande.
   - **Fallback al Oeste:** si al origen le quedan menos de `MIN_ROUTES_PER_ORIGIN` (2) rutas este, se completan con las más cortas de `-180 <= delta < 0` (`heading: "west"`). Origen > regla del Este.
   - **Poda por cota inferior:** en cuanto la gc del candidato supera la de la 5ª ya seleccionada, se para el bucle. La distancia marítima nunca es menor que la gc, así que es correcto por construcción y verificado idéntico a calcular el top-5 sin podar.
   - `searoute` de ciudad a ciudad con `include_ports=True`; excepción → `SKIP` con `WARN` y sigue.
   - Las 5 más cortas se ordenan por `distanceKm` ascendente.
5. **Normaliza** cada vértice con `normalize_lng()` a `[-180, 180]`. `searoute` entrega el marco desenrollado y se sale del rango (devuelve `lng` hasta `-208.8`); sin esto el visor **rechaza el fichero entero**.
6. **Ancla** la geometría a la ciudad: `anchor_to_cities()` antepone `city_vertex(origen)` y pospone `city_vertex(destino)`. Nunca sustituye, solo añade, y no duplica vértice si la ciudad ya coincide con el nodo vecino. Ver "Geometría de ciudad a ciudad".
7. **Valida** y, si no hay problemas, escribe con `indent=2, ensure_ascii=False` y revalida el JSON.

## Esquema `sea_routes.json` v3.1

```jsonc
{
  "meta": {
    "project": "eu.elarreglador.pf",
    "version": "3.1.0", "generated": "2026-10-07",
    "tool": "fogg-sea-routes", "searoute": "1.6.0",
    "units": "km",                    // obligatorio: lo exige el visor
    "thresholdKm": 10, "maxEastDeg": 180, "limitPerOrigin": 5,
    "minRoutesPerOrigin": 2,          // umbral del fallback al Oeste
    "origins": 42, "routes": 210, "citiesWithoutPort": 262,
    "crossesAntimeridian": 29,        // informativo
    "eastRule": "heading east: 0 < deltaLng(portDest - portOrigin) <= 180 (desenrollado); heading west: -180 <= deltaLng < 0, solo como fallback …",
    "forcedOrigins": "ciudades costeras reales (km a la costa, Natural Earth 1:50m) admitidas pese a superar thresholdKm …: Fakaofo (5.6 km), …",
    "geometry": "LineString [lng,lat] de ciudad a ciudad: …",
    "distanceNote": "distanceKm es properties.length de searoute …",
    "source": "searoute (avoid land) + GeoNames cities15000"
  },
  "routes": [{
    "origin": "Sidney", "originLat": -33.86785, "originLng": 151.20732,
    "destination": "Apia", "destinationLat": -13.8345235, "destinationLng": -171.7630955,
    "distanceKm": 4706.1,
    "heading": "east",                // east|west, coherente con el signo del delta entre puertos
    "portOrigin": { "code": "AUSYD", "name": "Sydney", "country": "Australia",
                    "lat": -33.85, "lng": 151.2, "seaKm": 1.6 },
    "portDest":   { "code": "WSAPW", "name": "Apia", "country": "Samoa",
                    "lat": -13.85, "lng": -171.76, "seaKm": 2.6 },
    "geometry": { "type": "LineString",
                  "coordinates": [[151.20732, -33.86785], …, [-171.76310, -13.83452]] }
  }]
}
```

### Geometría de ciudad a ciudad

`geometry.coordinates[0]` son las coordenadas de `origin` y `[-1]` las de `destination`, ambas redondeadas a `COORD_PRECISION` (5 decimales). `originLat/originLng` conservan la precisión íntegra de `locations.json`, así que la igualdad es a 5 decimales, no byte a byte. `validate_dataset` lo comprueba ruta por ruta.

Entre esos dos extremos va la malla de `searoute` intacta. `searoute` se *pide* ciudad→ciudad, pero *devuelve* la malla: su primer y último vértice son nodos de mar, a 0,4–15,7 km de la ciudad. `anchor_to_cities` los antepone/pospone sin sustituir, de modo que el tramo añadido es una línea recta ciudad→nodo y el camino marino no se recorta.

Consecuencias:

- **+2 vértices por ruta**: 10837 → 11257 (2 × 210; en la práctica no se duplica ninguno, el caso más cerrado es Macau a 0,41 km del nodo).
- **`distanceKm` no cambia**: sigue siendo `properties.length` de `searoute`, la distancia de nodo a nodo. El tramo ciudad→nodo no va incluido, y por eso la suma Haversine de la geometría queda hasta un **1,95 %** por encima de `distanceKm` (muy dentro del ±20 % de `LENGTH_TOLERANCE`).
- **Cruces**: de las 210 rutas, **29 cruzan** el antimeridiano (las 17 previas + 12 de las añadidas en 3.1.0: Leningradsky, Sapporo, Wŏnsan y Manokwari hacia el Pacífico).

### Historial de esquema

`v3` breaking: `geometry` pasa de arrancar en el puerto a arrancar en la ciudad. `v2` ya había sido breaking por añadir `portOrigin`/`portDest` y mover la Regla del Este de las ciudades a los puertos, así que las 9 rutas de `v1.0.1` no son comparables con las actuales. `v3.1` **no es breaking**: añade `heading` por ruta (con backfill a `east` en `--resume`), `meta.minRoutesPerOrigin`/`forcedOrigins` y admite rutas al Oeste como fallback.

## Regla del Este

`0 < deltaLng <= 180` con longitud **desenrollada**: `normalize_lng(b - a)`, de modo que Tokio → San Francisco es legal (cruza el antimeridiano hacia el Este) y Sidney → Lisboa no. Idéntico criterio a `FoggRoute.validated` / `_isEastward` en Dart, pero medido **de puerto a puerto**: con las ciudades, Denver (-104,99) y Ciudad de México (-99,13) quedan casi a la misma longitud, y Denver ganaría a Ciudad de México por 5,8° de diferencia.

**Excepción `heading: "west"` (v3.1):** si un origen no llega a `minRoutesPerOrigin` (2) rutas al Este, se completa con rutas al Oeste (`-180 <= deltaLng < 0`). Prioridad: una ciudad que no puede ser origen deja al jugador bloqueado, así que la Regla del Este cede. `validate_dataset` exige coherencia entre `heading` y el signo del delta; `meta.eastRule` documenta la ampliación. En la corrida de 2026-10-07 el fallback no hizo falta en el mar: las 9 costeras forzadas consiguieron 5 rutas al Este cada una.

## Antimeridiano

`geometry.coordinates` está **siempre en `[-180, 180]`** y una ruta que lo cruza tiene un salto `179 → -179` entre vértices. Segmentar es obligación del consumidor:

- Visor dev: `splitAntimeridian()` (`tools/locations-map/app.js:163`) inserta `[180, lat]` / `[-180, lat]` e interpola la latitud.
- Dart: `FoggRoute.polylineSegments` (`lib/domain/entities/fogg_route.dart:55`) hace lo mismo en Y Mercator.

De las 210 rutas, **29 cruzan** (Sidney, Townsville, Melbourne y Fukuoka hacia el Pacífico, más las 12 nuevas de Leningradsky, Sapporo, Wŏnsan y Manokwari). El salto `179 → -179` se produce dentro del camino marino y `splitAntimeridian` / `polylineSegments` lo segmentan.

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

**Excepción `FORCED_COASTAL_KM` (v3.1):** 9 ciudades que el umbral descarta pero que están a 1,0–15,4 km de la costa real (Natural Earth 1:50m): Fakaofo, Harbour Grace, Leningradsky, Manokwari, Mascate, Miami, Salvador, Sapporo y Wŏnsan. El `seaKm` de malla les da 11,8–152,9 km porque la malla está poco resuelta en su costa — no porque estén en interior. Sin la lista no tendrían origen marítimo (y casi ninguna ruta de salida en general): 9 de las 10 ciudades "solo destino" del catálogo eran justamente estas. No subir `THRESHOLD_KM` para conseguir lo mismo: a 50 km ya entran 112 "puertos" y el mapa se llena de ríos y ciudades del interior.

## Cierre de huecos (SPEC 008, `--close-gaps`)

Pasada posterior al lote normal (no lo sustituye) sobre la unión mar ∪ tierra (`tools/route_coverage.py`); requiere `sea_routes.json` previo con rutas.

- **Salidas:** para cada ciudad sin salida **y con puerto resuelto** (`THRESHOLD_KM` + `FORCED_COASTAL_KM`), `select_routes` con `limit=1` hacia el Este y, si no hay candidatas, hacia el Oeste. Sin puerto → `[WARN] … hueco de salida pendiente` (no aborta).
- **Entradas:** para cada ciudad sin entrada y con puerto, itera las ciudades con puerto por Haversine — primero con capacidad (`< limitPerOrigin` rutas normales; las `gapClosed` no cuentan para el límite) — hasta `MAX_GAP_ROUTE_TRIES = 5`; `searoute` no tiene rate limit (offline), así que el coste es CPU, no red.
- **Meta:** al escribir añade `meta.gapClosedRoutes` y `meta.coverage {cities, withoutOutbound, withoutInbound, exceptions}`.
- **Validación:** `validate_dataset` termina con los problemas de `tools/route_coverage.py` (unión mar ∪ tierra): cualquier ciudad sin salida o sin entrada y sin `excepción` registrada produce `[ERROR]` y no se escribe.

**Regla de excepciones:** `python3 tools/route_coverage.py --write-report` regenera `docs/ciudades-sin-rutas.md` conservando la columna `Decisión` a mano; una ciudad aceptada lleva `excepción — <motivo>`. `python3 tools/route_coverage.py` sale con código 0 cuando no queda ninguna pendiente (código 2 en tanto la haya).

## Límites y riesgos documentados

- **El WPI no sirve como filtro costero.** `include_ports` devuelve 3955 puertos, incluidos fluviales: Denver, Kansas City y Harare están a 0 km de un "puerto" (río Mississippi). El filtro es siempre `sea_snap_km <= THRESHOLD_KM`, nunca `include_ports`.
- **`searoute` entrega longitudes fuera de rango.** El marco desenrollado suma 360 al pasar el antimeridiano (`Denver → Sidney` termina en `-208.817139`). `normalize_lng()` es obligatorio: el visor valida `lng ∈ [-180,180]` en `app.js:136` y lanza `Rutas marítimas inválidas` para *todo* el fichero.
- **Cuidadoso con Haversine.** `sin²(Δλ/2)` es simétrico, así que un Δλ de 356° da el mismo resultado que uno de 4°: no hay que "arreglarlo", pero sí usar `eastward_delta` para no sumar 35.000 km en el salto `179 → -179`.
- **Sondeo de puerto ≠ el puerto de la ruta.** Con el punto sonda 0,7° al Este, Portsmouth resuelve a `GBCOW Cowes` (en la Isla de Wight, ~10 km). Es la respuesta del WPI para la dirección del sondeo, no un error: el `city` manda, `port` documenta.
- **El tramo anclado no es agua.** El primer y el último segmento de la `LineString` unen la ciudad con el nodo de la malla en línea recta, y ese nodo puede no ser el muelle: el peor caso es Portsmouth, 15,7 km hasta Cowes en la Isla de Wight; el más ajustado, Macau, 0,41 km. Del mismo modo, `seaKm` mide el sondeo (≤ 9,6 km) y el enrutado real puede anclar a otro nodo. Con `THRESHOLD_KM = 10` es cosmético, pero si se sube el umbral (ver tabla) este tramo crece con él y hay que revisarlo.
- **`distanceKm` no incluye el tramo anclado.** Es `properties.length` de `searoute` (nodo a nodo). La suma Haversine de la geometría queda hasta un 1,95 % por encima; dentro de `LENGTH_TOLERANCE`, pero no son la misma cifra y no deben tratarse como iguales. Lo declara `meta.distanceNote`.
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
