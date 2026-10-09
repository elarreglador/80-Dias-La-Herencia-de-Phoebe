---
name: fogg-sea-routes-fiction
description: Skill local Python que genera una ruta marítima ficticia bajo demanda entre dos ciudades de locations.json indicadas por el usuario (p. ej. San Juan → Nuakchot). Traza sobre la malla marítima real de searoute con Dijkstra de pesos perturbados de forma determinista por semilla, respeta la curvatura terrestre (Haversine), evita tierra por construcción, restringe el Paso del Noroeste, ancla la geometría a las ciudades y hace merge en assets/data/sea_routes_fiction.json. Exclusiva proyecto eu.elarreglador.pf.
---

# Fogg Sea Routes Fiction — una ruta marítima ficticia bajo demanda

Toma un origen y un destino explícitos, resuelve su puerto con `searoute`, y traza **una única ruta ficticia** que discurre sobre la malla marítima real (evita tierra por construcción) pero con los pesos de las aristas perturbados de forma determinista. El trazado resultante se parece a una ruta real, no es el camino más corto real, y es reproducible con `--seed`.

**Estado actual:** `sea_routes_fiction.json` v1.0.0, integra las 3 rutas de prueba preexistentes (Cartwright→Inverness, Georgetown→Dakar, San Juan→Georgetown, todas `synthetic: true`).

## Cuándo usar

```bash
pip install -r .opencode/skills/fogg-sea-routes-fiction/requirements.txt   # searoute==1.6.0

sea_route_fiction.py --origin "San Juan" --destination "Nuakchot" --dry-run
sea_route_fiction.py --origin "San Juan" --destination "Nuakchot"
sea_route_fiction.py --origin "Lisboa" --destination "Tokio" --seed 7 --detour 1.15
sea_route_fiction.py --origin "Cádiz" --destination "Nuakchot" --verbose
sea_route_fiction.py --origin "San Juan" --destination "Georgetown" --force
```

**Una invocación = una ruta.** `--dry-run` no escribe y muestra distancia, heading, vértices y ratio. `--out` redirige el destino. Si el par ya existe en el fichero, aborta salvo `--force` (que lo reemplaza). El resto de rutas del fichero se conservan: es un merge, no una reescritura.

| Flag | Default | Efecto |
|---|---|---|
| `--origin` / `--destination` | — (obligatorios) | Ciudad por `name` o `asciiname`, coincidencia exacta normalizada (NFD, sin acentos) |
| `--seed` | `80` | Semilla del trazado; otra semilla, otro trazado; la misma, bytes idénticos |
| `--detour` | `1.05` | Ratio objetivo frente al camino más corto real |
| `--rounds` | `16` | Trazados sondeados en la escalera de `beta` |
| `--out` | `assets/data/sea_routes_fiction.json` | Fichero destino |
| `--dry-run` / `--force` / `--verbose` | — | No escribir / reemplazar par / detallar rondas |

## Fuentes

- **Catálogo:** `assets/data/locations.json` — 304 ciudades `{name, asciiname, lat, lng, timezone}` (solo lectura).
- **Malla marítima:** `searoute==1.6.0` — `setup_M()` (9708 nodos, 15970 aristas, peso en km) y `setup_P()` (puertos WPI).
- **Helpers invariantes:** `.opencode/skills/fogg-sea-routes/sea_route.py`, importado vía `importlib` sin ejecutar su CLI. De allí se reutilizan `normalize`, `normalize_lng`, `eastward_delta`, `haversine`, `haversine_sum`, `city_vertex`, `anchor_to_cities`, `crosses_antimeridian`, `load_locations`, `sea_snap_km`, `resolve_port`, `load_searoute` y las constantes (`COORD_PRECISION`, `MAX_DISTANCE_KM`, `LENGTH_TOLERANCE`, `MAX_EAST_DEG`, `THRESHOLD_KM`).
- **Destino:** `assets/data/sea_routes_fiction.json` — `{meta, routes[]}` (esquema abajo).

