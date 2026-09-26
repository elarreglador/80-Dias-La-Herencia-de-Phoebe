# SPEC 004 — Skill local de rutas marítimas con searoute (5 rutas Este más cortas)

> **Estado:** Aprobado
> **Depende de:** `assets/data/locations.json` (ordenado Este, 304 ciudades, GeoNames CC-BY 4.0), `fogg-city-enricher` (Regla del Este desenrollada), `TODO.md:28` (trazado GeoJSON real)
> **Fecha:** 2026-09-25
> **Objetivo:** Proveer una skill local Python que, dada una ciudad origen, recorra `locations.json` hacia el Este, descarte ciudades sin puerto (<10 km vía `searoute`), calcule las 5 rutas marítimas más cortas y las guarde en `assets/data/sea_routes.json` en km.

---

## 1. Alcance

**En:**

- **Calcula 5 rutas marítimas más cortas hacia el Este — `.opencode/skills/fogg-sea-routes/sea_route.py` — invoca `searoute` y guarda polilíneas en `sea_routes.json`** — recorre `locations.json` desde índice origen hacia el Este desenrollado, filtra ciudades con puerto <10 km, ordena por distancia marítima y persiste las 5 más cortas
  - [ ] ¿Lo entendería un junior sin ver la maqueta? [ ] ¿Empieza por verbo + objeto que ve el usuario? [ ] ¿Menciona ruta/archivo y efecto sin jerga?
- **Detecta puerto marítimo cercano con searoute — `.opencode/skills/fogg-sea-routes/sea_route.py:resolvePort` — valida snap <10 km Haversine antes de enrutar** — llama `searoute.searoute([lng,lat], [lng,lat], units="km")` y mide distancia Haversine ciudad→primer vértice y ciudad destino→último vértice; si >10 km descarta ciudad como inland
  - [ ] ¿Lo entendería un junior sin ver la maqueta? [ ] ¿Empieza por verbo + objeto que ve el usuario? [ ] ¿Menciona ruta/archivo y efecto sin jerga?
- **Persiste rutas como GeoJSON LineString — `assets/data/sea_routes.json` — merge idempotente por clave origen::destino** — guarda `{meta, routes:[{origin,destination,lat,lng,distanceKm,geometry}]}` asumiendo puerto en misma ciudad (mismo `name`/`lat`/`lng`), sin objeto `port` anidado
  - [ ] ¿Lo entendería un junior sin ver la maqueta? [ ] ¿Empieza por verbo + objeto que ve el usuario? [ ] ¿Menciona ruta/archivo y efecto sin jerga?
- **Expone CLI con dry-run y validación — `.opencode/skills/fogg-sea-routes/sea_route.py --city --dry-run` — lista candidatos sin escribir disco** — argumentos `--city "Londres" [--limit 5] [--dry-run] [--force]`, normaliza NFD case-insensitive, valida existencia en `locations.json`
  - [ ] ¿Lo entendería un junior sin ver la maqueta? [ ] ¿Empieza por verbo + objeto que ve el usuario? [ ] ¿Menciona ruta/archivo y efecto sin jerga?
- **Documenta uso y dependencias — `.opencode/skills/fogg-sea-routes/SKILL.md + requirements.txt` — instala `searoute==1.6.0` y describe flujo Este** — `SKILL.md` con cuándo usar, fuentes, flujo, ejemplos; `requirements.txt` fija `searoute==1.6.0` (y `shapely` transitiva)
  - [ ] ¿Lo entendería un junior sin ver la maqueta? [ ] ¿Empieza por verbo + objeto que ve el usuario? [ ] ¿Menciona ruta/archivo y efecto sin jerga?

**Compartido:** respeta `Package by Layer`, prefijo `eu.elarreglador.pf` intacto, `assets/data/locations.json` no mutado, `searoute` offline sin key, `flutter analyze` verde (skill Python fuera de `lib/`).

**Fuera del alcance (para futuras especificaciones):**

