#!/usr/bin/env python3
"""
fogg-sea-routes — hasta 5 rutas marítimas más cortas hacia el Este por puerto
Proyecto eu.elarreglador.pf

- Resuelve el puerto de cada ciudad de locations.json: nodo de la malla marítima
  (distancia al mar) + puerto WPI que devuelve searoute (include_ports)
- Descarta las ciudades sin mar a <= THRESHOLD_KM (el WPI no sirve como filtro:
  Denver, Kansas City o Harare son puertos fluviales a 0 km del centro)
- De los puertos candidatos conserva solo los cuyo puerto queda al Este del puerto
  origen, desenrollado: 0 < deltaLng <= 180
- Ancla cada geometría a las coordenadas de la ciudad en ambos extremos: searoute
  devuelve la malla marítima, cuyo primer y último vértice son nodos de mar
- Selecciona las `limit` rutas más cortas por distancia marítima y persiste
  assets/data/sea_routes.json (reescritura completa, no merge)

Uso:
  python3 .opencode/skills/fogg-sea-routes/sea_route.py --dry-run
  python3 .opencode/skills/fogg-sea-routes/sea_route.py
  python3 .opencode/skills/fogg-sea-routes/sea_route.py --city "Lisboa" --dry-run
  python3 .opencode/skills/fogg-sea-routes/sea_route.py --out /tmp/prueba.json

Stdlib + searoute==1.6.0
"""
from __future__ import annotations

import argparse
import json
import math
import sys
import unicodedata
from datetime import date
from pathlib import Path
from typing import Any

# ---------------------------------------------------------------------------
# Rutas y constantes
# ---------------------------------------------------------------------------
PROJECT_ROOT = Path(__file__).resolve().parents[3]  # PF/
JSON_PATH = PROJECT_ROOT / "assets" / "data" / "locations.json"
SEA_ROUTES_PATH = PROJECT_ROOT / "assets" / "data" / "sea_routes.json"

PROJECT = "eu.elarreglador.pf"
TOOL_NAME = "fogg-sea-routes"
SCHEMA_VERSION = "3.0.0"
SEAROUTE_VERSION = "1.6.0"

THRESHOLD_KM = 10  # ciudad -> mar; por encima la ciudad no es un puerto
MAX_EAST_DEG = 180  # tope del salto Este, evita la vuelta al mundo por el Oeste
DEFAULT_LIMIT = 5
MAX_DISTANCE_KM = 40000
LENGTH_TOLERANCE = 0.20  # |haversine_sum - distanceKm| / distanceKm
COORD_PRECISION = 5  # ~1 m, suficiente para un visualizar
PROBE_DEG = 0.7  # desplazamiento del punto sonda para forzar un enrutado

# ---------------------------------------------------------------------------
# Helpers geodésicos
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
    """Desplazamiento Este de `lng_from` a `lng_to`, desenrollado en (-180, 180]."""
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
            float(c["lat"]); float(c["lng"])
        except Exception:
            print(f"[ERROR] lat/lng no numéricos: {c}", file=sys.stderr)
            sys.exit(1)
    # calcular lng_u desenrollado (offset+=360 si curr <= prev)
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
# searoute
# ---------------------------------------------------------------------------

def graph_size(graph: Any) -> int:
    """Número de nodos de un grafo de searoute (Graph no está tipado en el paquete)."""
    return int(graph.number_of_nodes())


def load_searoute():
    """Devuelve (módulo, red de la malla, red de puertos). Las redes se construyen una vez."""
    try:
        import searoute
    except ImportError as e:
        print(
            f"[ERROR] searoute no instalado: {e}. "
            "Ejecute: pip install -r .opencode/skills/fogg-sea-routes/requirements.txt",
            file=sys.stderr,
        )
        sys.exit(1)
    return searoute, searoute.setup_M(), searoute.setup_P()