## Cómo se genera la ficción

1. **Localiza** ambas ciudades por nombre normalizado; si una consulta normaliza igual que varias ciudades, lista candidatas y aborta (no elige por usted).
2. **Resuelve puertos** (`sea_snap_km` + `resolve_port`) para `portOrigin`/`portDest`. Si `seaKm` supera el umbral, avisa pero genera igual: es ficción, no el dataset canónico.
3. **Engancha** las ciudades a sus nodos de malla más cercanos (`M.kdtree.query`) y traza el **camino base** con Dijkstra sobre los pesos reales (pasajes restringidos a `inf`).
4. **Perturba** los pesos: `w' = w · exp(beta · xi)`, con `xi ∈ (-1, 1)` derivado de `blake2b(seed|ronda|arista)`. Recorre una escalera de `beta` de 0,05 a 1,10 en `--rounds` pasos; cada ronda da un trazado distinto, reproducible por semilla e independiente del orden de las aristas.
5. **Elige** el trazado cuyo ratio `distancia / camino_base` se acerca más a `--detour`. Los trazados idénticos al base (ratio < 1,002) se descartan salvo que se pida `--detour ≤ 1`.
6. **Ancla** la geometría a las coordenadas de la ciudad en ambos extremos (`anchor_to_cities`), dobla cada longitud a `[-180, 180]` (`normalize_lng`) descartando vértices consecutivos duplicados (dos nodos vecinos a cada lado del antimeridiano colapsan a `-180`), y calcula `distanceKm = haversine_sum` de toda la polilínea.
7. **Valida** (extremos en ciudad a 5 decimales, `lng/lat` en rango, `distanceKm` vs Haversine ±20 %, `heading` coherente con el delta de puertos) y hace merge ordenado por origen y distancia. Si el conjunto resultante no valida, no escribe nada.

## Curvatura terrestre y realismo

- **Distancias esféricas en todo el cálculo:** los pesos de la malla son Haversine (`searoute.utils.distance`, radio medio) y `distanceKm` es la suma Haversine de la polilínea. No hay trigonometría plana.
- **Evita tierra por construcción:** la malla solo contiene aristas marítimas; ningún camino Dijkstra puede cruzar un continente.
- **Radios de giro realistas:** el trazado es una sucesión de nodos de la malla real, no una recta ni una sinusoide inventada.
- **Paso del Noroeste restringido:** las aristas con ese pasaje se anulan con peso `inf`, igual que en `sea_routes.json`.
- **Desvío acotado:** `--detour` mantiene la ruta cerca del camino real (default 5 %); ratios muy altos producen trazados largos pero legítimos.
- **Realismo declarado:** `meta.fictional: true` y `synthetic: true` por ruta evitan confundirla con el dataset canónico.

## Esquema `sea_routes_fiction.json` v1.0.0

```jsonc
{
  "meta": {
    "project": "eu.elarreglador.pf",
    "name": "sea_routes_fiction", "version": "1.0.0",
    "generated": "2026-10-08", "tool": "fogg-sea-routes-fiction",
    "searoute": "1.6.0", "units": "km", "fictional": true,
    "algorithm": "Dijkstra con pesos perturbados w * exp(beta * xi) …",
    "seed": 80, "detourTarget": 1.05, "maxEastDeg": 180,
    "routes": 4, "crossesAntimeridian": 0,
    "eastRule": "heading east: 0 < deltaLng <= 180 (desenrollado); west: -180 <= deltaLng < 0 (par explícito)",
    "geometry": "LineString [lng,lat] de ciudad a ciudad; malla real en medio; [-180,180]",
    "distanceNote": "distanceKm = suma Haversine de toda la polilínea, incluidos los tramos anclados",
    "source": "searoute (malla real, avoid land) + GeoNames cities15000; geometría ficticia"
  },
  "routes": [{
    "origin": "San Juan", "originLat": 18.46633, "originLng": -66.10572,
    "destination": "Nuakchot", "destinationLat": 18.08581, "destinationLng": -15.9785,
    "distanceKm": 5732.0,
    "heading": "east",
    "portOrigin": {"code": "PRSJU", "name": "San Juan", "country": "Puerto rico",
                   "lat": 18.45753, "lng": -66.20911, "seaKm": 2.3},
    "portDest":   {"code": "MRNKC", "name": "Nouakchott", "country": "Mauritania",
                   "lat": 18.04378, "lng": -16.00037, "seaKm": 19.1},
    "geometry": {"type": "LineString", "coordinates": [[-66.10572, 18.46633], "…"]},
    "synthetic": true,
    "syntheticSeed": 80,       // semilla que produjo este trazado
    "detourRatio": 1.0462,     // distancia / camino más corto real
    "detourBaseKm": 5478.9     // longitud Haversine del camino más corto real
  }]
}
```