- Batch global que genere rutas para las 304 ciudades sin `--city` (merece spec de orquestación y caché).
- Dataset externo de puertos (WPI, Natural Earth `ports.json` o Overpass `seamark:harbour`) — esta spec delega la detección a `searoute` + umbral 10 km, sin empaquetar puertos.
- UI Flutter que renderice `sea_routes.json` sobre `flutter_map` (`PolylineLayer` marítimo, `TransportMode.ship`) — otra spec `presentation/`.
- Cálculo de duración/ETA, costes `BudgetService` o `Ledger` por milla náutica.
- Validación DST/`TimezoneService` o `package:timezone` en la skill.
- Edición manual de `sea_routes.json` o persistencia en `Hive`/`Supabase`.

---

## 2. Modelo de datos

Esta especificación **introduce un nuevo JSON persistido** y reutiliza `locations.json` como fuente de verdad solo lectura.

### 2.1 `assets/data/locations.json` (solo lectura, ya existente)

```json
{
  "meta": { "project": "eu.elarreglador.pf", "version": "1.0.1", "update": "2026-09-25" },
  "cities": [
    { "name": "Londres", "asciiname": "London", "lat": 51.50853, "lng": -0.12574, "timezone": "Europe/London" },
    { "name": "Genova", "asciiname": "Genoa", "lat": 44.40478, "lng": 8.94439, "timezone": "Europe/Rome" }
  ]
}
```

- Orden canónico **Este creciente por `lng` con desenrollado** (`offset+=360` si `currUnwrapped <= prevUnwrapped`), idéntico a `fogg-city-enricher` y `lib/domain/entities/fogg_route.dart:_isEastward`. El índice de `--city` determina el inicio del recorrido.
- Normalización para búsqueda: NFD, `casefold`, sobre `name|asciiname|alternatenames` (si futuro).

### 2.2 `assets/data/sea_routes.json` (nuevo, persistido)

```json
{
  "meta": {
    "project": "eu.elarreglador.pf",
    "name": "Fogg Sea Routes — Herencia de Phoebe",
    "version": "1.0.0",
    "generated": "2026-09-25",
    "tool": "fogg-sea-routes",
    "searoute": "1.6.0",
    "units": "km",
    "thresholdKm": 10,
    "source": "searoute (avoid land) + GeoNames cities15000"
  },
  "routes": [
    {
      "origin": "Londres",
      "originLat": 51.50853,
      "originLng": -0.12574,
      "destination": "Genova",
      "destinationLat": 44.40478,
      "destinationLng": 8.94439,
      "distanceKm": 3421.7,
      "geometry": {
        "type": "LineString",
        "coordinates": [[-0.12, 51.5], [0.5, 50.8], [8.9, 44.4]]
      }
    }
  ]
}
```

Convenciones:

- **Puerto = misma ciudad** (acuerdo punto 4): no hay `portName`/`portLat`; `origin`/`destination` son ciudades de `locations.json` con puerto implícito. Si `searoute` hace snap al mar, esa distancia snap se valida <10 km pero no se persiste como entidad separada.
- `distanceKm` = `properties.length` de `searoute` con `units="km"` (float, 1 decimal). Sin `durationHours` en MVP (searoute no estima tiempo sin velocidad).
- `geometry.coordinates` = array `[lng,lat]` GeoJSON (orden GeoJSON, no Leaflet `[lat,lng]`). Puede cruzar antimeridiano; no se segmenta en esta spec (consumidor Flutter hará `polylineSegments` si necesita).
- **Merge idempotente:** clave `origin::destination` (case-sensitive `name` canónico). Ejecución repetida con misma `--city` reemplaza rutas de esa clave, preserva otras.
- `meta.generated` ISO `YYYY-MM-DD`, `meta.version` bump `1.0.0→1.0.1` si cambia contenido.

### 2.3 Estructuras efímeras en `sea_route.py` (no persistidas)

```python
# Candidato evaluado en memoria
candidate = {
  "city": {"name": "Genova", "lat": 44.40478, "lng": 8.94439},
  "distanceKm": 3421.7,          # searoute properties.length
  "geometry": {"type": "LineString", "coordinates": [...]},
  "snapOriginKm": 2.3,           # Haversine ciudad→coords[0]
  "snapDestKm": 1.1,             # Haversine ciudad→coords[-1]
}

# Estado CLI
args = {"city": "Londres", "limit": 5, "dry_run": False, "force": False}
```