def probe_lng_of(lng: float) -> float:
    """Punto sonda al Este de la ciudad, replegado si se sale del rango."""
    probe = lng + PROBE_DEG
    return probe if probe <= 179.0 else lng - PROBE_DEG


def sea_snap_km(sr, M, P, city) -> float:
    """Distancia Haversine de la ciudad al nodo de la malla marítima más cercano."""
    lng, lat = float(city["lng"]), float(city["lat"])
    feature = sr.searoute([lng, lat], [probe_lng_of(lng), lat],
                          units="km", algorithm="astar", M=M, P=P)
    first_lng, first_lat = feature["geometry"]["coordinates"][0]
    return haversine(lat, lng, first_lat, first_lng)


def resolve_port(sr, M, P, city, sea_km: float) -> dict:
    """Puerto WPI de la ciudad (código, nombre, país) más la distancia al mar."""
    lng, lat = float(city["lng"]), float(city["lat"])
    feature = sr.searoute([lng, lat], [probe_lng_of(lng), lat], units="km",
                          include_ports=True, algorithm="astar", M=M, P=P)
    port = feature.properties.get("port_origin") or {}
    return {
        "city": city["name"],
        "lat": lat,
        "lng": lng,
        "seaKm": sea_km,
        "port": {
            "code": port.get("port"),
            "name": port.get("name"),
            # El WPI escribe los países con guiones bajos ("French_polynesia"); el código
            # es la clave de búsqueda, el país es solo etiqueta de interfaz.
            "country": (port.get("cty") or "").replace("_", " "),
            "lat": round(float(port["y"]), COORD_PRECISION),
            "lng": round(normalize_lng(float(port["x"])), COORD_PRECISION),
        },
    }


# ---------------------------------------------------------------------------
# Geometría de la ruta
# ---------------------------------------------------------------------------

def city_vertex(city) -> list[float]:
    """Coordenadas de la ciudad como primer/último vértice de la LineString.

    `searoute` devuelve la malla marítima: su primer y último vértice son nodos
    de esa malla, no la ciudad. Se anteponen/posponen las coordenadas del
    catálogo para que la polilínea arranque y termine donde lo espera el
    consumidor. `normalize_lng` es defensivo: `load_locations` no acota `lng`.
    """
    return [
        round(normalize_lng(float(city["lng"])), COORD_PRECISION),
        round(float(city["lat"]), COORD_PRECISION),
    ]


def anchor_to_cities(coordinates, origin, dest) -> list:
    """Antepone la ciudad origen y pospone la ciudad destino.

    Nunca sustituye un vértice: el camino que resuelve la malla se conserva
    entero y solo se le añade el tramo ciudad↔puerto en cada extremo. Si la
    ciudad ya coincide con el vértice vecino (misma posición redondeada a
    `COORD_PRECISION`, p. ej. Macau) no se duplica, que un segmento de longitud
    cero rompe los mapas.
    """
    start = city_vertex(origin)
    end = city_vertex(dest)
    if coordinates[0] != start:
        coordinates = [start] + coordinates
    if coordinates[-1] != end:
        coordinates = coordinates + [end]
    return coordinates


# ---------------------------------------------------------------------------
# Selección de rutas
# ---------------------------------------------------------------------------