Los campos `synthetic`/`syntheticSeed`/`detourRatio`/`detourBaseKm` son metadatos; el validador del visor los ignora. `originLat/originLng` conservan la precisión íntegra de `locations.json`; los vértices van a `COORD_PRECISION` (5 decimales).

## Regla del Este y antimeridiano

- **Regla del Este:** el `heading` se deriva del signo de `eastward_delta(portOrigin.lng, portDest.lng)`, desenrollado. A diferencia del dataset real, aquí el par lo elige el usuario, así que un par hacia el Oeste **no se rechaza**: se emite `[WARN]` y se escribe con `heading: "west"`.
- **Antimeridiano:** `coordinates` está siempre en `[-180, 180]`; al cruzar, los vértices saltan de 179 a -179 y el consumidor debe segmentar (`splitAntimeridian` en el visor, `FoggRoute.polylineSegments` en Dart). `meta.crossesAntimeridian` lo cuenta. Medido: Tokio → San Francisco cruza y sale con 65 vértices.

## Límites y riesgos

- **Acoplamiento entre skills:** importa helpers de `fogg-sea-routes/sea_route.py` vía `importlib`. Si esa skill se renombra o cambia de firma, esta falla al cargar (error explícito). Es deliberado: una sola definición de la Regla del Este y del formato de vértice.
- **No es navegabilidad real:** el trazado es plausible sobre la malla, no una derrota náutica. Nunca debe tratarse como el dataset canónico: para eso está `sea_routes.json`.
- **Tramo anclado no es agua:** el primer y último segmento unen la ciudad con el nodo de malla en línea recta, como en el dataset real. Es cosmético con ciudades costeras.
- **Ciudades de interior:** se generan igual (aviso), pero el tramo ciudad→malla puede ser largo; el ratio de desvío puede verse inflado por ese tramo, no por el camino marino.
- **`--detour` es un objetivo, no una garantía:** se elige el candidato más cercano de los `--rounds` sondeados. Suba `--rounds` si quiere más variedad; cambie `--seed` para otro conjunto de candidatos.
- **Sin consumidor Dart todavía:** el único consumidor vivo es el visor dev (botón/drag&drop de rutas marítimas, validador `validateRoutes`). `TransportMode.ship` aún no lo lee.
- **Fichero versionado por merge:** cada invocación añade una ruta y reescribe `meta.generated`; revise el diff antes de commitear.

## Archivos del proyecto

- `assets/data/locations.json` → catálogo solo lectura.
- `assets/data/sea_routes_fiction.json` → artefacto derivado, merge por esta skill.
- `.opencode/skills/fogg-sea-routes-fiction/sea_route_fiction.py` → CLI principal.
- `.opencode/skills/fogg-sea-routes-fiction/requirements.txt` → `searoute==1.6.0`.
- `.opencode/skills/fogg-sea-routes/sea_route.py` → helpers invariantes reutilizados.
- `tools/locations-map/app.js` → visor dev: valida el JSON y segmenta el antimeridiano.
- `lib/domain/entities/fogg_route.dart` → invariante espejada (`validated`, `polylineSegments`).