- `snap*Km` solo para filtro 10 km y log; no se persiste.
- Sin `SENSIBLE/.cache` en MVP (YAGNI); idempotencia vía `sea_routes.json` es suficiente.

---

## 3. Plan de implementación

Cada paso deja el repo ejecutable, `sea_routes.json` válido si existe, y `flutter analyze` verde (skill Python fuera de `lib/`).

1. **Crea esqueleto de la skill** — `mkdir -p .opencode/skills/fogg-sea-routes`, `SKILL.md` con `name/description/cuándo usar/fuentes/flujo/rate-limit/ejemplos`, `requirements.txt` con `searoute==1.6.0`, `sea_route.py` con `argparse --city --limit 5 --dry-run --force` y `load_locations()` que valida `cities` y resuelve índice origen con normalización NFD + desenrollado `offset+=360`. Prueba: `python3 sea_route.py --help` imprime uso sin error.

2. **Implementa recorrido Este y filtro 10 km** — `find_candidates(originIdx)` itera `i=originIdx+1 .. len(cities)-1` (sin wrap en MVP; wrap opcional tras `Leningradsky→Suva` si se pide), para cada `dest` invoca `searoute.searoute([lngOri,latOri],[lngDest,latDest], units="km")`, calcula `haversine(city, coords[0])` y `haversine(city, coords[-1])`, si alguno >10 km log `SKIP inland` y continúa; si `searoute` lanza excepción (puntos en tierra sin ruta) también `SKIP`. Prueba: `python --city "Londres" --dry-run` lista 5+ candidatos Este con `OK`/`SKIP`.

3. **Selecciona 5 rutas más cortas y formatea GeoJSON** — acumula `candidates` válidos, ordena por `distanceKm` ascendente, toma `limit=5`, construye `route` con `origin/destination/lat/lng/distanceKm/geometry`. Prueba: `Londres` → 5 destinos costeros Este (`Genova`, `Roma`... si tienen puerto) con distancias crecientes.

4. **Implementa merge idempotente en sea_routes.json** — `load_or_init_sea_routes()` lee `assets/data/sea_routes.json` si existe o crea `{"meta":..., "routes":[]}`, `merge_routes(newRoutes)` reemplaza por clave `origin::destination` o hace `append`, actualiza `meta.generated` a hoy y `meta.version` si hubo cambio, escribe `json.dump(indent=2, ensure_ascii=False)`. Prueba: dos ejecuciones idénticas no duplican rutas; `--force` sobrescribe.

5. **Añade validación y logging** — valida `0 < distanceKm < 40000`, `coordinates.length >=2`, `lng∈[-180,180] lat∈[-90,90]`, `distanceKm` coincide con suma Haversine segmentos ±20%; log `INFO` por ruta y `WARN` si `searoute` devuelve `FeatureCollection` vacío. Prueba: `cat sea_routes.json | python -m json.tool` sin `Traceback`.

6. **Documenta y verifica calidad** — completa `SKILL.md` con ejemplos `sea_route.py --city "Londres"` y ` --dry-run`, añade `README.md:Configuración` breve referencia si aplica, ejecuta `pip install -r requirements.txt && python sea_route.py --city "Londres" --dry-run`, `python -m json.tool assets/data/sea_routes.json`, `flutter analyze` verde, diff sin secretos. Marca `TODO.md:28` parcial si corresponde.

---

## 4. Criterios de aceptación

