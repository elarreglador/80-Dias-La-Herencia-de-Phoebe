#!/usr/bin/env python3
"""
fogg-sea-routes-fiction — ruta marítima ficticia bajo demanda
Proyecto eu.elarreglador.pf

- Toma un origen y un destino explícitos (p. ej. "San Juan" y "Nuakchot"),
  resuelve su puerto con searoute y traza UNA única ruta ficticia.
- La ruta discurre sobre la malla marítima real de searoute (evita tierra por
  construcción) pero con los pesos de las aristas perturbados de forma
  determinista por semilla: w' = w * exp(beta * xi), xi = blake2b(seed|u|v).
  Un Dijkstra por cada beta de la escalera produce trazados distintos; se elige
  el que más se acerca al ratio de desvío pedido (`--detour`) frente al camino
  más corto real.
- La curvatura terrestre se respeta en todo el cálculo: los pesos de la malla y
  la distancia persistida son distancias Haversine sobre esfera.
- La geometría se ancla a las coordenadas de la ciudad en ambos extremos
  (como sea_routes.json) y la longitud se dobla a [-180, 180].
- Persiste en assets/data/sea_routes_fiction.json con merge: conserva las rutas
  ya escritas y solo exige --force para reemplazar un par existente.

Uso:
  python3 .opencode/skills/fogg-sea-routes-fiction/sea_route_fiction.py \\
      --origin "San Juan" --destination "Nuakchot" --dry-run
  python3 .opencode/skills/fogg-sea-routes-fiction/sea_route_fiction.py \\
      --origin "San Juan" --destination "Nuakchot"
  python3 .opencode/skills/fogg-sea-routes-fiction/sea_route_fiction.py \\
      --origin "Lisboa" --destination "Tokio" --seed 7 --detour 1.15
  python3 .opencode/skills/fogg-sea-routes-fiction/sea_route_fiction.py \\
      --origin "Cádiz" --destination "Nuakchot" --dry-run --verbose

Stdlib + searoute==1.6.0
"""
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import math
import sys
from datetime import date
from pathlib import Path
from typing import Any

# ---------------------------------------------------------------------------
# Rutas y constantes
# ---------------------------------------------------------------------------
PROJECT_ROOT = Path(__file__).resolve().parents[3]  # PF/
FICTION_PATH = PROJECT_ROOT / "assets" / "data" / "sea_routes_fiction.json"
SIBLING_SKILL = PROJECT_ROOT / ".opencode" / "skills" / "fogg-sea-routes" / "sea_route.py"

PROJECT = "eu.elarreglador.pf"
TOOL_NAME = "fogg-sea-routes-fiction"
SCHEMA_VERSION = "1.0.0"
SEAROUTE_VERSION = "1.6.0"

DEFAULT_SEED = 80
DEFAULT_DETOUR = 1.05  # ratio objetivo frente al camino más corto real
DEFAULT_ROUNDS = 16  # número de betas sondeados en la escalera
BETA_MIN = 0.05
BETA_MAX = 1.10
MIN_FICTION_RATIO = 1.002  # por debajo se considera "el mismo camino real"


# ---------------------------------------------------------------------------
# Import de los helpers invariantes de la skill real (fuente única de verdad)
# ---------------------------------------------------------------------------

def _load_sibling() -> Any:
    """Importa sea_route.py sin ejecutar su CLI; reutiliza sus invariantes."""
    if not SIBLING_SKILL.exists():
        print(f"[ERROR] No existe la skill hermana {SIBLING_SKILL}", file=sys.stderr)
        sys.exit(1)
    spec = importlib.util.spec_from_file_location("fogg_sea_routes", SIBLING_SKILL)
    if spec is None or spec.loader is None:
        print(f"[ERROR] No se pudo cargar {SIBLING_SKILL}", file=sys.stderr)
        sys.exit(1)
    module = importlib.util.module_from_spec(spec)
    try:
        spec.loader.exec_module(module)
    except Exception as e:  # pragma: no cover - error de entorno
        print(f"[ERROR] Fallo al importar la skill real: {e}", file=sys.stderr)
        sys.exit(1)
    return module


S = _load_sibling()  # normalize, normalize_lng, eastward_delta, haversine,
# haversine_sum, city_vertex, anchor_to_cities, crosses_antimeridian,
# load_locations, resolve_port, sea_snap_km, load_searoute, COORD_PRECISION...

try:
    import networkx as nx
    from searoute.classes.passages import Passage
