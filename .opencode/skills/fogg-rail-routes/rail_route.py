#!/usr/bin/env python3
"""
fogg-rail-routes — hasta 5 rutas ferroviarias hacia el Este por ciudad
Proyecto eu.elarreglador.pf

- Para cada ciudad de locations.json toma sus 5 vecinas más próximas por
  círculo grande que cumplan la Regla del Este (0 < deltaLng <= 180) y
  consulta a OpenRailRouting (GraphHopper ferroviario de Geofabrik) cuáles
  tienen vía de tren con el perfil `non_tgv`.
- Si al origen le quedan menos de MIN_ROUTES_PER_ORIGIN rutas este, se
  completa con el pool oeste (5 vecinas hacia el Oeste, -180 <= deltaLng < 0):
  un jugador atrapado en una ciudad sin salida bloquearía la partida, así que
  la Regla del Este cede ante la jugabilidad. Cada ruta lleva `heading`.
- Respeta la política del servidor (instancia pública, experimental, sin SLA):
  como mucho 1 petición por segundo (pausa de 1,2 s), User-Agent identificable
  y backoff ante 429 (5 s, 15 s y 45 s).
- El servidor no ofrece geometría simplificada ni /matrix: cada candidata es
  un /route con `points_encoded=true`, la polilínea se decodifica con
  `decode_polyline5` y se simplifica con Douglas-Peucker (tolerancia en
  metros, no en grados) antes de escribir.
- Ancla cada geometría a las coordenadas de la ciudad en ambos extremos:
  GraphHopper devuelve el punto enganchado a la vía, no el centro urbano.
- Selecciona como mucho `limit` rutas por origen y persiste
  assets/data/rail_routes.json (reescritura completa; con --resume hace merge:
  conserva las rutas ya escritas y solo calcula los orígenes que falten).

Uso:
  python3 .opencode/skills/fogg-rail-routes/rail_route.py --dry-run
  python3 .opencode/skills/fogg-rail-routes/rail_route.py
  python3 .opencode/skills/fogg-rail-routes/rail_route.py --city "Lisboa" --dry-run
  python3 .opencode/skills/fogg-rail-routes/rail_route.py --only 20
  python3 .opencode/skills/fogg-rail-routes/rail_route.py --resume
  python3 .opencode/skills/fogg-rail-routes/rail_route.py --out /tmp/prueba.json
  python3 .opencode/skills/fogg-rail-routes/rail_route.py --pair "Londres|París"
  python3 .opencode/skills/fogg-rail-routes/rail_route.py --profile tgv_all --dry-run

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
RAIL_ROUTES_PATH = PROJECT_ROOT / "assets" / "data" / "rail_routes.json"
CACHE_ROOT = PROJECT_ROOT / "SENSIBLE" / ".cache" / "fogg-rail-routes"

# Cobertura de rutas (SPEC 008): módulo único compartido con las otras skills.
sys.path.insert(0, str(PROJECT_ROOT / "tools"))
import route_coverage  # noqa: E402  # type: ignore[import-not-found]

PROJECT = "eu.elarreglador.pf"
TOOL_NAME = "fogg-rail-routes"
SCHEMA_VERSION = "1.0.0"
ROUTER_SERVER = "https://routing.openrailrouting.org"
ENGINE = "OpenRailRouting (GraphHopper fork, Geofabrik)"
PROFILE_WHITELIST = ("non_tgv", "tgv_all", "all_tracks",
                     "all_tracks_1435", "tramtrain")
DEFAULT_PROFILE = "non_tgv"
USER_AGENT = "eu.elarreglador.pf/1.0"

MAX_EAST_DEG = 180  # tope del salto Este, evita la vuelta al mundo por el Oeste
DEFAULT_LIMIT = 5
DEFAULT_POOL = 5
MIN_ROUTES_PER_ORIGIN = 2  # mínimo de rutas de salida; por debajo se recurre al Oeste
MAX_DISTANCE_KM = 40000
LENGTH_TOLERANCE = 0.25  # |haversine_sum(geom) - snapKm(ori) - snapKm(dest)
                         #  - distanceKm| / distanceKm. Inicial 0,10 (SPEC 010
                         #  §5) ajustado a 0,25 tras la primera corrida completa
                         #  (2026-10-10): Kampala→Nairobi, vía montañosa de
                         #  Uganda–Kenia, recorta un 14,6 % (808,8 km vs 690,7
                         #  km de suma Haversine de la geometría simplificada con
                         #  SIMPLIFY_METERS=1500). Precedente: SPEC 006 §5 terminó
                         #  en el mismo 0,25 por cortes del `simplified` de OSRM
                         #  en alta montaña (hasta 22,7 %). Las rutas fantasma
                         #  siguen cayendo: desvían cientos % por el lado
                         #  positivo.
SIMPLIFY_METERS = 1500.0  # Douglas-Peucker en metros (decisión del Señor,
                          #  2026-10-10): cumple el criterio de aceptación de
                          #  "un orden de cientos" de vértices (Estambul→Bombay
                          #  pasa de ~30.900 a cientos) y mantiene el fichero
                          #  en el orden de pocos MB.
COORD_PRECISION = 5  # ~1 m, suficiente para visualizar
MIN_INTERVAL_S = 1.2  # cortesía: como mucho 1 petición por segundo
REQUEST_TIMEOUT_S = 60
RETRY_DELAYS = (5, 15, 45)  # backoff ante 429
SNAP_WARN_KM = 1.0  # avisa si el enganche queda lejos del centro

# Estado del cliente (cortesía + versión de los datos del servidor).
_last_request_ts = 0.0
_rail_data_timestamp: str | None = None


# ---------------------------------------------------------------------------
# Helpers geodésicos (mismo modelo que fogg-land-routes)
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
# Cliente HTTP con caché y cortesía
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


def router_get(url: str, profile: str) -> dict | None:
    """GET a OpenRailRouting con caché cruda, pausa de cortesía y reintentos.

    Devuelve el JSON parseado o None en fallo irrecuperable (429 agotado,
    timeout, respuesta inválida). La caché guarda la respuesta cruda indexada
    por sha1(url); la segunda llamada idéntica no toca la red. Captura
    `info.road_data_timestamp` para delatar un artefacto viejo.
    """
    global _last_request_ts, _rail_data_timestamp
    cache = _cache_path(profile, url)
    if cache.exists():
        try:
            with open(cache, encoding="utf-8") as f:
                payload = json.load(f)
            # Un acierto de caché también aporta la versión de datos.
            dv = payload.get("info", {}).get("road_data_timestamp")
            if isinstance(dv, str) and _rail_data_timestamp is None:
                _rail_data_timestamp = dv
            return payload
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
            dv = payload.get("info", {}).get("road_data_timestamp")
            if isinstance(dv, str) and _rail_data_timestamp is None:
                _rail_data_timestamp = dv
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
            # Los errores deterministas (400) llevan un JSON tipo
            # {"message": "Cannot find point ..."}, determinista por versión de
            # datos: se devuelven como payload para que build_route los
            # clasifique (PointNotFound / NoRoute) y se cachean para que la
            # regeneración no vuelva a la red.
            if e.code != 429:
                body = e.read().decode("utf-8", errors="replace") or ""
                try:
                    err_payload = json.loads(body)
                except Exception:
                    err_payload = None
                if isinstance(err_payload, dict) and isinstance(err_payload.get("message"), str):
                    cache.parent.mkdir(parents=True, exist_ok=True)
                    with open(cache, "w", encoding="utf-8") as f:
                        f.write(body)
                    return err_payload
            print(f"[WARN] OpenRailRouting {e.code} en {url}", file=sys.stderr)
            return None
        except (urllib.error.URLError, TimeoutError, OSError) as e:
            _last_request_ts = time.monotonic()
            last_code = "timeout" if isinstance(e, TimeoutError) else "URLError"
            print(f"[WARN] OpenRailRouting sin respuesta en {url} ({e})", file=sys.stderr)
            return None
        except (json.JSONDecodeError, ValueError) as e:
            _last_request_ts = time.monotonic()
            print(f"[WARN] OpenRailRouting respuesta inválida en {url} ({e})",
                  file=sys.stderr)
            return None
    print(f"[WARN] OpenRailRouting 429 agotado en {url} (código {last_code})",
          file=sys.stderr)
    return None


# ---------------------------------------------------------------------------
# Pool de candidatas y fallback al Oeste
# ---------------------------------------------------------------------------

def build_pool(cities, origin_idx: int, pool_size: int, direction: str = "east") -> list[dict]:
    """Las `pool_size` ciudades más cercanas por círculo grande hacia el Este
    (`direction="east"`) u Oeste (`direction="west"`).

    Filtra con 0 < delta <= MAX_EAST_DEG (o -MAX_EAST_DEG <= delta < 0) sobre
    la ciudad (no sobre el enganche), excluye el propio nombre, ordena por
    Haversine y corta. Sin /matrix: el servidor no ofrece tabla de distancias.
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