- [ ] `.opencode/skills/fogg-sea-routes/SKILL.md` existe y describe `name: fogg-sea-routes`, `cuándo usar --city`, `fuentes searoute 1.6.0`, `flujo Este desenrollado + 10 km`, ejemplos `--city "Londres"` y `--dry-run`.
- [ ] `.opencode/skills/fogg-sea-routes/requirements.txt` fija `searoute==1.6.0` y `pip install -r requirements.txt` completa sin `ModuleNotFoundError`.
- [ ] `python3 .opencode/skills/fogg-sea-routes/sea_route.py --city "Londres" --dry-run` lista candidatos Este con `OK`/`SKIP inland (>10km)` y no escribe `sea_routes.json`.
- [ ] `python3 .opencode/skills/fogg-sea-routes/sea_route.py --city "Londres"` genera/mergea `assets/data/sea_routes.json` con `meta.units=="km"`, `meta.thresholdKm==10`, `meta.searoute=="1.6.0"` y exactamente 5 rutas cuando hay ≥5 ciudades costeras hacia el Este.
- [ ] Cada `routes[]` contiene `origin/destination` (nombres canónicos de `locations.json`), `originLat/originLng/destinationLat/destinationLng` numéricos, `distanceKm` float >0 y `geometry.type=="LineString"` con `coordinates` `[lng,lat]` longitud ≥2.
- [ ] Recorrido respeta Este desenrollado: todo `destination` tiene `lng_u > origin_lng_u` (con `offset+=360` si cruza antimeridiano `Leningradsky 178 → Suva 178 → Egvekinot -179`), nunca incluye destino al Oeste del origen.
- [ ] Ciudades sin puerto se descartan: `Niamey` (Níger interior) invocada como destino desde `Londres` aparece como `SKIP inland` y no genera ruta; la skill continúa hasta reunir 5 o agotar catálogo sin `exit 1` salvo origen inexistente.
- [ ] Ejecución idempotente: dos corridas ` --city "Londres"` no duplican `routes` con misma clave `Londres::Genova`; segunda corrida reemplaza `distanceKm/geometry` y actualiza `meta.generated`.
- [ ] `sea_routes.json` es JSON válido (`python3 -m json.tool` sin error), `routes` ordenadas por `distanceKm` ascendente, ninguna ruta duplica `origin==destination`.
- [ ] `flutter analyze` verde y `git diff` sin secretos, sin `SENSIBLE/` versionado, sin tocar `pubspec.yaml` ni `lib/domain`.
- [ ] Rama `spec-01-fogg-sea-routes` contiene solo cambios de esta spec (`SKILL.md`, `sea_route.py`, `requirements.txt`, `sea_routes.json` si generado en `--force` de ejemplo) y el archivo de spec `specs/01-fogg-sea-routes.md` en estado `Borrador`.

---

## 5. Decisiones tomadas y descartadas