except ImportError as e:  # pragma: no cover - error de entorno
    print(
        f"[ERROR] Faltan dependencias: {e}. Ejecute: "
        "pip install -r .opencode/skills/fogg-sea-routes-fiction/requirements.txt",
        file=sys.stderr,
    )
    sys.exit(1)


# ---------------------------------------------------------------------------
# Localización de ciudades
# ---------------------------------------------------------------------------

def resolve_city(cities, query: str) -> dict:
    """Ciudad por nombre o asciiname, coincidencia exacta normalizada (NFD).

    Si la consulta es ambigua (varias ciudades normalizan igual) se listan las
    candidatas y se aborta para no elegir por el usuario.
    """
    key = S.normalize(query)
    if not key:
        print("[ERROR] Origen/destino vacío", file=sys.stderr)
        sys.exit(1)
    matches = [
        c for c in cities
        if key in {S.normalize(c.get("name", "")), S.normalize(c.get("asciiname", ""))}
    ]
    if not matches:
        print(f'[ERROR] Ciudad no encontrada en locations.json: "{query}"', file=sys.stderr)
        sys.exit(1)
    if len(matches) > 1:
        names = ", ".join(f'{c["name"]} ({c["lat"]}, {c["lng"]})' for c in matches)
        print(f'[ERROR] "{query}" es ambigua: {names}. Use otra grafía.', file=sys.stderr)
        sys.exit(1)
    return matches[0]


# ---------------------------------------------------------------------------
# Ruta ficticia: Dijkstra con pesos perturbados sobre la malla real
# ---------------------------------------------------------------------------

def _passage_of(data: dict):
    """Pasaje asociado a una arista, si lo tiene."""
    return data.get("passage")


def make_base_weight(restrictions):
    """Peso real de la malla; los pasajes restringidos se anulan con inf."""
    def weight(u, v, data):
        if _passage_of(data) in restrictions:
            return float("inf")
        return data.get("weight")
    return weight


def make_perturbed_weight(seed: int, round_index: int, beta: float, restrictions):
    """Peso perturbado determinista: w * exp(beta * xi), xi ~ U(-1, 1).

    xi se deriva de blake2b(seed | ronda | arista), de modo que la misma
    semilla y ronda reproducen exactamente el mismo grafo ponderado, con
    independencia del orden de recorrido de las aristas.
    """
    def weight(u, v, data):
        if _passage_of(data) in restrictions:
            return float("inf")
        key = f"{seed}|{round_index}|{u[0]:.6f},{u[1]:.6f}|{v[0]:.6f},{v[1]:.6f}".encode()
        digest = hashlib.blake2b(key, digest_size=8).digest()
        xi = int.from_bytes(digest, "big") / 2 ** 64  # [0, 1)
        return data.get("weight") * math.exp(beta * (2.0 * xi - 1.0))
    return weight


def mesh_coordinates(path, origin, dest):
    """Vértices de la malla normalizados, sin duplicados consecutivos, anclados.

    Dos nodos vecinos pueden caer en lados opuestos del antimeridiano y acabar
    en la misma coordenada tras `normalize_lng` (p. ej. 180 y -180 → -180);
    el segmento de longitud cero se descarta.
    """
    coords = []
    for lng, lat in path:
        vertex = [round(S.normalize_lng(lng), S.COORD_PRECISION), round(lat, S.COORD_PRECISION)]
        if coords and coords[-1] == vertex:
            continue
        coords.append(vertex)
    return S.anchor_to_cities(coords, origin, dest)


