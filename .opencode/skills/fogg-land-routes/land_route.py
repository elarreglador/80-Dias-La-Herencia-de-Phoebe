#!/usr/bin/env python3
"""
fogg-land-routes — hasta 5 rutas por carretera hacia el Este por ciudad
Proyecto eu.elarreglador.pf

- Para cada ciudad de locations.json toma sus 5 vecinas más próximas por
  círculo grande que cumplan la Regla del Este (0 < deltaLng <= 180) y
  consulta al servidor demo de OSRM cuáles tienen camino por carretera.
- Si al origen le quedan menos de MIN_ROUTES_PER_ORIGIN rutas este, se
  completa con el pool oeste (5 vecinas hacia el Oeste, -180 <= deltaLng < 0):
  un jugador atrapado en una ciudad sin salida bloquearía la partida, así que
  la Regla del Este cede ante la jugabilidad. Cada ruta lleva `heading`.
- Respeta la política del servidor: como mucho 1 petición por segundo
  (pausa de 1,2 s), User-Agent identificable y backoff ante 429.
- Ancla cada geometría a las coordenadas de la ciudad en ambos extremos:
  OSRM devuelve el punto enganchado a la calzada, no el centro urbano.
- Selecciona como mucho `limit` rutas por origen y persiste
  assets/data/car_routes.json (reescritura completa; con --resume hace merge:
  conserva las rutas ya escritas y solo calcula los orígenes que falten).

Uso:
  python3 .opencode/skills/fogg-land-routes/land_route.py --dry-run
  python3 .opencode/skills/fogg-land-routes/land_route.py
  python3 .opencode/skills/fogg-land-routes/land_route.py --city "Lisboa" --dry-run
  python3 .opencode/skills/fogg-land-routes/land_route.py --only 20
  python3 .opencode/skills/fogg-land-routes/land_route.py --resume
  python3 .opencode/skills/fogg-land-routes/land_route.py --close-gaps
  python3 .opencode/skills/fogg-land-routes/land_route.py --out /tmp/prueba.json

Stdlib puro, sin pip install.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
import sys
import time
import unicodedata
import urllib.error
import urllib.request
from datetime import date
from pathlib import Path
from typing import Any

# ---------------------------------------------------------------------------
# Rutas y constantes
# ---------------------------------------------------------------------------
PROJECT_ROOT = Path(__file__).resolve().parents[3]  # PF/
JSON_PATH = PROJECT_ROOT / "assets" / "data" / "locations.json"
CAR_ROUTES_PATH = PROJECT_ROOT / "assets" / "data" / "car_routes.json"
CACHE_ROOT = PROJECT_ROOT / "SENSIBLE" / ".cache" / "fogg-land-routes"

# Cobertura de rutas (SPEC 008): módulo único compartido con fogg-sea-routes.
sys.path.insert(0, str(PROJECT_ROOT / "tools"))
import route_coverage  # noqa: E402  # type: ignore[import-not-found]

PROJECT = "eu.elarreglador.pf"
TOOL_NAME = "fogg-land-routes"
SCHEMA_VERSION = "1.1.0"
OSRM_SERVER = "https://router.project-osrm.org"
OSRM_WEIGHT_NAME = "routability"
USER_AGENT = "eu.elarreglador.pf/1.0"

MAX_EAST_DEG = 180  # tope del salto Este, evita la vuelta al mundo por el Oeste
DEFAULT_LIMIT = 5
DEFAULT_POOL = 5
MIN_ROUTES_PER_ORIGIN = 2  # mínimo de rutas de salida; por debajo se recurre al Oeste
MAX_DISTANCE_KM = 40000
LENGTH_TOLERANCE = 0.25  # |haversine_sum - distanceKm| / distanceKm
                     # 0,20 era demasiado estricto: el `simplified` recorta
                     # hasta un 22,7 % en alta montaña (Nizhneyansk→Magadán,
                     # verificado contra overview=full: ±0,3 %, o sea la
                     # distancia OSRM es real y la que pierde es la
                     # polilínea). Las rutas fantasma siguen cayendo: desvían
                     # cientos % por el lado positivo.
COORD_PRECISION = 5  # ~1 m, suficiente para visualizar
MIN_INTERVAL_S = 1.2  # cortesía: como mucho 1 petición por segundo
REQUEST_TIMEOUT_S = 60
RETRY_DELAYS = (5, 15, 45)  # backoff ante 429
SNAP_WARN_KM = 1.0  # avisa si el enganche queda lejos del centro
SNAP_MAX_KM = 50.0  # por encima el enganche no es la ciudad: OSRM cruzó el
                    # mar hasta otra costa (p. ej. Lampedusa) y la ruta es un
                    # fantasma; se descarta como NoSegment para que la
                     # validación ±25 % no caiga por el tramo ancla.
GAP_POOL = 25  # candidatas por hueco de cierre (SPEC 008): 1 /table con
               # pool este + pool oeste y como mucho 1 /route por hueco
MAX_GAP_ROUTE_TRIES = 5  # /route por hueco de entrada: el primer candidato
                         # suele ser isla o par sin enganche rodado

# Estado del cliente OSRM (cortesía + versión de datos).
_last_request_ts = 0.0
_osrm_data_version: str | None = None


# ---------------------------------------------------------------------------
# Helpers geodésicos (mismo modelo que sea_route.py)
# ---------------------------------------------------------------------------

def normalize(s: str) -> str:
    """NFD, lower, strip, sin acentos."""
    if not s:
        return ""
    nfkd = unicodedata.normalize("NFKD", s)
    stripped = "".join(c for c in nfkd if not unicodedata.combining(c))
    return stripped.lower().strip()


def normalize_lng(lng: float) -> float:
    """Dobla una longitud a [-180, 180]."""
    return (lng + 180.0) % 360.0 - 180.0


def eastward_delta(lng_from: float, lng_to: float) -> float:
    """Desplazamiento Este de `lng_from` a `lng_to`, en (-180, 180]."""
    return normalize_lng(lng_to - lng_from)


def haversine(lat1: float, lng1: float, lat2: float, lng2: float) -> float:
    """Distancia Haversine en km entre dos puntos [lat, lng]."""
    R = 6371.0088
    phi1, phi2 = math.radians(lat1), math.radians(lat2)
    dphi = math.radians(lat2 - lat1)
    dlambda = math.radians(eastward_delta(lng1, lng2))
    a = math.sin(dphi / 2) ** 2 + math.cos(phi1) * math.cos(phi2) * math.sin(dlambda / 2) ** 2
    c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))
    return R * c


def haversine_sum(coordinates) -> float:
    """Suma Haversine de segmentos GeoJSON [lng, lat], con longitud ya normalizada."""
    total = 0.0
    for i in range(len(coordinates) - 1):
        lng1, lat1 = coordinates[i]
        lng2, lat2 = coordinates[i + 1]
        total += haversine(lat1, lng1, lat2, lng2)
    return total


# ---------------------------------------------------------------------------
# Catálogo de ciudades
# ---------------------------------------------------------------------------

def load_locations():
    """Carga locations.json, valida y calcula lng_u desenrollado."""
    if not JSON_PATH.exists():
        print(f"[ERROR] No existe {JSON_PATH}", file=sys.stderr)
        sys.exit(1)
    with open(JSON_PATH, encoding="utf-8") as f:
        data = json.load(f)
    cities = data.get("cities")
    if not isinstance(cities, list) or not cities:
        print("[ERROR] locations.json sin 'cities' o vacío", file=sys.stderr)
        sys.exit(1)
    for c in cities:
        if not all(k in c for k in ("name", "lat", "lng", "timezone")):
            print(f"[ERROR] Ciudad sin campos requeridos: {c}", file=sys.stderr)
            sys.exit(1)
        try:
            float(c["lat"])
            float(c["lng"])
        except Exception:
            print(f"[ERROR] lat/lng no numéricos: {c}", file=sys.stderr)
            sys.exit(1)
    # lng_u desenrollado (offset += 360 si curr <= prev), como en sea_route.py.
    unwrapped = []
    offset = 0
    prev = None
    for c in cities:
        lng = float(c["lng"])
        curr = lng + offset
        if prev is not None and curr <= prev:
            offset += 360
            curr = lng + offset
        unwrapped.append(curr)
        prev = curr
    return data, cities, unwrapped


def find_city_indices(cities, targets) -> list[int]:
    """Resuelve índices origen con normalización NFD sobre name|asciiname."""
    if not targets:
        return list(range(len(cities)))
    wanted = {}
    for t in targets:
        wanted[normalize(t)] = t
    found = []
    missing = []
    for idx, c in enumerate(cities):
        names = {normalize(c.get("name", "")), normalize(c.get("asciiname", ""))} - {""}
        for key in wanted:
            if key in names:
                found.append(idx)
                break
    for t in targets:
        key = normalize(t)
        if not any(key in {normalize(c.get("name", "")), normalize(c.get("asciiname", ""))}
                   for c in cities):
            missing.append(t)
    if missing:
        print(f'[ERROR] Ciudades no encontradas en locations.json: {", ".join(missing)}',
              file=sys.stderr)
        sys.exit(1)
    return found


# ---------------------------------------------------------------------------
# Cliente OSRM con caché y cortesía
# ---------------------------------------------------------------------------

def _cache_path(profile: str, url: str) -> Path:
    digest = hashlib.sha1(url.encode("utf-8")).hexdigest()
    return CACHE_ROOT / profile / f"{digest}.json"


def _respect_rate_limit() -> None:
    """Espera lo necesario para dejar >= MIN_INTERVAL_S entre peticiones."""
    global _last_request_ts
    now = time.monotonic()
    wait = MIN_INTERVAL_S - (now - _last_request_ts)
    if wait > 0:
        time.sleep(wait)


def osrm_get(url: str, profile: str = "car") -> dict | None:
    """GET a OSRM con caché cruda, pausa de cortesía y reintentos ante 429.

    Devuelve el JSON parseado o None en fallo irrecuperable (lo registra
    con su `code`: NoRoute, NoSegment, TooBig, InvalidUrl, 429, timeout).
    La caché guarda la respuesta cruda indexada por sha1(url).
    """
    global _last_request_ts, _osrm_data_version
    cache = _cache_path(profile, url)
    if cache.exists():
        try:
            with open(cache, encoding="utf-8") as f:
                return json.load(f)
        except Exception as e:
            print(f"[WARN] Caché ilegible, se reintenta en red: {cache} ({e})",
                  file=sys.stderr)
    _respect_rate_limit()
    last_code = "Unknown"
    for attempt in range(len(RETRY_DELAYS) + 1):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
            with urllib.request.urlopen(req, timeout=REQUEST_TIMEOUT_S) as resp:
                raw = resp.read().decode("utf-8")
            _last_request_ts = time.monotonic()
            payload = json.loads(raw)
            dv = payload.get("data_version")
            if isinstance(dv, str) and _osrm_data_version is None:
                _osrm_data_version = dv
            cache.parent.mkdir(parents=True, exist_ok=True)
            with open(cache, "w", encoding="utf-8") as f:
                f.write(raw)
            return payload
        except urllib.error.HTTPError as e:
            _last_request_ts = time.monotonic()
            last_code = f"HTTP {e.code}"
            if e.code == 429 and attempt < len(RETRY_DELAYS):
                delay = RETRY_DELAYS[attempt]
                print(f"[WARN] 429 en {url}, reintento {attempt + 1}/3 en {delay} s",
                      file=sys.stderr)
                time.sleep(delay)
                continue
            print(f"[WARN] OSRM {e.code} en {url}", file=sys.stderr)
            return None
        except (urllib.error.URLError, TimeoutError, OSError) as e:
            _last_request_ts = time.monotonic()
            last_code = "timeout" if isinstance(e, TimeoutError) else "URLError"
            print(f"[WARN] OSRM sin respuesta en {url} ({e})", file=sys.stderr)
            return None
        except (json.JSONDecodeError, ValueError) as e:
            _last_request_ts = time.monotonic()
            print(f"[WARN] OSRM respuesta inválida en {url} ({e})", file=sys.stderr)
            return None
    print(f"[WARN] OSRM 429 agotado en {url} (código {last_code})", file=sys.stderr)
    return None


# ---------------------------------------------------------------------------
# Pool de candidatos y matriz de distancias
# ---------------------------------------------------------------------------

def build_pool(cities, origin_idx: int, pool_size: int, direction: str = "east") -> list[dict]:
    """Las `pool_size` ciudades más cercanas por círculo grande hacia el Este
    (`direction="east"`) u Oeste (`direction="west"`).

    Filtra con 0 < delta <= MAX_EAST_DEG (o -MAX_EAST_DEG <= delta < 0) sobre
    la ciudad (no sobre el enganche), excluye el propio nombre, ordena por
    Haversine y corta.
    """
    origin = cities[origin_idx]
    o_lat, o_lng = float(origin["lat"]), float(origin["lng"])
    scored = []
    for idx, cand in enumerate(cities):
        if idx == origin_idx or cand["name"] == origin["name"]:
            continue
        delta = eastward_delta(o_lng, float(cand["lng"]))
        if direction == "east" and not (0 < delta <= MAX_EAST_DEG):
            continue
        if direction == "west" and not (-MAX_EAST_DEG <= delta < 0):
            continue
        gc = haversine(o_lat, o_lng, float(cand["lat"]), float(cand["lng"]))
        scored.append({"city": cand, "gcKm": gc, "deltaLng": delta})
    scored.sort(key=lambda item: item["gcKm"])
    return scored[:pool_size]


def table_distances(profile: str, origin: dict, pool: list[dict]) -> list | None:
    """Una llamada /table con origen + candidatas (como mucho 6 coordenadas).

    Devuelve la fila `durations`/`distances[0]` (metros, None si no hay
    camino) o None si la petición falló.
    """
    coords = [f'{float(origin["lng"])},{float(origin["lat"])}']
    for item in pool:
        c = item["city"]
        coords.append(f'{float(c["lng"])},{float(c["lat"])}')
    joined = ";".join(coords)
    url = (f"{OSRM_SERVER}/table/v1/{profile}/{joined}"
           f"?sources=0&annotations=distance")
    payload = osrm_get(url, profile)
    if payload is None:
        return None
    if payload.get("code") != "Ok":
        print(f'[WARN] /table {origin["name"]}: code {payload.get("code")}',
              file=sys.stderr)
        return None
    rows = payload.get("distances") or payload.get("durations")
    if not rows or not isinstance(rows[0], list):
        print(f'[WARN] /table {origin["name"]}: sin matriz', file=sys.stderr)
        return None
    return rows[0]


# ---------------------------------------------------------------------------
# Geometría de la ruta y anclaje
# ---------------------------------------------------------------------------

def city_vertex(city) -> list[float]:
    """Coordenadas de la ciudad como primer/último vértice de la LineString."""
    return [
        round(normalize_lng(float(city["lng"])), COORD_PRECISION),
        round(float(city["lat"]), COORD_PRECISION),
    ]


def anchor_to_cities(coordinates, origin, dest) -> list:
    """Antepone la ciudad origen y pospone la ciudad destino.

    Nunca sustituye un vértice: el camino de OSRM se conserva entero y solo
    se le añade el tramo ciudad↔calzada en cada extremo. Si la ciudad ya
    coincide con el vértice vecino (misma posición redondeada a
    `COORD_PRECISION`) no se duplica, que un segmento de longitud cero
    rompe los mapas.
    """
    start = city_vertex(origin)
    end = city_vertex(dest)
    if coordinates[0] != start:
        coordinates = [start] + coordinates
    if coordinates[-1] != end:
        coordinates = coordinates + [end]
    return coordinates


def _road_point(waypoint: dict, fallback: dict) -> dict:
    """Enganche a calzada: nombre de calle OSRM + distancia centro→calzada."""
    loc = waypoint.get("location") or [fallback["lng"], fallback["lat"]]
    try:
        w_lng, w_lat = float(loc[0]), float(loc[1])
    except Exception:
        w_lng, w_lat = float(fallback["lng"]), float(fallback["lat"])
    snap = haversine(float(fallback["lat"]), float(fallback["lng"]), w_lat, w_lng)
    return {
        "name": waypoint.get("name") or "",
        "lat": round(w_lat, COORD_PRECISION),
        "lng": round(normalize_lng(w_lng), COORD_PRECISION),
        "snapKm": round(snap, 1),
    }


def build_route(profile: str, origin: dict, dest: dict, direction: str = "east") -> dict | None:
    """Una ruta /route con overview=simplified, anclada a las ciudades.

    Devuelve el dict de ruta listo para persistir, o None con el motivo
    registrado ([SKIP] NoRoute / NoSegment / TooBig / 429 / timeout).
    `direction` se persiste como `heading` (east|west).
    """
    url = (f'{OSRM_SERVER}/route/v1/{profile}/'
           f'{float(origin["lng"])},{float(origin["lat"])};'
           f'{float(dest["lng"])},{float(dest["lat"])}'
           f'?geometries=geojson&overview=simplified&steps=false')
    payload = osrm_get(url, profile)
    if payload is None:
        print(f"[SKIP] {origin['name']} → {dest['name']}: sin respuesta (timeout o 429)",
              file=sys.stderr)
        return None
    code = payload.get("code")
    if code != "Ok":
        print(f"[SKIP] {origin['name']} → {dest['name']}: {code}", file=sys.stderr)
        return None
    candidates = payload.get("routes") or []
    if not candidates:
        print(f"[SKIP] {origin['name']} → {dest['name']}: NoRoute", file=sys.stderr)
        return None
    best = candidates[0]
    try:
        distance_m = float(best["distance"])
        duration_s = float(best["duration"])
    except Exception:
        print(f"[SKIP] {origin['name']} → {dest['name']}: NoSegment", file=sys.stderr)
        return None
    if not (0 < distance_m / 1000.0 < MAX_DISTANCE_KM):
        print(f"[SKIP] {origin['name']} → {dest['name']}: TooBig", file=sys.stderr)
        return None
    geom = (best.get("geometry") or {}).get("coordinates") or []
    if len(geom) < 2:
        print(f"[SKIP] {origin['name']} → {dest['name']}: NoSegment", file=sys.stderr)
        return None
    coordinates = [
        [round(normalize_lng(float(x)), COORD_PRECISION), round(float(y), COORD_PRECISION)]
        for x, y in geom
    ]
    coordinates = anchor_to_cities(coordinates, origin, dest)
    waypoints = payload.get("waypoints") or [{}, {}]
    road_origin = _road_point(waypoints[0] if len(waypoints) > 0 else {}, origin)
    road_dest = _road_point(waypoints[-1] if len(waypoints) > 1 else {}, dest)
    for road, city in ((road_origin, origin), (road_dest, dest)):
        if road["snapKm"] > SNAP_WARN_KM:
            print(f'[WARN] {city["name"]}: enganche a {road["snapKm"]:.1f} km '
                  f'({road["name"] or "sin nombre"})', file=sys.stderr)
    if road_origin["snapKm"] > SNAP_MAX_KM or road_dest["snapKm"] > SNAP_MAX_KM:
        print(f"[SKIP] {origin['name']} → {dest['name']}: NoSegment "
              f"(enganche a {max(road_origin['snapKm'], road_dest['snapKm']):.1f} km)",
              file=sys.stderr)
        return None
    return {
        "origin": origin["name"],
        "originLat": origin["lat"],
        "originLng": origin["lng"],
        "destination": dest["name"],
        "destinationLat": dest["lat"],
        "destinationLng": dest["lng"],
        "distanceKm": round(distance_m / 1000.0, 1),
        "durationHours": round(duration_s / 3600.0, 1),
        "heading": direction,
        "roadOrigin": road_origin,
        "roadDest": road_dest,
        "geometry": {"type": "LineString", "coordinates": coordinates},
    }


# ---------------------------------------------------------------------------
# Cierre de huecos de cobertura (SPEC 008)
# ---------------------------------------------------------------------------

def gap_uncovered(cities, routes) -> list[dict]:
    """Ciudades descubiertas en la unión mar ∪ tierra con rutas actuales."""
    sea = route_coverage.load_routes(route_coverage.SEA_ROUTES_PATH)
    return route_coverage.compute_coverage(cities, sea, routes)


def gap_table(profile: str, origin: dict, east_pool: list, west_pool: list):
    """Un único /table con pool este y pool oeste como destinos.

    Devuelve (filaEste, filaOeste): distancia en metros por candidata
    (None si no hay camino) o (None, None) si la petición falla.
    """
    coords = [f'{float(origin["lng"])},{float(origin["lat"])}']
    for item in east_pool + west_pool:
        c = item["city"]
        coords.append(f'{float(c["lng"])},{float(c["lat"])}')
    url = (f"{OSRM_SERVER}/table/v1/{profile}/" + ";".join(coords)
           + "?sources=0&annotations=distance")
    payload = osrm_get(url, profile)
    if payload is None:
        return None, None
    if payload.get("code") != "Ok":
        print(f'[WARN] /table hueco {origin["name"]}: code {payload.get("code")}',
              file=sys.stderr)
        return None, None
    rows = payload.get("distances") or payload.get("durations")
    if not rows or not isinstance(rows[0], list):
        print(f'[WARN] /table hueco {origin["name"]}: sin matriz', file=sys.stderr)
        return None, None
    row = rows[0][1:]
    return (row[:len(east_pool)], row[len(east_pool):])


def pick_gap_candidate(pool: list, row) -> dict | None:
    """Primera candidata de la pool (orden Haversine) con camino según /table.

    Se respeta el orden Haversine de la pool, no la menor distancia de la
    matriz: el /table del demo devuelve valores fantasma (medido: Madrid →
    tombuctu "684 km" cuando la distancia real pasa de 2.600 km), así que
    la verificación real es build_route con /route.
    """
    if row is None:
        return None
    for item, dist in zip(pool, row):
        if dist is not None:
            return item
    return None


def gap_route_ok(route: dict) -> bool:
    """Invariante de validate_dataset sobre una ruta de cierre.

    El demo devuelve rutas fantasma que SNAP_MAX_KM no alcanza a descartar
    (medido: Tarifa ↔ Tánger, distancia OSRM 1,3 km y geometría anclada de
    35,3 km); sin este filtro una ruta inválida bloquea la escritura entera.
    """
    dist = route["distanceKm"]
    hsum = haversine_sum(route["geometry"]["coordinates"])
    if dist and abs(hsum - dist) / dist > LENGTH_TOLERANCE:
        print(f'[SKIP] {route["origin"]} → {route["destination"]}: distancia '
              f'fantasma (distanceKm {dist:.1f} vs haversine {hsum:.1f})',
              file=sys.stderr)
        return False
    return True


def close_outbound_gap(profile: str, cities, origin_idx: int) -> dict | None:
    """Ruta de salida para una ciudad sin ella: pool este → pool oeste.

    Como mucho 1 /table (este + oeste en la misma petición) y 1 /route,
    con la caché, el rate limit y los guardias de build_route existentes.
    """
    origin = cities[origin_idx]
    east_pool = build_pool(cities, origin_idx, GAP_POOL, "east")
    west_pool = build_pool(cities, origin_idx, GAP_POOL, "west")
    if not east_pool and not west_pool:
        print(f'[WARN] {origin["name"]}: sin candidatas para el hueco de salida',
              file=sys.stderr)
        return None
    row_east, row_west = gap_table(profile, origin, east_pool, west_pool)
    item = pick_gap_candidate(east_pool, row_east)
    direction = "east"
    if item is None:
        item = pick_gap_candidate(west_pool, row_west)
        direction = "west"
    if item is None and (east_pool or west_pool):
        # /table sin ningún valor: el demo devuelve nulos espurios (medido:
        # Teresina→Salvador, SPEC 006 §12), así que la candidata más
        # cercana por Haversine se verifica igualmente con /route; sigue
        # siendo 1 /table + 1 /route por hueco (presupuesto SPEC 008 §2).
        item = min(east_pool + west_pool, key=lambda i: i["gcKm"])
        delta = eastward_delta(float(origin["lng"]), float(item["city"]["lng"]))
        direction = "east" if 0 < delta <= MAX_EAST_DEG else "west"
    if item is None:
        print(f'[WARN] {origin["name"]}: sin camino por tierra (hueco de salida)',
              file=sys.stderr)
        return None
    route = build_route(profile, origin, item["city"], direction)
    if route is None:
        return None  # build_route ya registra el motivo ([SKIP])
    if not gap_route_ok(route):
        return None
    route["gapClosed"] = True
    print(f'[INFO] {origin["name"]} → {route["destination"]} '
          f'({direction}, {route["distanceKm"]} km): hueco de salida cerrado')
    return route


def close_inbound_gap(profile: str, cities, routes: list,
                      target_idx: int, limit: int) -> dict | None:
    """Ruta de llegada para una ciudad sin ella (inverso del cierre de salida).

    Candidatas origen ordenadas por Haversine; una única petición /table con
    `sources=0..n-1&destinations=n` lista los pares con camino y se prefiere
    la más cercana con capacidad (< limitPerOrigin rutas normales). Cada
    candidata se verifica con /route (máximo MAX_GAP_ROUTE_TRIES) hasta que
    una pase el filtro de distancia; sin origen con capacidad se permite
    superar limitPerOrigin porque las gapClosed no cuentan para el límite.
    """
    target = cities[target_idx]
    target_key = target["name"]
    normal_by_origin: dict[str, int] = {}
    for r in routes:
        if not r.get("gapClosed"):
            normal_by_origin[r["origin"]] = normal_by_origin.get(r["origin"], 0) + 1

    others = sorted(
        (c for i, c in enumerate(cities)
         if i != target_idx and c["name"] != target_key),
        key=lambda c: haversine(float(target["lat"]), float(target["lng"]),
                                float(c["lat"]), float(c["lng"])),
    )[:GAP_POOL]
    if not others:
        print(f'[WARN] {target_key}: sin candidatas para el hueco de entrada',
              file=sys.stderr)
        return None

    coords = [f'{float(c["lng"])},{float(c["lat"])}' for c in others]
    coords.append(f'{float(target["lng"])},{float(target["lat"])}')
    last = len(others)
    sources = ",".join(str(i) for i in range(last))
    url = (f"{OSRM_SERVER}/table/v1/{profile}/" + ";".join(coords)
           + f"?sources={sources}&destinations={last}")
    payload = osrm_get(url, profile)
    row: list | None = None
    if payload is not None and payload.get("code") == "Ok":
        matrix = payload.get("distances") or payload.get("durations")
        if matrix and all(isinstance(r, list) and len(r) > last for r in matrix):
            row = [r[last] for r in matrix[:last]]
        else:
            print(f'[WARN] /table hueco entrada {target_key}: sin matriz',
                  file=sys.stderr)
    elif payload is not None:
        print(f'[WARN] /table hueco entrada {target_key}: '
              f'code {payload.get("code")}', file=sys.stderr)

    has_room = lambda name: normal_by_origin.get(name, 0) < limit  # noqa: E731

    # Secuencia de candidatas: Haversine, primero con capacidad (< limit
    # rutas normales, las gapClosed no cuentan) y después el resto; el
    # resultado de /table solo desordena dentro de cada tramo porque los
    # nulos del demo son espurios. Se verifica con /route hasta que una
    # pase (máximo MAX_GAP_ROUTE_TRIES): el primer candidato suele ser
    # una isla o un par sin enganche rodado.
    ordered = ([c for c in others if has_room(c["name"])]
               + [c for c in others if not has_room(c["name"])])
    path_hint = dict(zip((id(c) for c in others),
                         (d is not None for d in row) if row else
                         (False for _ in others)))
    seen: set[int] = set()
    sequence = [c for c in ordered
                if path_hint.get(id(c)) and not seen.add(id(c))] \
        + [c for c in ordered if not seen.add(id(c))]

    tries = 0
    for chosen in sequence:
        if tries >= MAX_GAP_ROUTE_TRIES:
            break
        tries += 1
        delta = eastward_delta(float(chosen["lng"]), float(target["lng"]))
        direction = "east" if 0 < delta <= MAX_EAST_DEG else "west"
        route = build_route(profile, chosen, target, direction)
        if route is None:
            continue  # build_route ya registra el motivo ([SKIP])
        if not gap_route_ok(route):
            continue
        route["gapClosed"] = True
        print(f'[INFO] {route["origin"]} → {target_key} '
              f'({direction}, {route["distanceKm"]} km): hueco de entrada '
              f'cerrado (intento {tries})')
        return route
    print(f'[SKIP] {target_key}: {tries} candidatas de entrada sin ruta '
          f'válida (hueco de entrada queda pendiente)', file=sys.stderr)
    return None


def insert_gap_route(routes: list, route: dict) -> bool:
    """Inserta una ruta `gapClosed` sin tocar las existentes.

    Mantiene el grupo de origen contiguo y ordenado por distanceKm
    ascendente (invariante de validate_dataset).
    """
    if any(r["origin"] == route["origin"] and r["destination"] == route["destination"]
           for r in routes):
        print(f'[WARN] {route["origin"]} → {route["destination"]}: ya existe, '
              f'se omite el cierre', file=sys.stderr)
        return False
    group = [i for i, r in enumerate(routes) if r["origin"] == route["origin"]]
    if not group:
        routes.append(route)
        return True
    pos = group[-1] + 1
    for i in group:
        if routes[i]["distanceKm"] > route["distanceKm"]:
            pos = i
            break
    routes.insert(pos, route)
    return True


def coverage_meta(cities, routes) -> dict:
    """meta.coverage de SPEC 008 §3.1 (recuento real sobre el archivo)."""
    uncovered = gap_uncovered(cities, routes)
    return {
        "cities": len(cities),
        "withoutOutbound": sum(1 for item in uncovered if item["outbound"] == 0),
        "withoutInbound": sum(1 for item in uncovered if item["inbound"] == 0),
        "exceptions": sum(1 for item in uncovered
                          if route_coverage.is_exception(item["decision"])),
    }


# ---------------------------------------------------------------------------
# Validación y persistencia
# ---------------------------------------------------------------------------

def crosses_antimeridian(coordinates) -> bool:
    """True si algún par de vértices salta de un meridiano al otro."""
    for i in range(len(coordinates) - 1):
        if abs(coordinates[i + 1][0] - coordinates[i][0]) > 180:
            return True
    return False


def validate_dataset(routes, limit) -> list[str]:
    """Invariantes del dataset. Lista vacía = correcto."""
    problems = []
    seen = set()
    by_origin: dict[str, list] = {}
    for route in routes:
        key = f'{route["origin"]}::{route["destination"]}'
        if key in seen:
            problems.append(f"duplicado {key}")
        seen.add(key)
        if route["origin"] == route["destination"]:
            problems.append(f"origen == destino {key}")
        by_origin.setdefault(route["origin"], []).append(route)
        if "gapClosed" in route and not isinstance(route["gapClosed"], bool):
            problems.append(f"gapClosed no booleano en {key}: "
                            f"{route['gapClosed']!r}")

        distance = route.get("distanceKm")
        if not isinstance(distance, (int, float)) or not (0 < distance < MAX_DISTANCE_KM):
            problems.append(f"distanceKm fuera de rango en {key}: {distance}")
        duration = route.get("durationHours")
        if not isinstance(duration, (int, float)) or not (duration > 0):
            problems.append(f"durationHours fuera de rango en {key}: {duration}")
        for road_key in ("roadOrigin", "roadDest"):
            road = route.get(road_key) or {}
            if not all(k in road for k in ("name", "lat", "lng", "snapKm")):
                problems.append(f"{road_key} incompleto en {key}")
        coords = route["geometry"]["coordinates"]
        if len(coords) < 2:
            problems.append(f"geometría con menos de 2 vértices en {key}")
            continue
        if route["geometry"].get("type") != "LineString":
            problems.append(f"geometry.type distinto de LineString en {key}")
        # La geometría arranca y termina en la ciudad (a 5 decimales).
        expected_start = [round(normalize_lng(float(route["originLng"])), COORD_PRECISION),
                          round(float(route["originLat"]), COORD_PRECISION)]
        expected_end = [round(normalize_lng(float(route["destinationLng"])), COORD_PRECISION),
                        round(float(route["destinationLat"]), COORD_PRECISION)]
        if coords[0] != expected_start:
            problems.append(f"no arranca en la ciudad origen en {key}: {coords[0]}")
        if coords[-1] != expected_end:
            problems.append(f"no termina en la ciudad destino en {key}: {coords[-1]}")
        for lng, lat in coords:
            if not (-180 <= lng <= 180 and -90 <= lat <= 90):
                problems.append(f"coordenada fuera de rango en {key}: {lng},{lat}")
                break
        # Regla del Este sobre la ciudad, no sobre el enganche (SPEC 006 §6),
        # salvo heading="west" (fallback de origen, SPEC 006 §12).
        try:
            delta = eastward_delta(float(route["originLng"]), float(route["destinationLng"]))
        except Exception:
            problems.append(f"lng no numérico en {key}")
            continue
        heading = route.get("heading") or ("east" if delta > 0 else "west")
        if heading == "east" and not (0 < delta <= MAX_EAST_DEG):
            problems.append(f"Regla del Este incumplida en {key}: delta {delta:.3f}º")
        elif heading == "west" and not (-MAX_EAST_DEG <= delta < 0):
            problems.append(f"heading west con delta {delta:.3f}º en {key}")
        elif heading not in ("east", "west"):
            problems.append(f"heading desconocido {heading!r} en {key}")
        if route.get("heading") and route["heading"] != ("east" if delta > 0 else "west"):
            problems.append(f"heading {route['heading']} no coincide con el delta "
                            f"{delta:.3f}º en {key}")
        hsum = haversine_sum(coords)
        if distance and abs(hsum - distance) / distance > LENGTH_TOLERANCE:
            problems.append(
                f"distanceKm {distance:.1f} vs haversine {hsum:.1f} en {key} "
                f"(±{LENGTH_TOLERANCE * 100:.0f}%)"
            )

    for origin, group in by_origin.items():
        # limitPerOrigin acota las rutas normales; las gapClosed (SPEC 008
        # §3.1) no cuentan para el límite, pero sí para la cobertura.
        normal = [r for r in group if not r.get("gapClosed")]
        if len(normal) > limit:
            problems.append(f"{origin} tiene {len(normal)} rutas, máximo {limit}")
        distances = [r["distanceKm"] for r in group]
        if distances != sorted(distances):
            problems.append(f"{origin} no ordenado por distanceKm ascendente")

    # SPEC 008 paso 7: la unión mar ∪ tierra debe cubrir el catálogo entero;
    # las ciudades con `excepción` en el informe se aceptan.
    sea = route_coverage.load_routes(route_coverage.SEA_ROUTES_PATH)
    problems += route_coverage.coverage_problems(sea, routes)
    return problems


def build_meta(origins_total: int, routes: list, unroutable: int,
               without_route: int, limit: int, pool: int, profile: str) -> dict:
    crossings = sum(1 for r in routes if crosses_antimeridian(r["geometry"]["coordinates"]))
    west = [r for r in routes if r.get("heading") == "west"]
    meta = {
        "project": PROJECT,
        "name": "Fogg Land Routes — Herencia de Phoebe",
        "version": SCHEMA_VERSION,
        "generated": date.today().isoformat(),
        "tool": TOOL_NAME,
        "profile": profile,
        "osrmServer": OSRM_SERVER,
        "osrmWeightName": OSRM_WEIGHT_NAME,
        "osrmDataVersion": _osrm_data_version or "unknown",
        "units": "km",
        "limitPerOrigin": limit,
        "minRoutesPerOrigin": MIN_ROUTES_PER_ORIGIN,
        "maxEastDeg": MAX_EAST_DEG,
        "candidatePool": pool,
        "origins": origins_total,
        "routes": len(routes),
        "originsWithoutRoute": without_route,
        "unroutableCities": unroutable,
        "crossesAntimeridian": crossings,
        "eastRule": "heading east: 0 < deltaLng(cityDest - cityOrigin) <= 180 (desenrollado); "
                    "heading west: -180 <= deltaLng < 0, solo como fallback cuando un origen "
                    "tiene menos de minRoutesPerOrigin rutas al Este",
        "poolRule": ("los pool candidatos más cercanos por círculo grande dentro de "
                     "maxEastDeg en cada dirección; se descartan los que OSRM no puede "
                     "enrutar; el pool oeste solo se consulta si el este no llega a "
                     "minRoutesPerOrigin rutas"),
        "geometry": ("LineString [lng,lat] de ciudad a ciudad: el primer y el último "
                     "vértice son las coordenadas de la ciudad de locations.json y entre "
                     "medias va la carretera de OSRM con overview=simplified"),
        "distanceNote": ("distanceKm es routes[0].distance de OSRM; NO es la suma Haversine "
                         "de la geometría, que con overview=simplified queda hasta un 9% "
                         "por debajo al recortar curvas"),
        "attribution": ("© OpenStreetMap contributors (ODbL); routing courtesy of the "
                        "OSRM demo server sponsored by FOSSGIS"),
        "source": "OSRM demo server (car) + GeoNames cities15000",
    }
    if west:
        meta["westFallbackNote"] = (
            f"{len(west)} rutas con heading west; destinos hacia el Oeste porque el origen "
            f"no alcanzó minRoutesPerOrigin rutas al Este"
        )
    return meta


def write_output(out_path: Path, meta: dict, routes: list) -> None:
    out_path.parent.mkdir(parents=True, exist_ok=True)
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump({"meta": meta, "routes": routes}, f, indent=2, ensure_ascii=False)
        f.write("\n")
    try:
        with open(out_path, encoding="utf-8") as f:
            json.load(f)
    except Exception as e:
        print(f"[ERROR] JSON inválido tras escribir: {e}", file=sys.stderr)
        sys.exit(1)


def load_existing(out_path: Path) -> tuple[list, set, dict]:
    """Rutas ya escritas (para --resume). Devuelve (rutas, orígenes, meta previo).

    Rellena `heading` en las rutas del esquema 1.0.0, que no lo traían:
    con la Regla del Este histórica todas son rutas al Este.
    """
    if not out_path.exists():
        return [], set(), {}
    try:
        with open(out_path, encoding="utf-8") as f:
            data = json.load(f)
        routes = data.get("routes") or []
        for route in routes:
            if "heading" not in route:
                delta = eastward_delta(float(route["originLng"]),
                                       float(route["destinationLng"]))
                route["heading"] = "east" if delta > 0 else "west"
        origins = {r["origin"] for r in routes if "origin" in r}
        meta = data.get("meta") or {}
        return routes, origins, meta
    except Exception as e:
        print(f"[WARN] No se pudo leer {out_path} para --resume ({e})", file=sys.stderr)
        return [], set(), {}


# ---------------------------------------------------------------------------
# Orquestación
# ---------------------------------------------------------------------------

def close_gaps(args) -> None:
    """Pasada de cierre de huecos de cobertura (SPEC 008, `--close-gaps`).

    Posterior al lote normal, no lo sustituye: para cada ciudad de la unión
    mar ∪ tierra sin ruta de salida la traza por carretera (pool este →
    pool oeste) con 1 /table + 1 /route por hueco.
    """
    _, cities, _ = load_locations()
    routes, _, prev_meta = load_existing(args.out)
    if not routes:
        print(f"[ERROR] No hay rutas previas en {args.out}: ejecuta primero el "
              f"lote normal (un cierre sobre un fichero vacío no tiene sentido "
              f"porque la validación de orden y límites exige el lote)",
              file=sys.stderr)
        sys.exit(1)
    print(f"[INFO] --close-gaps: {len(routes)} rutas previas en {args.out}")

    uncovered = gap_uncovered(cities, routes)
    out_gaps = [item for item in uncovered if item["outbound"] == 0]
    print(f"[INFO] {len(out_gaps)} ciudades sin salida por mar ni tierra")
    name_to_idx = {c["name"]: i for i, c in enumerate(cities)}

    added = 0
    for item in out_gaps:
        idx = name_to_idx.get(item["name"])
        if idx is None:
            print(f'[WARN] {item["name"]}: fuera del catálogo, se omite',
                  file=sys.stderr)
            continue
        route = close_outbound_gap(args.profile, cities, idx)
        if route is not None and insert_gap_route(routes, route):
            added += 1
    print(f"[INFO] {added} rutas de salida añadidas "
          f"({len(out_gaps) - added} huecos sin cerrar)")

    # Una ruta de salida puede haber dado entrada a otra ciudad: se recalcula.
    uncovered = gap_uncovered(cities, routes)
    in_gaps = [item for item in uncovered if item["inbound"] == 0]
    print(f"[INFO] {len(in_gaps)} ciudades sin entrada por mar ni tierra")
    added_in = 0
    for item in in_gaps:
        idx = name_to_idx.get(item["name"])
        if idx is None:
            print(f'[WARN] {item["name"]}: fuera del catálogo, se omite',
                  file=sys.stderr)
            continue
        route = close_inbound_gap(args.profile, cities, routes, idx, args.limit)
        if route is not None and insert_gap_route(routes, route):
            added_in += 1
    print(f"[INFO] {added_in} rutas de entrada añadidas "
          f"({len(in_gaps) - added_in} huecos sin cerrar)")

    problems = validate_dataset(routes, args.limit)
    for p in problems:
        print(f"[ERROR] {p}", file=sys.stderr)
    if problems:
        print(f"[ERROR] {len(problems)} problemas de validación, no se escribe",
              file=sys.stderr)
        sys.exit(1)

    unique = len({r["origin"] for r in routes})
    origins_total = max(len(cities), int(prev_meta.get("origins") or 0))
    meta = build_meta(origins_total, routes,
                      int(prev_meta.get("unroutableCities") or 0),
                      origins_total - unique, args.limit, args.pool, args.profile)
    meta["gapClosedRoutes"] = sum(1 for r in routes if r.get("gapClosed"))
    meta["coverage"] = coverage_meta(cities, routes)
    if args.dry_run:
        print(f"[INFO] dry-run: no se escribe {args.out}")
        return
    write_output(args.out, meta, routes)
    print(f'[INFO] Guardadas {len(routes)} rutas '
          f'({meta["gapClosedRoutes"]} gapClosed) en {args.out}')


def main():
    parser = argparse.ArgumentParser(
        description=(
            "Fogg Land Routes — hasta 5 rutas por carretera hacia el Este "
            f"(OSRM {OSRM_SERVER}, 1 petición/s)"
        ),
        formatter_class=argparse.RawTextHelpFormatter,
    )
    parser.add_argument("--profile", default="car",
                        help='Perfil OSRM (solo "car" en esta spec)')
    parser.add_argument("--city", action="append", default=[], metavar="NOMBRE",
                        help="Ciudad origen (repetible). Sin --city: todas")
    parser.add_argument("--limit", type=int, default=DEFAULT_LIMIT,
                        help=f"Rutas por origen (default {DEFAULT_LIMIT})")
    parser.add_argument("--pool", type=int, default=DEFAULT_POOL,
                        help=f"Candidatas por origen (default {DEFAULT_POOL})")
    parser.add_argument("--only", type=int, default=None, metavar="N",
                        help="Procesa solo los N primeros orígenes y sale con código 0")
    parser.add_argument("--resume", action="store_true",
                        help="Salta los orígenes ya presentes en el fichero de salida")
    parser.add_argument("--close-gaps", action="store_true",
                        help="Pasada de cierre de huecos (SPEC 008): ruta de salida "
                             "para toda ciudad sin ella, posterior al lote normal")
    parser.add_argument("--dry-run", action="store_true",
                        help="Detalla el resultado sin escribir disco")
    parser.add_argument("--out", type=Path, default=CAR_ROUTES_PATH,
                        help=f"Ruta de salida (default {CAR_ROUTES_PATH})")
    args = parser.parse_args()

    if args.profile != "car":
        print(f"[ERROR] --profile {args.profile!r} no soportado: el servidor demo "
              f"devuelve datos de coche (driving/foot/bike byte-idénticos, "
              f"weight_name={OSRM_WEIGHT_NAME}); no se escribe ningún fichero",
              file=sys.stderr)
        sys.exit(1)
    if args.limit <= 0:
        print("[ERROR] --limit debe ser >0", file=sys.stderr)
        sys.exit(1)
    if args.pool <= 0:
        print("[ERROR] --pool debe ser >0", file=sys.stderr)
        sys.exit(1)

    if args.close_gaps:
        close_gaps(args)
        return

    _, cities, _ = load_locations()
    selected_indices = find_city_indices(cities, args.city)
    if args.only is not None:
        if args.only <= 0:
            print("[ERROR] --only debe ser >0", file=sys.stderr)
            sys.exit(1)
        selected_indices = selected_indices[:args.only]
    print(f"[INFO] {len(cities)} ciudades en {JSON_PATH}")
    print(f"[INFO] orígenes solicitados: {len(selected_indices)}"
          f"{' (el lote completo)' if not args.city and args.only is None else ''}")

    existing_routes: list = []
    done_origins: set = set()
    prev_meta: dict = {}
    if args.resume and not args.dry_run:
        existing_routes, done_origins, prev_meta = load_existing(args.out)
        if done_origins:
            print(f"[INFO] --resume: {len(done_origins)} orígenes ya en {args.out}, se saltan "
                  f"({len(existing_routes)} rutas conservadas)")

    routes: list = list(existing_routes)
    # `unroutable_hits` es acumulado (se siembra del meta previo en --resume);
    # `origins_without` es de esta corrida y el meta final lo deriva del catálogo.
    unroutable_hits = int(prev_meta.get("unroutableCities") or 0)
    origins_without = 0
    processed = 0

    def current_meta() -> dict:
        unique = len({r["origin"] for r in routes})
        base = int(prev_meta.get("origins") or 0) if args.resume else 0
        origins_total = max(base, unique + origins_without)
        return build_meta(origins_total, routes, unroutable_hits,
                          origins_total - unique, args.limit, args.pool, args.profile)

    for pos, idx in enumerate(selected_indices):
        origin = cities[idx]
        if origin["name"] in done_origins:
            continue
        pool_east = build_pool(cities, idx, args.pool, "east")
        if args.dry_run:
            pool_west = build_pool(cities, idx, args.pool, "west")
            print(f'  {origin["name"]:<22} {len(pool_east)} candidatas este, '
                  f'{len(pool_west)} oeste')
            for label, pool in (("", pool_east), ("[oeste]", pool_west)):
                for item in pool:
                    c = item["city"]
                    print(f'    {label:<8} {c["name"]:<24} gc {item["gcKm"]:8.1f} km  '
                          f'delta {item["deltaLng"]:6.1f}º')
            print(f'  {origin["name"]:<22} rutas previstas al Este (el pool oeste solo '
                  f'entra si no llega a {MIN_ROUTES_PER_ORIGIN})')
            processed += 1
            continue

        built: list = []
        for direction in ("east", "west"):
            if direction == "west" and len(built) >= MIN_ROUTES_PER_ORIGIN:
                break
            pool = build_pool(cities, idx, args.pool, direction)
            if not pool:
                if direction == "east":
                    print(f'[WARN] {origin["name"]}: sin candidatas al Este', file=sys.stderr)
                continue
            row = table_distances(args.profile, origin, pool)
            kept = []
            if row is None:
                print(f'[WARN] {origin["name"]}: /table sin respuesta, se intenta ruta directa',
                      file=sys.stderr)
                kept = pool
            else:
                for item, dist in zip(pool, row[1:]):
                    if dist is None:
                        # El /table del demo devuelve nulos espurios (p. ej.
                        # Teresina→Salvador, verificado con /route: 1146 km).
                        # No se descarta aquí: la verificación la hace
                        # build_route, que con /route y el guardia SNAP_MAX_KM
                        # distingue "sin camino" de "enganchado al otro lado".
                        print(f'[WARN] {origin["name"]} → {item["city"]["name"]}: '
                              f'/table sin distancia, se verifica con /route',
                              file=sys.stderr)
                        kept.append(item)
                        continue
                    item["roadKm"] = float(dist)
                    kept.append(item)
                if not kept:
                    print(f'[WARN] {origin["name"]}: sin camino terrestre {direction}',
                          file=sys.stderr)
                    continue
            room = args.limit - len(built)
            if direction == "west":
                # El oeste es fallback: solo cubre el hueco hasta el mínimo.
                room = min(room, MIN_ROUTES_PER_ORIGIN - len(built))
            for item in kept[:max(0, room)]:
                dest = item["city"]
                route = build_route(args.profile, origin, dest, direction)
                if route is None:
                    unroutable_hits += 1
                    continue
                built.append(route)

        built.sort(key=lambda r: r["distanceKm"])
        built = built[:args.limit]
        if not built:
            origins_without += 1
            print(f'[WARN] {origin["name"]}: 0 rutas por tierra', file=sys.stderr)
        elif len(built) < MIN_ROUTES_PER_ORIGIN:
            print(f'[WARN] {origin["name"]}: solo {len(built)} rutas '
                  f'(< {MIN_ROUTES_PER_ORIGIN})', file=sys.stderr)
        routes.extend(built)
        done_origins.add(origin["name"])
        processed += 1

        # Volcado periódico cada 10 orígenes para no perder el lote.
        if processed % 10 == 0:
            meta = current_meta()
            write_output(args.out, meta, routes)
            print(f"[INFO] Volcado parcial: {processed} orígenes, {len(routes)} rutas")

    problems = validate_dataset(routes, args.limit)
    for p in problems:
        print(f"[ERROR] {p}", file=sys.stderr)
    if problems:
        print(f"[ERROR] {len(problems)} problemas de validación, no se escribe", file=sys.stderr)
        sys.exit(1)

    unique_origins = len({r["origin"] for r in routes})
    crossings = sum(1 for r in routes if crosses_antimeridian(r["geometry"]["coordinates"]))
    print(f"[INFO] {len(routes)} rutas de {unique_origins} orígenes "
          f"({processed} procesados en esta corrida)")
    print(f"[INFO] {origins_without} orígenes sin ruta en esta corrida, "
          f"{unroutable_hits} descartes sin camino (acumulado)")
    print(f"[INFO] {crossings} rutas cruzan el antimeridiano "
          f"(coordenadas normalizadas, las segmenta el consumidor)")

    if args.dry_run:
        print(f"[INFO] dry-run: no se escribe {args.out}")
        return

    meta = current_meta()
    write_output(args.out, meta, routes)
    print(f'[INFO] Guardadas {len(routes)} rutas ({meta["generated"]}) en {args.out}')


if __name__ == "__main__":
    main()