- **Sí:** `searoute==1.6.0` Python como única fuente de puerto+ruta, con validación Haversine snap <10 km en `sea_route.py`. Por qué: cumple su requisito textual *"searoute buscará el puerto más cercano"* sin empaquetar dataset externo, offline (cache de tiles marítimos en lib), sin key, sin rate-limit. No: empaquetar `WPI NaturalEarth ports.json (~3k)` — descartado porque duplica lógica que `searoute` ya resuelve y obligaría a mantener `ports.json` versionado y a elegir criterio de puerto (comercial vs pesquero). No: Overpass `seamark:harbour` — descartado por requerir red, `sleep 1` y `429 backoff`, frágil en CI y no determinista.
- **Sí:** Umbral fijo 10 km (no parametrizable en MVP) medido Haversine ciudad→primer vértice `searoute`. Por qué: su punto 3 explícito, equilibra ciudades costeras (Genova 2 km) vs interiores (Niamey 450 km al mar) sin falsos positivos; 10 km cubre delta puerto-ciudad pero no cuencas interiores. No: 50 km — descartado por incluir `París` (150 km a Le Havre) como falso puerto y generar rutas tierra-mar irreales. No: 1 km — descartado por descartar puertos reales con `city` geo-centro desplazado (ej. `Bombay` centro a 3 km de muelle).
- **Sí:** Puerto = misma ciudad (mismo `name`/`lat`/`lng`), sin entidad `port` anidada. Por qué: su punto 4 *"asumiremos que el puerto está en la misma ciudad y tiene el mismo nombre para no complicar el json"* — simplifica `sea_routes.json` y evita `portName/portLat` que el consumidor Flutter no necesita en MVP. No: objeto `originPort{name,lat,lng,distanceKm}` — descartado para esta spec, se reintroducirá si `BudgetService` necesita `portTax` diferenciado.
- **Sí:** Recorrido lineal Este desde índice origen en `locations.json` ordenado por `lng` (desenrollado `offset+=360`) y selección de 5 rutas más cortas por `distanceKm`. Por qué: satisface punto 1 *"recorrer el archivo desde la ciudad origen hasta obtener los 5 puertos más cercanos"* + punto 5 *"nos quedaremos con las 5 rutas más cortas"* — primero acumula candidatos válidos hacia el Este, luego ordena por distancia marítima (no por Haversine previo), optimiza costa vs interior. No: tomar los 5 primeros candidatos en orden de catálogo sin ordenar por distancia — descartado por priorizar `Bruselas (inland skip)` sobre `Genova` más lejano en catálogo pero más barato por mar. No: evaluar todas las 304 ciudades como batch global — descartado, merece spec orquestadora.
- **Sí:** Unidades fijas `km` (`units="km"` en `searoute` y `meta.units`), sin flag `--units`. Por qué: punto 7 explícito, evita divergencia `nm` vs `km` en `BudgetService` futuro y mantiene `sea_routes.json` comparable. No: `--units km|nm` parametrizable — descartado YAGNI, se añade si `Ledger` requiere millas náuticas.
- **Sí:** CLI con `--city` requerido + `--dry-run` + `--limit 5` default + `--force`. Por qué: KISS, idempotente, permite validar sin escribir disco (como `enrich.py --dry-run`), `--force` fuerza re-cálculo aunque `sea_routes.json` exista. No: `--origin/--destination` pareja fija — descartado porque su punto 1 pide descubrimiento de 5 destinos Este, no ruta 1:1 prefijada.
- **Sí:** Merge idempotente por clave `origin::destination` con `meta.generated` bump, sin `SENSIBLE/.cache`. Por qué: sin caché extra, `sea_routes.json` es la caché; re-ejecución corrige rutas si `searoute` actualiza malla marítima. No: `SENSIBLE/.cache/sea_routes.json` separado — descartado por duplicar fuente de verdad.

---

## 6. Riesgos identificados

| Riesgo | Mitigación |
| --- | --- |
| `searoute` hace snap a mar pero devuelve `Feature` con `coordinates` que aún dista >10 km en ciudades estuarinas (ej. `Londres` Támesis) y se descarta como inland falso negativo | Medir snap Haversine a primer vértice y loggear `distance`; si sistemáticamente >10 km para puertos fluviales, documentar en `SKILL.md` y considerar subir umbral a 15 km en revisión sin romper spec (cambio solo de constante). |
| `searoute` lanza excepción si origen/destino en tierra profunda sin costa cercana (ej. `Niamey→Kano`) | `try/except` por candidata, `SKIP` con `WARN`, no aborta batch; batch solo falla si origen inexistente o 0 rutas encontradas (exit 1 con mensaje). |
| Antimeridiano `Leningradsky 178 → Egvekinot -179` produce `LineString` que cruza `180→-180` y `flutter_map` dibuja línea parásita | Documentar que `geometry.coordinates` conserva `lng` en `[-180,180]` con salto; consumidor Flutter debe usar `polylineSegments` (como `FoggRoute`) — fuera de esta spec, pero `SKILL.md` lo advierte. |
| Catálogo contiene ciudades costeras pero `searoute` no encuentra ruta (estrecho bloqueado, canal sin malla) | Considerar `SKIP` y continuar; si <5 rutas halladas desde origen, guardar las halladas y log `WARN "only N routes"` sin inventar rutas. |
| `searoute` depende de `shapely`/`geos` nativo y `pip install` falla en Windows sin `Wheel` | Fijar `searoute==1.6.0` que publica `wheel` manylinux, documentar `pip install --only-binary=shapely`; CI usa `ubuntu-latest`. |
| Ejecución repetida sin `--force` produce `sea_routes.json` con `meta.version` sin bump si contenido idéntico | Comparar `routes` antes/después con `json.dumps(sort_keys=True)` y solo bump `meta.version` si hay cambio real. |
| Usuario espera rutas para ciudad interior origen (ej. `Niamey`) | Si origen mismo es inland (`snapOrigin>10km`), aborta con `exit 1 "origin has no port within 10km"` y lista 3 sugerencias de ciudades costeras Este cercanas. |