def choose_path(M, origin, dest, seed: int, rounds: int, detour: float, restrictions, verbose: bool):
    """Elige el trazado perturbado cuyo ratio se acerca más a `detour`.

    Devuelve (nodes, coords, distance_km, ratio, base_km). El camino base
    (sin perturbar) define el ratio 1.0 y se descarta salvo que sea la única
    opción o que `detour <= MIN_FICTION_RATIO`.
    """
    origin_node = M.kdtree.query([float(origin["lng"]), float(origin["lat"])])
    dest_node = M.kdtree.query([float(dest["lng"]), float(dest["lat"])])

    base_path = nx.dijkstra_path(M, origin_node, dest_node, weight=make_base_weight(restrictions))
    base_coords = mesh_coordinates(base_path, origin, dest)
    base_km = S.haversine_sum(base_coords)

    candidates: dict[tuple, list] = {}
    for round_index in range(rounds):
        beta = BETA_MIN + (BETA_MAX - BETA_MIN) * (round_index / max(1, rounds - 1))
        weight = make_perturbed_weight(seed, round_index, beta, restrictions)
        path = nx.dijkstra_path(M, origin_node, dest_node, weight=weight)
        candidates[tuple(path)] = path
        if verbose:
            km = S.haversine_sum(mesh_coordinates(path, origin, dest))
            print(f"    ronda {round_index:2d} beta {beta:.2f}  ratio {km / base_km:.4f}  "
                  f"{len(path)} nodos")

    want_fiction = detour > MIN_FICTION_RATIO
    ranked = []
    for nodes, path in candidates.items():
        coords = mesh_coordinates(path, origin, dest)
        distance_km = S.haversine_sum(coords)
        ratio = distance_km / base_km if base_km else 1.0
        if want_fiction and ratio < MIN_FICTION_RATIO:
            continue  # idéntico al camino real: no es ficción
        ranked.append((abs(ratio - detour), ratio, distance_km, nodes, coords))

    if not ranked:
        ranked = [(0.0, 1.0, base_km, tuple(base_path), base_coords)]

    ranked.sort(key=lambda item: (round(item[0], 6), item[1]))
    _, ratio, distance_km, nodes, coords = ranked[0]
    return list(nodes), coords, distance_km, ratio, base_km


# ---------------------------------------------------------------------------
# Construcción y validación de la ruta
# ---------------------------------------------------------------------------

def build_route(M, origin, dest, sea_origin, port_origin, sea_dest, port_dest,
                seed, detour, rounds, verbose) -> dict:
    restrictions = [Passage.northwest]  # mismo invariante que la skill real
    _, coords, distance_km, ratio, base_km = choose_path(
        M, origin, dest, seed, rounds, detour, restrictions, verbose
    )
    delta = S.eastward_delta(port_origin["lng"], port_dest["lng"])
    heading = "east" if delta > 0 else "west"
    if heading == "west":
        print(f"[WARN] {origin['name']} -> {dest['name']}: par hacia el Oeste "
              f"(delta {delta:.2f}º); el juego prefiere el Este", file=sys.stderr)

    return {
        "origin": origin["name"],
        "originLat": float(origin["lat"]),
        "originLng": float(origin["lng"]),
        "destination": dest["name"],
        "destinationLat": float(dest["lat"]),
        "destinationLng": float(dest["lng"]),
        "distanceKm": round(distance_km, 1),
        "heading": heading,
        "portOrigin": {**port_origin, "seaKm": round(float(sea_origin), 1)},
        "portDest": {**port_dest, "seaKm": round(float(sea_dest), 1)},
        "geometry": {"type": "LineString", "coordinates": coords},
        "synthetic": True,
        "syntheticSeed": seed,
        "detourRatio": round(ratio, 4),
        "detourBaseKm": round(base_km, 1),
    }


def validate_route(route) -> list[str]:
    """Invariantes de una ruta individual (sin la cobertura de SPEC 008)."""
    problems = []
    key = f'{route["origin"]}::{route["destination"]}'
    if route["origin"] == route["destination"]:
        problems.append(f"origen == destino {key}")

    distance = route["distanceKm"]
    if not isinstance(distance, (int, float)) or not (0 < distance < S.MAX_DISTANCE_KM):
        problems.append(f"distanceKm fuera de rango en {key}: {distance}")

    coords = route["geometry"]["coordinates"]
    if len(coords) < 2:
        return problems + [f"geometría con menos de 2 vértices en {key}"]

    expected_start = [round(S.normalize_lng(float(route["originLng"])), S.COORD_PRECISION),
                      round(float(route["originLat"]), S.COORD_PRECISION)]
    expected_end = [round(S.normalize_lng(float(route["destinationLng"])), S.COORD_PRECISION),
                    round(float(route["destinationLat"]), S.COORD_PRECISION)]
    if coords[0] != expected_start:
        problems.append(f"no arranca en la ciudad origen en {key}: {coords[0]}")
    if coords[-1] != expected_end:
        problems.append(f"no termina en la ciudad destino en {key}: {coords[-1]}")
    for lng, lat in coords:
        if not (-180 <= lng <= 180 and -90 <= lat <= 90):
            problems.append(f"coordenada fuera de rango en {key}: {lng},{lat}")
            break

    delta = S.eastward_delta(route["portOrigin"]["lng"], route["portDest"]["lng"])
    expected_heading = "east" if delta > 0 else "west"
    if route["heading"] != expected_heading:
        problems.append(f"heading {route['heading']} no coincide con el delta "
                        f"{delta:.3f}º en {key}")
    if route["heading"] == "east" and not (0 < delta <= S.MAX_EAST_DEG):
        problems.append(f"Regla del Este incumplida en {key}: delta {delta:.3f}º")
    if route["heading"] == "west" and not (-S.MAX_EAST_DEG <= delta < 0):
        problems.append(f"heading west con delta {delta:.3f}º en {key}")

    hsum = S.haversine_sum(coords)
    if distance and abs(hsum - distance) / distance > S.LENGTH_TOLERANCE:
        problems.append(f"distanceKm {distance:.1f} vs haversine {hsum:.1f} en {key} "
                        f"(±{S.LENGTH_TOLERANCE * 100:.0f}%)")
    return problems