def select_routes(sr, M, P, origin, ports, limit, verbose=False):
    """Rutas marítimas más cortas hacia el Este. `ports` es la lista ya resuelta."""
    o_lng, o_lat = origin["port"]["lng"], origin["port"]["lat"]
    candidates = []
    for dest in ports:
        if dest["city"] == origin["city"]:
            continue
        # Regla del Este sobre el puerto, no sobre la ciudad
        delta = eastward_delta(o_lng, dest["port"]["lng"])
        if not (0 < delta <= MAX_EAST_DEG):
            continue
        gc_km = haversine(o_lat, o_lng, dest["port"]["lat"], dest["port"]["lng"])
        candidates.append((gc_km, dest))
    candidates.sort(key=lambda item: item[0])

    selected = []
    for gc_km, dest in candidates:
        # Poda por cota inferior: la distancia marítima nunca es menor que la de
        # círculo grande, así que en cuanto gc supera la 5ª válida no puede entrar.
        if len(selected) >= limit and gc_km > selected[-1][0]:
            break
        try:
            feature = sr.searoute(
                [origin["lng"], origin["lat"]],
                [dest["lng"], dest["lat"]],
                units="km",
                include_ports=True,
                algorithm="astar",
                M=M,
                P=P,
            )
        except Exception as e:
            print(f"[SKIP] {origin['city']} -> {dest['city']} searoute error: {e}", file=sys.stderr)
            continue
        distance = feature.properties.get("length")
        if not isinstance(distance, (int, float)) or not (0 < distance < MAX_DISTANCE_KM):
            continue
        # searoute entrega el marco desenrollado y puede salirse de [-180, 180];
        # se dobla cada vértice y el salto 179 -> -179 lo segmenta el consumidor.
        coordinates = [
            [round(normalize_lng(float(x)), COORD_PRECISION), round(float(y), COORD_PRECISION)]
            for x, y in feature["geometry"]["coordinates"]
        ]
        if len(coordinates) < 2:
            continue
        # La malla empieza y acaba en el nodo marino, no en la ciudad: se ancla
        # a las coordenadas del catálogo sin tocar el camino intermedio.
        coordinates = anchor_to_cities(coordinates, origin, dest)
        selected.append((float(distance), dest, coordinates))
        if verbose:
            print(f"    {dest['city']:<24} {distance:9.1f} km  gc {gc_km:8.1f} km")

    selected.sort(key=lambda item: item[0])
    return selected[:limit]


def build_route(origin, dest, distance_km, coordinates) -> dict:
    return {
        "origin": origin["city"],
        "originLat": origin["lat"],
        "originLng": origin["lng"],
        "destination": dest["city"],
        "destinationLat": dest["lat"],
        "destinationLng": dest["lng"],
        "distanceKm": round(distance_km, 1),
        "portOrigin": dict(origin["port"], seaKm=round(origin["seaKm"], 1)),
        "portDest": dict(dest["port"], seaKm=round(dest["seaKm"], 1)),
        "geometry": {"type": "LineString", "coordinates": coordinates},
    }


# ---------------------------------------------------------------------------
# Validación y persistencia
# ---------------------------------------------------------------------------

def crosses_antimeridian(coordinates) -> bool:
    """True si algún vértice salta de un meridiano al otro."""
    for i in range(len(coordinates) - 1):
        if abs(coordinates[i + 1][0] - coordinates[i][0]) > 180:
            return True
    return False


def validate_dataset(routes, limit) -> list[str]:
    """Invariantes del dataset. Lista vacía = correcto."""
    problems = []
    seen = set()
    by_origin = {}
    for route in routes:
        key = f'{route["origin"]}::{route["destination"]}'
        if key in seen:
            problems.append(f"duplicado {key}")
        seen.add(key)
        if route["origin"] == route["destination"]:
            problems.append(f"origen == destino {key}")
        by_origin.setdefault(route["origin"], []).append(route)

        distance = route["distanceKm"]
        if not isinstance(distance, (int, float)) or not (0 < distance < MAX_DISTANCE_KM):
            problems.append(f"distanceKm fuera de rango en {key}: {distance}")
        coords = route["geometry"]["coordinates"]
        if len(coords) < 2:
            problems.append(f"geometría con menos de 2 vértices en {key}")
            continue
        # La geometría arranca y termina en la ciudad, no en el nodo de la malla.
        # `originLat/originLng` conservan la precisión de locations.json, así que
        # la comparación va contra el mismo redondeo que aplica `city_vertex`.
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
        delta = eastward_delta(route["portOrigin"]["lng"], route["portDest"]["lng"])
        if not (0 < delta <= MAX_EAST_DEG):
            problems.append(f"Regla del Este incumplida en {key}: delta {delta:.3f}º")
        hsum = haversine_sum(coords)
        if distance and abs(hsum - distance) / distance > LENGTH_TOLERANCE:
            problems.append(
                f"distanceKm {distance:.1f} vs haversine {hsum:.1f} en {key} "
                f"(±{LENGTH_TOLERANCE * 100:.0f}%)"
            )

    for origin, group in by_origin.items():
        if len(group) > limit:
            problems.append(f"{origin} tiene {len(group)} rutas, máximo {limit}")
        distances = [r["distanceKm"] for r in group]
        if distances != sorted(distances):
            problems.append(f"{origin} no ordenado por distanceKm ascendente")
    return problems