# ---------------------------------------------------------------------------
# Polilínea: decodificación (precision 5) y simplificación Douglas-Peucker
# ---------------------------------------------------------------------------

def decode_polyline5(encoded: str) -> list[list[float]]:
    """Polilínea Google con precisión 5 (factor 1e5), como la sirve
    GraphHopper con `points_encoded=true`. Devuelve pares [lng, lat]."""
    if not encoded:
        return []
    points = []
    index = 0
    lat = 0
    lng = 0
    length = len(encoded)
    while index < length:
        result = 0
        shift = 0
        while True:
            b = ord(encoded[index]) - 63
            index += 1
            result |= (b & 0x1f) << shift
            shift += 5
            if not (b & 0x20):
                break
        lat += ~(result >> 1) if result & 1 else (result >> 1)
        result = 0
        shift = 0
        while True:
            b = ord(encoded[index]) - 63
            index += 1
            result |= (b & 0x1f) << shift
            shift += 5
            if not (b & 0x20):
                break
        lng += ~(result >> 1) if result & 1 else (result >> 1)
        points.append([lng / 1e5, lat / 1e5])
    return points


_METERS_PER_DEG = 111320.0  # aproximación esférica, suficiente para el DP


def _point_segment_dist_m(p, a, b) -> float:
    """Distancia perpendicular punto-segmento en metros, plano local
    equirectangular anclado en la latitud del punto de prueba `p`."""
    cos_lat = math.cos(math.radians(p[1]))

    def to_xy(pt):
        return (pt[0] * _METERS_PER_DEG * cos_lat, pt[1] * _METERS_PER_DEG)

    px, py = to_xy(p)
    ax, ay = to_xy(a)
    bx, by = to_xy(b)
    dx, dy = bx - ax, by - ay
    if dx == 0 and dy == 0:
        return math.hypot(px - ax, py - ay)
    t = ((px - ax) * dx + (py - ay) * dy) / (dx * dx + dy * dy)
    t = max(0.0, min(1.0, t))
    cx, cy = ax + t * dx, ay + t * dy
    return math.hypot(px - cx, py - cy)