# ---------------------------------------------------------------------------
# Persistencia (merge)
# ---------------------------------------------------------------------------

def load_existing(path: Path) -> list:
    if not path.exists():
        return []
    try:
        with open(path, encoding="utf-8") as f:
            data = json.load(f)
    except Exception as e:
        print(f"[ERROR] No se pudo leer {path}: {e}", file=sys.stderr)
        sys.exit(1)
    routes = data.get("routes")
    if not isinstance(routes, list):
        print(f"[ERROR] {path} sin lista 'routes'", file=sys.stderr)
        sys.exit(1)
    return routes


def build_meta(routes, seed, detour, rounds) -> dict:
    west = [r for r in routes if r.get("heading") == "west"]
    meta = {
        "project": PROJECT,
        "name": "sea_routes_fiction",
        "version": SCHEMA_VERSION,
        "generated": date.today().isoformat(),
        "tool": TOOL_NAME,
        "searoute": SEAROUTE_VERSION,
        "units": "km",
        "fictional": True,
        "algorithm": "Dijkstra con pesos perturbados w * exp(beta * xi) sobre la malla "
                      "marítima real de searoute; xi = blake2b(seed|ronda|arista) ~ U(-1,1). "
                      f"Rondas por ruta: {rounds}. Pasaje del Noroeste restringido.",
        "seed": seed,
        "detourTarget": detour,
        "maxEastDeg": S.MAX_EAST_DEG,
        "routes": len(routes),
        "crossesAntimeridian": sum(1 for r in routes
                                   if S.crosses_antimeridian(r["geometry"]["coordinates"])),
        "eastRule": "heading east: 0 < deltaLng(portDest - portOrigin) <= 180 (desenrollado); "
                    "heading west: -180 <= deltaLng < 0 (par explícito del usuario)",
        "geometry": "LineString [lng,lat] de ciudad a ciudad: el primer y el último vértice "
                    "son las coordenadas de la ciudad y en medio va la malla de searoute. "
                    "Siempre en [-180,180]; al cruzar el antimeridiano los vértices saltan de "
                    "179 a -179 y el consumidor debe segmentar",
        "distanceNote": "distanceKm = suma Haversine de toda la polilínea, incluidos los "
                        "tramos ciudad↔nodo de malla (a diferencia de sea_routes.json)",
        "source": "searoute (malla real, avoid land) + GeoNames cities15000; geometría ficticia",
    }
    if west:
        meta["westRoutesNote"] = f"{len(west)} ruta(s) hacia el Oeste por elección explícita"
    return meta