def build_meta(origins_total, routes_count, cities_without_port, crossings, limit) -> dict:
    return {
        "project": PROJECT,
        "name": "Fogg Sea Routes — Herencia de Phoebe",
        "version": SCHEMA_VERSION,
        "generated": date.today().isoformat(),
        "tool": TOOL_NAME,
        "searoute": SEAROUTE_VERSION,
        "units": "km",
        "thresholdKm": THRESHOLD_KM,
        "maxEastDeg": MAX_EAST_DEG,
        "limitPerOrigin": limit,
        "origins": origins_total,
        "routes": routes_count,
        "citiesWithoutPort": cities_without_port,
        "crossesAntimeridian": crossings,
        "eastRule": "0 < deltaLng(portDest - portOrigin) <= 180 (desenrollado)",
        "geometry": "LineString [lng,lat] de ciudad a ciudad: el primer y el último "
                    "vértice son las coordenadas de la ciudad de locations.json y entre "
                    "medias va la malla marítima de searoute. Siempre en [-180,180]; al "
                    "cruzar el antimeridiano los vértices saltan de 179 a -179 y el "
                    "consumidor debe segmentar (splitAntimeridian / polylineSegments)",
        "distanceNote": "distanceKm es properties.length de searoute (nodo de malla a "
                        "nodo de malla) y NO incluye los tramos ciudad-puerto de los "
                        "extremos, de hasta ~15.7 km (Portsmouth-Cowes, Isla de Wight)",
        "source": "searoute (avoid land) + GeoNames cities15000",
    }


def write_output(out_path, meta, routes) -> None:
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


# ---------------------------------------------------------------------------
# Orquestación
# ---------------------------------------------------------------------------

def resolve_ports(sr, M, P, cities, indices, verbose=False):
    """Separa puertos válidos (mar a <= THRESHOLD_KM) del resto."""
    ports = []
    rejected = []
    for idx in indices:
        city = cities[idx]
        try:
            sea_km = sea_snap_km(sr, M, P, city)
        except Exception as e:
            print(f"[WARN] {city['name']}: no se pudo medir el mar ({e})", file=sys.stderr)
            rejected.append((city["name"], float("inf")))
            continue
        if sea_km > THRESHOLD_KM:
            rejected.append((city["name"], sea_km))
            continue
        ports.append(resolve_port(sr, M, P, city, sea_km))
        if verbose:
            p = ports[-1]["port"]
            print(f"  {city['name']:<22} {str(p['code'] or '?'):<7} "
                  f"{str(p['name'])[:24]:<24} mar {sea_km:5.1f} km")
    ports.sort(key=lambda p: p["port"]["lng"])
    return ports, rejected