---

## 7. Lo que **no** está en esta especificación

- Generación batch de rutas para las 304 ciudades ni malla completa Este-Oeste (otra spec orquestadora con caché y paralelismo).
- Empaquetado de `ports.json` externo o consulta Overpass/Nominatim (esta spec delega a `searoute`).
- Renderizado `PolylineLayer` marítimo en `flutter_map` ni `TransportMode.ship`/`sleeper` (spec `presentation/`).
- Estimación `durationHours`/coste `BudgetService` por ruta.
- Validación IANA `timezone` con `package:timezone`.
- Persistencia `Hive`/`Supabase` de rutas.

> Cada uno, si aterriza, irá en su propia spec.

---

## 8. Referencias

- `assets/data/locations.json:1` — catálogo canónico (304 ciudades, `version 1.0.1`, ordenado Este `lng` creciente)
- `AGENTS.md:40` — Regla del Este `destination.lng > current.lng`, Sin avión, Ciclo Fogg Phoebe
- `.opencode/skills/fogg-city-enricher/SKILL.md` — patrón offline + normalización NFD + desenrollado `offset+=360`
- `lib/domain/entities/fogg_route.dart:_isEastward` — invariante desenrollado a espejar
- `searoute` PyPI `1.6.0` — `searoute.searoute(origin, destination, units="km") → GeoJSON Feature LineString` (avoid land, sin key)
- `TODO.md:28` — trazado GeoJSON real (OpenRailwayMap + rutas marítimas)

---

## 9. Preguntas abiertas (resueltas por esta spec)

- Recorrido Este desde índice origen con desenrollado ✅
- Detección puerto <10 km vía `searoute` snap Haversine ✅ — inland se descarta
- Puerto = misma ciudad, sin entidad `port` ✅
- 5 rutas más cortas por `distanceKm` ✅
- Unidades km fijas ✅
- Merge idempotente `origin::destination` ✅
- Rama `spec-01-fogg-sea-routes` ✅ — no tocar `main` hasta aprobación

> Siguiente paso tras aprobar esta spec: ejecutar `/spec-impl 01-fogg-sea-routes` (pasos §3) con validación `json.tool` + `flutter analyze` verde.

---

## 10. Addendum 2026-09-26 — geometría de ciudad a ciudad (esquema 3.0.0)

El cuerpo de esta spec describe el diseño `v1` (puerto implícito, merge idempotente) y queda **superado** en cuatro aspectos por el estado real del artefacto. Este addendum registra el delta; no reescribe §2.

| Aspecto | `v1` (§2.2) | Actual `v3.0.0` | Delta |
|---|---|---|---|
| Puerto | implícito, misma ciudad | `portOrigin`/`portDest` explícitos (WPI: código, nombre, país, lat/lng, `seaKm`) | `v2` |
| Regla del Este | sobre la ciudad | sobre el **puerto** (desenrollada) | `v2` |
| Escritura | merge idempotente por `origin::destination` | reescritura completa, sin merge | `v2` |
| `geometry.coordinates[0]` / `[-1]` | nodo de la malla `searoute` | **coordenadas de la ciudad**, redondeadas a 5 decimales | `v3` (este addendum) |

Motivo del último punto: `searoute` se *pide* ciudad→ciudad pero *devuelve* la malla marítima, así que la polilínea arrancaba en un nodo de mar a hasta 15,7 km del centro de la ciudad (Portsmouth → Cowes). `anchor_to_cities()` antepone y pospone las coordenadas de `locations.json` **sin sustituir** los vértices de la malla, de modo que el camino marino queda intacto y la línea empieza y acaba en la ciudad que espera el consumidor.

Consecuencias asumidas: `distanceKm` sigue siendo `properties.length` de `searoute` (nodo a nodo) y **no** incluye los dos tramos añadidos — la suma Haversine de la geometría queda hasta un 1,95 % por encima, dentro del ±20 % que ya toleraba §2.2. `validate_dataset` incorpora la invariante de extremos. Detalle operativo en `.opencode/skills/fogg-sea-routes/SKILL.md`.