def write_output(path: Path, meta, routes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        json.dump({"meta": meta, "routes": routes}, f, indent=2, ensure_ascii=False)
        f.write("\n")
    try:
        with open(path, encoding="utf-8") as f:
            json.load(f)
    except Exception as e:
        print(f"[ERROR] JSON inválido tras escribir: {e}", file=sys.stderr)
        sys.exit(1)


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def parse_args(argv=None):
    p = argparse.ArgumentParser(
        description="Genera una ruta marítima ficticia bajo demanda sobre la malla real.",
    )
    p.add_argument("--origin", required=True, help="ciudad de origen (name o asciiname)")
    p.add_argument("--destination", required=True, help="ciudad de destino (name o asciiname)")
    p.add_argument("--seed", type=int, default=DEFAULT_SEED,
                   help=f"semilla del trazado (default {DEFAULT_SEED}); otra semilla, otro trazado")
    p.add_argument("--detour", type=float, default=DEFAULT_DETOUR,
                   help=f"ratio objetivo frente al camino más corto real (default {DEFAULT_DETOUR})")
    p.add_argument("--rounds", type=int, default=DEFAULT_ROUNDS,
                   help=f"número de trazados sondeados (default {DEFAULT_ROUNDS})")
    p.add_argument("--out", type=Path, default=FICTION_PATH,
                   help=f"fichero destino (default {FICTION_PATH})")
    p.add_argument("--dry-run", action="store_true", help="no escribe; solo informa")
    p.add_argument("--force", action="store_true",
                   help="reemplaza la ruta si el par ya existe en el fichero")
    p.add_argument("--verbose", action="store_true", help="detalla cada ronda sondeada")
    return p.parse_args(argv)


def main(argv=None) -> int:
    args = parse_args(argv)
    if args.rounds < 1:
        print("[ERROR] --rounds debe ser >= 1", file=sys.stderr)
        return 1
    if args.detour <= 0:
        print("[ERROR] --detour debe ser > 0", file=sys.stderr)
        return 1

    data, cities, _ = S.load_locations()
    origin = resolve_city(cities, args.origin)
    dest = resolve_city(cities, args.destination)
    if origin["name"] == dest["name"]:
        print("[ERROR] Origen y destino son la misma ciudad", file=sys.stderr)
        return 1

    sr, M, P = S.load_searoute()

    sea_origin = S.sea_snap_km(sr, M, P, origin)
    sea_dest = S.sea_snap_km(sr, M, P, dest)
    port_origin = S.resolve_port(sr, M, P, origin, sea_origin)["port"]
    port_dest = S.resolve_port(sr, M, P, dest, sea_dest)["port"]
    for city, sea_km, port in ((origin, sea_origin, port_origin), (dest, sea_dest, port_dest)):
        if sea_km > S.THRESHOLD_KM and city["name"] not in S.FORCED_COASTAL_KM:
            print(f"[WARN] {city['name']} está a {sea_km:.1f} km del mar "
                  f"(umbral {S.THRESHOLD_KM}); la ruta se traza igual por ser ficticia",
                  file=sys.stderr)
        if not port.get("code"):
            print(f"[WARN] {city['name']} sin puerto WPI resuelto; se ancla solo a la malla",
                  file=sys.stderr)

    route = build_route(M, origin, dest, sea_origin, port_origin,
                        sea_dest, port_dest, args.seed, args.detour, args.rounds, args.verbose)

    problems = validate_route(route)
    if problems:
        print("[ERROR] La ruta generada no valida:", file=sys.stderr)
        for problem in problems:
            print(f"  - {problem}", file=sys.stderr)
        return 1

    pair = f'{route["origin"]} → {route["destination"]}'
    print(f'[OK] {pair}: {route["distanceKm"]} km, heading {route["heading"]}, '
          f'{len(route["geometry"]["coordinates"])} vértices, '
          f'ratio {route["detourRatio"]} (base {route["detourBaseKm"]} km), '
          f'seed {args.seed}, antimeridiano '
          f'{"sí" if S.crosses_antimeridian(route["geometry"]["coordinates"]) else "no"}')

    if args.dry_run:
        print("[DRY-RUN] No se ha escrito nada.")
        return 0

    routes = load_existing(args.out)
    duplicate = next((r for r in routes
                      if r["origin"] == route["origin"] and r["destination"] == route["destination"]),
                     None)
    if duplicate and not args.force:
        print(f'[ERROR] El par {pair} ya existe en {args.out}. Use --force para reemplazarlo.',
              file=sys.stderr)
        return 1
    if duplicate:
        routes = [r for r in routes if not (r["origin"] == route["origin"]
                                            and r["destination"] == route["destination"])]
        print(f"[INFO] Reemplazando el par existente {pair} (--force)")
    routes.append(route)
    routes.sort(key=lambda r: (r["origin"].lower(), r["distanceKm"]))

    problems = []
    seen = set()
    for r in routes:
        key = f'{r["origin"]}::{r["destination"]}'
        if key in seen:
            problems.append(f"duplicado {key}")
        seen.add(key)
        problems += validate_route(r)
    if problems:
        print("[ERROR] El dataset resultante no valida; no se escribe:", file=sys.stderr)
        for problem in problems:
            print(f"  - {problem}", file=sys.stderr)
        return 1

    write_output(args.out, build_meta(routes, args.seed, args.detour, args.rounds), routes)
    print(f'[OK] Escrito {args.out} con {len(routes)} ruta(s).')
    return 0


if __name__ == "__main__":
    sys.exit(main())