def main():
    parser = argparse.ArgumentParser(
        description=(
            "Fogg Sea Routes — hasta 5 rutas marítimas más cortas hacia el Este por puerto "
            f"(searoute {SEAROUTE_VERSION}, mar a <= {THRESHOLD_KM} km)"
        ),
        formatter_class=argparse.RawTextHelpFormatter
    )
    parser.add_argument("--city", action="append", default=[], metavar="NOMBRE",
                        help="Ciudad origen (repetible). Sin --city: todas las ciudades con puerto")
    parser.add_argument("--limit", type=int, default=DEFAULT_LIMIT,
                        help=f"Rutas por puerto (default {DEFAULT_LIMIT})")
    parser.add_argument("--dry-run", action="store_true",
                        help="Detalla el resultado sin escribir disco")
    parser.add_argument("--out", type=Path, default=SEA_ROUTES_PATH,
                        help=f"Ruta de salida (default {SEA_ROUTES_PATH})")
    args = parser.parse_args()

    if args.limit <= 0:
        print("[ERROR] --limit debe ser >0", file=sys.stderr)
        sys.exit(1)

    _, cities, _ = load_locations()
    selected_indices = find_city_indices(cities, args.city)
    selected_names = {cities[i]["name"] for i in selected_indices}
    print(f"[INFO] {len(cities)} ciudades en {JSON_PATH}")
    print(f"[INFO] orígenes solicitados: {len(selected_indices)}"
          f"{' (el lote completo)' if not selected_names else ''}")

    sr, M, P = load_searoute()
    print(f"[INFO] searoute {SEAROUTE_VERSION}: {graph_size(M)} nodos de malla, "
          f"{graph_size(P)} puertos")

    # El pool de candidatos es siempre el de todos los puertos válidos del catálogo:
    # filtrar los orígenes no debe alterar los destinos disponibles de cada uno.
    print("[INFO] Resolviendo puertos")
    all_ports, rejected = resolve_ports(sr, M, P, cities, range(len(cities)), verbose=args.dry_run)
    origins = [p for p in all_ports if p["city"] in selected_names]
    if not origins:
        print("[WARN] Ningún origen solicitado tiene mar a "
              f"<= {THRESHOLD_KM} km", file=sys.stderr)
    print(f"[INFO] {len(all_ports)} puertos válidos, {len(rejected)} ciudades descartadas sin mar")
    if rejected:
        rejected.sort(key=lambda item: item[1])
        preview = ", ".join(f"{name}({km:.0f} km)" for name, km in rejected[:12])
        print(f"[INFO] Descartadas, muestra: {preview}{' …' if len(rejected) > 12 else ''}")

    routes = []
    for origin in origins:
        selected = select_routes(sr, M, P, origin, all_ports, args.limit, verbose=args.dry_run)
        if args.dry_run:
            print(f"  {origin['city']:<22} {len(selected)} rutas")
        for distance, dest, coordinates in selected:
            routes.append(build_route(origin, dest, distance, coordinates))
        if not selected and not args.dry_run:
            print(f"[WARN] {origin['city']} sin ruta hacia el Este", file=sys.stderr)

    problems = validate_dataset(routes, args.limit)
    for p in problems:
        print(f"[ERROR] {p}", file=sys.stderr)
    if problems:
        print(f"[ERROR] {len(problems)} problemas de validación, no se escribe", file=sys.stderr)
        sys.exit(1)

    crossings = [r for r in routes if crosses_antimeridian(r["geometry"]["coordinates"])]
    print(f"[INFO] {len(routes)} rutas para {len(origins)} orígenes")
    print(f"[INFO] {len(crossings)} rutas cruzan el antimeridiano "
          f"(coordenadas normalizadas, las segmenta el consumidor)")
    if crossings and not args.dry_run:
        print("[WARN] " + ", ".join(f'{r["origin"]}->{r["destination"]}' for r in crossings),
              file=sys.stderr)

    if args.dry_run:
        print(f"[INFO] dry-run: no se escribe {args.out}")
        return

    meta = build_meta(len(origins), len(routes), len(rejected), len(crossings), args.limit)
    write_output(args.out, meta, routes)
    print(f'[INFO] Guardadas {len(routes)} rutas ({meta["generated"]}) en {args.out}')


if __name__ == "__main__":
    main()