def simplify_dp(coords: list, tol_m: float) -> list:
    """Douglas-Peucker iterativo con tolerancia en metros, dedup previo/posterior.

    `coords` son pares [lng, lat]. El plano local se re-ancla por segmento en
    la latitud del vértice de prueba, así que la tolerancia es esférica en la
    práctica (no en grados).
    """
    deduped = []
    for c in coords:
        if not deduped or deduped[-1] != c:
            deduped.append(c)
    if len(deduped) <= 2:
        return deduped
    keep = {0, len(deduped) - 1}
    stack = [(0, len(deduped) - 1)]
    while stack:
        start, end = stack.pop()
        a, b = deduped[start], deduped[end]
        max_d = 0.0
        max_i = start
        for i in range(start + 1, end):
            d = _point_segment_dist_m(deduped[i], a, b)
            if d > max_d:
                max_d, max_i = d, i
        if max_d > tol_m:
            keep.add(max_i)
            stack.append((start, max_i))
            stack.append((max_i, end))
    simplified = [deduped[i] for i in sorted(keep)]
    out = []
    for c in simplified:
        if not out or out[-1] != c:
            out.append(c)
    return out


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

    Nunca sustituye un vértice: la vía de GraphHopper se conserva entera y solo
    se le añade el tramo ciudad↔vía en cada extremo. Si la ciudad ya coincide
    con el vértice vecino (misma posición redondeada a `COORD_PRECISION`) no se
    duplica, que un segmento de longitud cero rompe los mapas.
    """
    start = city_vertex(origin)
    end = city_vertex(dest)
    if coordinates[0] != start:
        coordinates = [start] + coordinates
    if coordinates[-1] != end:
        coordinates = coordinates + [end]
    return coordinates


def _rail_point(vertex: list, city: dict) -> dict:
    """Enganche a la vía: primer/último vértice + distancia centro→vía.

    Sin `name`: GraphHopper no devuelve el nombre de la estación en /route
    (acuerdo del Señor, SPEC 010 §6).
    """
    lng, lat = float(vertex[0]), float(vertex[1])
    snap = haversine(float(city["lat"]), float(city["lng"]), lat, normalize_lng(lng))
    return {
        "lat": round(lat, COORD_PRECISION),
        "lng": round(normalize_lng(lng), COORD_PRECISION),
        "snapKm": round(snap, 1),
    }


def length_ok(route: dict) -> bool:
    """Invariante de longitud tolerada (SPEC 010 §5).

    La suma Haversine de la geometría incluye los dos tramos de anclaje
    (ciudad→vía); se descuentan sus `snapKm` antes de comparar con
    `distanceKm` (que es paths[0].distance de GraphHopper, nunca recalculado).
    """
    dist = route["distanceKm"]
    hsum = haversine_sum(route["geometry"]["coordinates"])
    snaps = route["railOrigin"]["snapKm"] + route["railDest"]["snapKm"]
    if dist and abs(hsum - snaps - dist) / dist > LENGTH_TOLERANCE:
        print(f'[SKIP] {route["origin"]} → {route["destination"]}: distancia '
              f'fuera de ±{LENGTH_TOLERANCE * 100:.0f}% '
              f'(distanceKm {dist:.1f} vs vía {hsum - snaps:.1f} km)',
              file=sys.stderr)
        return False
    return True


def build_route(profile: str, origin: dict, dest: dict, direction: str = "east") -> dict | None:
    """Una ruta /route con points_encoded=true, simplificada y anclada.

    Devuelve el dict de ruta listo para persistir, o None con el motivo
    registrado ([SKIP] PointNotFound / NoRoute / 429 / timeout / NoSegment).
    `direction` se persiste como `heading` (east|west).
    """
    url = (f"{ROUTER_SERVER}/route?"
           f"point={float(origin['lat'])},{float(origin['lng'])}&"
           f"point={float(dest['lat'])},{float(dest['lng'])}&"
           f"profile={profile}&points_encoded=true")
    payload = router_get(url, profile)
    if payload is None:
        print(f"[SKIP] {origin['name']} → {dest['name']}: sin respuesta (timeout o 429)",
              file=sys.stderr)
        return None
    message = payload.get("message") or ""
    if "paths" not in payload or not payload.get("paths"):
        code = "PointNotFound" if "Cannot find point" in message else "NoRoute"
        if message:
            code = f"{code} ({message})"
        print(f"[SKIP] {origin['name']} → {dest['name']}: {code}", file=sys.stderr)
        return None
    best = payload["paths"][0]
    try:
        distance_m = float(best["distance"])
        time_ms = float(best["time"])
    except Exception:
        print(f"[SKIP] {origin['name']} → {dest['name']}: NoSegment", file=sys.stderr)
        return None
    if not (0 < distance_m / 1000.0 < MAX_DISTANCE_KM):
        print(f"[SKIP] {origin['name']} → {dest['name']}: TooBig", file=sys.stderr)
        return None
    # Con points_encoded=true, paths[0].points ES la cadena de polilínea
    # (fallback al objeto {encoded} por si el servidor cambia el formato).
    points = best.get("points") or ""
    encoded = points if isinstance(points, str) else (points.get("encoded") or "")
    raw = decode_polyline5(encoded)
    if len(raw) < 2:
        print(f"[SKIP] {origin['name']} → {dest['name']}: NoSegment", file=sys.stderr)
        return None
    rail_origin = _rail_point(raw[0], origin)
    rail_dest = _rail_point(raw[-1], dest)
    for rail, city in ((rail_origin, origin), (rail_dest, dest)):
        if rail["snapKm"] > SNAP_WARN_KM:
            print(f'[WARN] {city["name"]}: enganche a vía a {rail["snapKm"]:.1f} km',
                  file=sys.stderr)
    coordinates = [
        [round(normalize_lng(float(x)), COORD_PRECISION), round(float(y), COORD_PRECISION)]
        for x, y in raw
    ]
    coordinates = simplify_dp(coordinates, SIMPLIFY_METERS)
    coordinates = anchor_to_cities(coordinates, origin, dest)
    return {
        "origin": origin["name"],
        "originLat": origin["lat"],
        "originLng": origin["lng"],
        "destination": dest["name"],
        "destinationLat": dest["lat"],
        "destinationLng": dest["lng"],
        "distanceKm": round(distance_m / 1000.0, 1),
        "durationHours": round(time_ms / 3_600_000.0, 1),
        "heading": direction,
        "railOrigin": rail_origin,
        "railDest": rail_dest,
        "geometry": {"type": "LineString", "coordinates": coordinates},
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

        distance = route.get("distanceKm")
        if not isinstance(distance, (int, float)) or not (0 < distance < MAX_DISTANCE_KM):
            problems.append(f"distanceKm fuera de rango en {key}: {distance}")
        duration = route.get("durationHours")
        if not isinstance(duration, (int, float)) or not (duration > 0):
            problems.append(f"durationHours fuera de rango en {key}: {duration}")
        for rail_key in ("railOrigin", "railDest"):
            rail = route.get(rail_key) or {}
            if not all(k in rail for k in ("lat", "lng", "snapKm")):
                problems.append(f"{rail_key} incompleto en {key}")
        coords = route["geometry"]["coordinates"]
        if route["geometry"].get("type") != "LineString":
            problems.append(f"geometry.type distinto de LineString en {key}")
        if len(coords) < 2:
            problems.append(f"geometría con menos de 2 vértices en {key}")
            continue
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
        # Regla del Este sobre la ciudad, no sobre el enganche (SPEC 010 §6),
        # salvo heading="west" (fallback de origen, igual que SPEC 006 §12).
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
        if not length_ok(route):
            problems.append(f"longitud fuera de tolerancia en {key}")

    for origin, group in by_origin.items():
        # limitPerOrigin acota las rutas normales; las `explicit` (pares
        # curados a mano) no cuentan para el límite, pero sí para la cobertura.
        normal = [r for r in group if not r.get("explicit")]
        if len(normal) > limit:
            problems.append(f"{origin} tiene {len(normal)} rutas, máximo {limit}")
        distances = [r["distanceKm"] for r in group]
        if distances != sorted(distances):
            problems.append(f"{origin} no ordenado por distanceKm ascendente")

    # SPEC 010 §3.3: la unión pasa a ser mar ∪ tierra ∪ raíl; el raíl que se
    # valida es el de memoria (el fichero aún no está escrito).
    sea = route_coverage.load_routes(route_coverage.SEA_ROUTES_PATH)
    car = route_coverage.load_routes(route_coverage.CAR_ROUTES_PATH)
    problems += route_coverage.coverage_problems(sea, car, routes)
    return problems


def build_meta(origins_total: int, routes: list, unroutable: int,
               without_route: int, limit: int, pool: int, profile: str) -> dict:
    crossings = sum(1 for r in routes if crosses_antimeridian(r["geometry"]["coordinates"]))
    # Las rutas `explicit` (pares curados a mano) no son fallback de
    # jugabilidad: no cuentan para la nota del Oeste.
    west = [r for r in routes if r.get("heading") == "west" and not r.get("explicit")]
    meta = {
        "project": PROJECT,
        "name": "Fogg Rail Routes — Herencia de Phoebe",
        "version": SCHEMA_VERSION,
        "generated": date.today().isoformat(),
        "tool": TOOL_NAME,
        "profile": profile,
        "routerServer": ROUTER_SERVER,
        "engine": ENGINE,
        "dataTimestamp": _rail_data_timestamp or "unknown",
        "units": "km",
        "limitPerOrigin": limit,
        "minRoutesPerOrigin": MIN_ROUTES_PER_ORIGIN,
        "maxEastDeg": MAX_EAST_DEG,
        "candidatePool": pool,
        "simplifyMeters": SIMPLIFY_METERS,
        "origins": origins_total,
        "routes": len(routes),
        "originsWithoutRoute": without_route,
        "unroutableCities": unroutable,
        "crossesAntimeridian": crossings,
        "eastRule": "heading east: 0 < deltaLng(cityDest - cityOrigin) <= 180 (desenrollado); "
                    "heading west: -180 <= deltaLng < 0, solo como fallback cuando un origen "
                    "tiene menos de minRoutesPerOrigin rutas al Este",
        "poolRule": ("los pool candidatos más cercanos por círculo grande dentro de "
                     "maxEastDeg en cada dirección; se descartan los que OpenRailRouting "
                     "no puede enrutar; el pool oeste solo se consulta si el este no llega "
                     "a minRoutesPerOrigin rutas"),
        "geometry": ("LineString [lng,lat] de ciudad a ciudad: el primer y el último "
                     "vértice son las coordenadas de la ciudad de locations.json y entre "
                     "medias va la vía de OpenRailRouting decodificada (points_encoded) "
                     "y simplificada con Douglas-Peucker"),
        "distanceNote": ("distanceKm es paths[0].distance de GraphHopper /1000; "
                         "durationHours es paths[0].time /3.600.000. Ninguno se "
                         "recalcula desde la geometría"),
        "attribution": ("© OpenStreetMap contributors (ODbL); routing courtesy of "
                        "OpenRailRouting (Geofabrik) / GraphHopper"),
        "source": "OpenRailRouting demo (non_tgv) + GeoNames cities15000",
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
    """Rutas ya escritas (para --resume). Devuelve (rutas, orígenes, meta previo)."""
    if not out_path.exists():
        return [], set(), {}
    try:
        with open(out_path, encoding="utf-8") as f:
            data = json.load(f)
        routes = data.get("routes") or []
        origins = {r["origin"] for r in routes if "origin" in r}
        meta = data.get("meta") or {}
        return routes, origins, meta
    except Exception as e:
        print(f"[WARN] No se pudo leer {out_path} para --resume ({e})", file=sys.stderr)
        return [], set(), {}


# ---------------------------------------------------------------------------
# Pares curados a mano (--pair)
# ---------------------------------------------------------------------------

def insert_route(routes: list, route: dict) -> bool:
    """Inserta una ruta (explicit o no) sin tocar las existentes.

    Mantiene el grupo de origen contiguo y ordenado por distanceKm ascendente
    (invariante de validate_dataset).
    """
    if any(r["origin"] == route["origin"] and r["destination"] == route["destination"]
           for r in routes):
        print(f'[WARN] {route["origin"]} → {route["destination"]}: ya existe, '
              f'se omite', file=sys.stderr)
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


def add_pairs(args) -> None:
    """Pares curados a mano (`--pair ORIGEN|DESTINO`, repeatable).

    Fuerza una ruta explícita entre ciudades aunque el origen ya tenga sus 5
    rutas normales del lote: la ruta se marca `explicit: true` y no cuenta
    para `limitPerOrigin`, así el dataset no pierde estas parejas en futuras
    regeneraciones. Reutiliza `build_route` (rate limit, anclaje y guardias)
    y hace merge sobre el fichero existente.
    """
    _, cities, _ = load_locations()
    routes, _, prev_meta = load_existing(args.out)
    if not routes:
        print(f"[ERROR] No hay rutas previas en {args.out}: los pares explícitos "
              f"se añaden sobre el lote existente (la validación de cobertura "
              f"exige el lote completo)", file=sys.stderr)
        sys.exit(1)
    print(f"[INFO] --pair: {len(routes)} rutas previas en {args.out}")
    name_to_city = {}
    for c in cities:
        name_to_city.setdefault(normalize(c.get("name") or ""), c)
        if c.get("asciiname"):
            name_to_city.setdefault(normalize(c["asciiname"]), c)

    added = 0
    for raw in args.pair:
        for sep in ("|", "->", "→", " - "):
            if sep in raw:
                origin_name, dest_name = (p.strip() for p in raw.split(sep, 1))
                break
        else:
            print(f'[ERROR] --pair inválido {raw!r}: use "Origen|Destino"',
                  file=sys.stderr)
            sys.exit(1)
        origin = name_to_city.get(normalize(origin_name))
        dest = name_to_city.get(normalize(dest_name))
        if origin is None or dest is None:
            print(f'[WARN] --pair {raw}: ciudad no encontrada, se omite',
                  file=sys.stderr)
            continue
        if origin["name"] == dest["name"]:
            print(f'[WARN] --pair {raw}: origen == destino, se omite',
                  file=sys.stderr)
            continue
        if any(r["origin"] == origin["name"] and r["destination"] == dest["name"]
               for r in routes):
            print(f'[WARN] {origin["name"]} → {dest["name"]}: ya existe, se omite',
                  file=sys.stderr)
            continue
        delta = eastward_delta(float(origin["lng"]), float(dest["lng"]))
        if delta == 0:
            print(f'[WARN] {origin["name"]} → {dest["name"]}: misma longitud, se omite',
                  file=sys.stderr)
            continue
        direction = "east" if 0 < delta <= MAX_EAST_DEG else "west"
        route = build_route(args.profile, origin, dest, direction)
        if route is None:
            continue  # build_route ya registra el motivo ([SKIP])
        if not length_ok(route):
            continue
        route["explicit"] = True
        if insert_route(routes, route):
            added += 1
            print(f'[INFO] {origin["name"]} → {dest["name"]} '
                  f'({direction}, {route["distanceKm"]} km): par explícito añadido')
    print(f"[INFO] {added} pares explícitos añadidos de {len(args.pair)} solicitados")

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
    meta["explicitRoutes"] = sum(1 for r in routes if r.get("explicit"))
    if args.dry_run:
        print(f"[INFO] dry-run: no se escribe {args.out}")
        return
    write_output(args.out, meta, routes)
    print(f'[INFO] Guardadas {len(routes)} rutas '
          f'({meta["explicitRoutes"]} explícitas) en {args.out}')


# ---------------------------------------------------------------------------
# Orquestación
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(
        description=(
            "Fogg Rail Routes — hasta 5 rutas ferroviarias hacia el Este "
            f"(OpenRailRouting {ROUTER_SERVER}, 1 petición/s, perfil "
            f"{DEFAULT_PROFILE})"
        ),
        formatter_class=argparse.RawTextHelpFormatter,
    )
    parser.add_argument("--profile", default=DEFAULT_PROFILE,
                        help=f'Perfil ferroviario (default {DEFAULT_PROFILE}); '
                             f'lista blanca: {", ".join(PROFILE_WHITELIST)}')
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
    parser.add_argument("--pair", action="append", default=[], metavar='"ORIGEN|DESTINO"',
                        help="Par explícito a forzar (repetible). Se marca `explicit: true` "
                             "y no cuenta para el límite de 5 rutas por origen")
    parser.add_argument("--dry-run", action="store_true",
                        help="Detalla el resultado sin escribir disco")
    parser.add_argument("--out", type=Path, default=RAIL_ROUTES_PATH,
                        help=f"Ruta de salida (default {RAIL_ROUTES_PATH})")
    args = parser.parse_args()

    if args.profile not in PROFILE_WHITELIST:
        print(f"[ERROR] --profile {args.profile!r} no soportado; lista blanca: "
              f'{", ".join(PROFILE_WHITELIST)}; no se escribe ningún fichero',
              file=sys.stderr)
        sys.exit(1)
    if args.limit <= 0:
        print("[ERROR] --limit debe ser >0", file=sys.stderr)
        sys.exit(1)
    if args.pool <= 0:
        print("[ERROR] --pool debe ser >0", file=sys.stderr)
        sys.exit(1)

    if args.pair:
        add_pairs(args)
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
            room = args.limit - len(built)
            if direction == "west":
                # El oeste es fallback: solo cubre el hueco hasta el mínimo.
                room = min(room, MIN_ROUTES_PER_ORIGIN - len(built))
            for item in pool[:max(0, room)]:
                dest = item["city"]
                route = build_route(args.profile, origin, dest, direction)
                if route is None:
                    unroutable_hits += 1
                    continue
                if not length_ok(route):
                    unroutable_hits += 1
                    continue
                built.append(route)
                if len(built) >= args.limit:
                    break

        built.sort(key=lambda r: r["distanceKm"])
        built = built[:args.limit]
        if not built:
            origins_without += 1
            print(f'[WARN] {origin["name"]}: 0 rutas por ferrocarril', file=sys.stderr)
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