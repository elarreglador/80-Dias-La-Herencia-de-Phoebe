#!/usr/bin/env python3
"""
fogg-sea-routes — 5 rutas marítimas más cortas hacia el Este con searoute
Proyecto eu.elarreglador.pf

- Recorre assets/data/locations.json desde índice origen hacia Este desenrollado
- Valida snap puerto <10 km Haversine (searoute first/last vertex)
- Ordena por distanceKm y persiste 5 más cortas en assets/data/sea_routes.json
- Merge idempotente origin::destination, sin tocar locations.json

Uso:
  python3 .opencode/skills/fogg-sea-routes/sea_route.py --city "Londres" --dry-run
  python3 .opencode/skills/fogg-sea-routes/sea_route.py --city "Londres"
  python3 .opencode/skills/fogg-sea-routes/sea_route.py --city "Londres" --limit 5 --force

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
import difflib

# ---------------------------------------------------------------------------
# Rutas y constantes
# ---------------------------------------------------------------------------
PROJECT_ROOT = Path(__file__).resolve().parents[3]  # PF/
JSON_PATH = PROJECT_ROOT / "assets" / "data" / "locations.json"
SEA_ROUTES_PATH = PROJECT_ROOT / "assets" / "data" / "sea_routes.json"

THRESHOLD_KM = 10
ORIGIN_ABORT_KM = 100  # si snapOrigin >100, origen inland profundo → abort
SEAROUTE_VERSION = "1.6.0"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def normalize(s: str) -> str:
    """NFD, lower, strip, sin acentos."""
    if not s:
        return ""
    nfkd = unicodedata.normalize("NFKD", s)
    stripped = "".join(c for c in nfkd if not unicodedata.combining(c))
    return stripped.lower().strip()


def haversine(lat1: float, lng1: float, lat2: float, lng2: float) -> float:
    """Distancia Haversine en km entre dos puntos [lat,lng]."""
    R = 6371.0088
    phi1, phi2 = math.radians(lat1), math.radians(lat2)
    dphi = math.radians(lat2 - lat1)
    dlambda = math.radians(lng2 - lng1)
    a = math.sin(dphi / 2) ** 2 + math.cos(phi1) * math.cos(phi2) * math.sin(dlambda / 2) ** 2
    c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))
    return R * c


def haversine_sum(coordinates) -> float:
    """Suma Haversine de segmentos GeoJSON [lng,lat]."""
    total = 0.0
    for i in range(len(coordinates) - 1):
        lng1, lat1 = coordinates[i]
        lng2, lat2 = coordinates[i + 1]
        total += haversine(lat1, lng1, lat2, lng2)
    return total


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
    # validar campos mínimos
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


def find_origin_index(cities, target: str):
    """Resuelve índice origen con normalización NFD sobre name|asciiname."""
    norm_target = normalize(target)
    for idx, c in enumerate(cities):
        names = [c.get("name", ""), c.get("asciiname", "")]
        # alternatenames no existe en locations.json actual, pero si futuro
        if c.get("alternatenames"):
            names += c["alternatenames"].split(",")
        for n in names:
            if normalize(n) == norm_target:
                return idx, c
    # no encontrado → sugerencias con difflib
    all_names = [c["name"] for c in cities]
    suggestions = difflib.get_close_matches(target, all_names, n=3, cutoff=0.6)
    if not suggestions:
        # fallback: 3 primeras costeras Este (heurística) o primeras 3
        suggestions = all_names[:3]
    print(f'[ERROR] Ciudad origen "{target}" no encontrada en locations.json', file=sys.stderr)
    if suggestions:
        print(f'  Sugerencias: {", ".join(suggestions)}', file=sys.stderr)
    sys.exit(1)


def load_or_init_sea_routes():
    """Lee sea_routes.json si existe o crea esqueleto."""
    if SEA_ROUTES_PATH.exists():
        try:
            with open(SEA_ROUTES_PATH, encoding="utf-8") as f:
                data = json.load(f)
            # validar estructura mínima
            if "meta" not in data or "routes" not in data:
                raise ValueError("estructura inválida")
            if not isinstance(data["routes"], list):
                raise ValueError("routes no es lista")
            return data
        except Exception as e:
            print(f"[WARN] sea_routes.json existente inválido, reiniciando: {e}", file=sys.stderr)
    # crear nuevo
    meta = {
        "project": "eu.elarreglador.pf",
        "name": "Fogg Sea Routes — Herencia de Phoebe",
        "version": "1.0.0",
        "generated": date.today().isoformat(),
        "tool": "fogg-sea-routes",
        "searoute": SEAROUTE_VERSION,
        "units": "km",
        "thresholdKm": THRESHOLD_KM,
        "source": "searoute (avoid land) + GeoNames cities15000"
    }
    return {"meta": meta, "routes": []}


def validate_route(route) -> list[str]:
    """Valida ruta y retorna lista de warnings (vacía si OK)."""
    warns = []
    d = route.get("distanceKm")
    if not isinstance(d, (int, float)) or not (0 < d < 40000):
        warns.append(f"distanceKm fuera de rango 0-40000: {d}")
    geom = route.get("geometry", {})
    if geom.get("type") != "LineString":
        warns.append(f"geometry.type != LineString: {geom.get('type')}")
    coords = geom.get("coordinates", [])
    if not isinstance(coords, list) or len(coords) < 2:
        warns.append(f"coordinates.length <2: {len(coords) if isinstance(coords, list) else type(coords)}")
    else:
        for lng, lat in coords:
            if not (-180 <= lng <= 180 and -90 <= lat <= 90):
                warns.append(f"coord fuera de rango lng {lng} lat {lat}")
                break
        # ±20% haversine sum vs distanceKm
        try:
            hsum = haversine_sum(coords)
            if d and hsum:
                diff = abs(hsum - d) / d
                if diff > 0.20:
                    warns.append(f"distanceKm {d:.1f} vs haversine sum {hsum:.1f} diff {diff*100:.1f}% >20%")
        except Exception as e:
            warns.append(f"haversine sum error: {e}")
    # campos obligatorios
    for k in ("origin", "destination", "originLat", "originLng", "destinationLat", "destinationLng"):
        if k not in route:
            warns.append(f"falta campo {k}")
    if route.get("origin") == route.get("destination"):
        warns.append("origin == destination")
    return warns


def main():
    parser = argparse.ArgumentParser(
        description="Fogg Sea Routes — 5 rutas marítimas más cortas hacia el Este (searoute 1.6.0, threshold 10km)",
        formatter_class=argparse.RawTextHelpFormatter
    )
    parser.add_argument("--city", required=True, help='Ciudad origen (ej. "Londres") — debe existir en locations.json')
    parser.add_argument("--limit", type=int, default=5, help="Número de rutas más cortas a guardar (default 5)")
    parser.add_argument("--dry-run", action="store_true", help="Lista candidatos sin escribir sea_routes.json")
    parser.add_argument("--force", action="store_true", help="Fuerza recálculo aunque sea_routes.json exista")
    args = parser.parse_args()

    if args.limit <= 0:
        print("[ERROR] --limit debe ser >0", file=sys.stderr)
        sys.exit(1)

    # cargar locations
    loc_data, cities, unwrapped = load_locations()
    print(f"[INFO] Cargado {len(cities)} ciudades desde {JSON_PATH}")

    # resolver origen
    origin_idx, origin_city = find_origin_index(cities, args.city)
    origin_lng_u = unwrapped[origin_idx]
    origin_name = origin_city["name"]  # canónico
    print(f'[INFO] Origen: {origin_name} ({origin_city["lat"]}, {origin_city["lng"]}) lng_u {origin_lng_u:.2f} idx {origin_idx}')

    # importar searoute
    try:
        import searoute
    except ImportError as e:
        print(f"[ERROR] searoute no instalado: {e}. Ejecute: pip install -r .opencode/skills/fogg-sea-routes/requirements.txt", file=sys.stderr)
        sys.exit(1)

    # recorrer hacia Este
    candidates = []
    origin_snap_checked = False
    origin_is_inland = False
    skipped_inland = 0
    skipped_error = 0

    # preparar lista de sugerencias costeras para abort origen inland
    # se calculará bajo demanda si detectamos origen inland

    for i in range(origin_idx + 1, len(cities)):
        dest = cities[i]
        dest_lng_u = unwrapped[i]
        # Regla del Este desenrollada
        if dest_lng_u <= origin_lng_u:
            # no debería ocurrir si catálogo ordenado, pero validar
            print(f'[SKIP] {dest["name"]} no es Este (lng_u {dest_lng_u:.2f} <= {origin_lng_u:.2f})')
            continue

        # invocar searoute
        try:
            # searoute espera [lng, lat]
            result = searoute.searoute(
                [float(origin_city["lng"]), float(origin_city["lat"])],
                [float(dest["lng"]), float(dest["lat"])],
                units="km"
            )
        except Exception as e:
            # searoute lanza excepción si puntos en tierra sin ruta
            print(f'[SKIP] {dest["name"]} searoute error: {e}')
            skipped_error += 1
            continue

        # manejar respuesta vacía o FeatureCollection
        if result is None:
            print(f'[WARN] {dest["name"]} searoute devolvió None')
            skipped_error += 1
            continue
        # si es FeatureCollection (cuando include_ports con múltiples), tomar primer Feature
        # pero en nuestro caso sin include_ports siempre Feature
        if isinstance(result, dict) and result.get("type") == "FeatureCollection":
            feats = result.get("features", [])
            if not feats:
                print(f'[WARN] {dest["name"]} FeatureCollection vacío')
                skipped_error += 1
                continue
            result = feats[0]

        geometry = result.get("geometry")  # type: ignore
        properties = result.get("properties", {})  # type: ignore
        if not geometry or geometry.get("type") != "LineString":
            print(f'[WARN] {dest["name"]} geometry no LineString: {geometry}')
            skipped_error += 1
            continue
        coordinates = geometry.get("coordinates", [])
        if not isinstance(coordinates, list) or len(coordinates) < 2:
            print(f'[WARN] {dest["name"]} coordinates inválidas len {len(coordinates) if isinstance(coordinates, list) else "NA"}')
            skipped_error += 1
            continue

        distanceKm = properties.get("length")
        if distanceKm is None:
            # fallback: calcular haversine sum
            distanceKm = haversine_sum(coordinates)
            print(f'[WARN] {dest["name"]} sin properties.length, usando haversine sum {distanceKm:.1f}')

        # validar snap Haversine ciudad→primer/último vértice
        try:
            first_lng, first_lat = coordinates[0]
            last_lng, last_lat = coordinates[-1]
            snapOriginKm = haversine(float(origin_city["lat"]), float(origin_city["lng"]), first_lat, first_lng)
            snapDestKm = haversine(float(dest["lat"]), float(dest["lng"]), last_lat, last_lng)
        except Exception as e:
            print(f'[WARN] {dest["name"]} error snap calc: {e}')
            skipped_error += 1
            continue

        # Validar origen inland una sola vez (primer éxito)
        if not origin_snap_checked:
            origin_snap_checked = True
            if snapOriginKm > ORIGIN_ABORT_KM:
                # origen profundo inland → abort con 3 sugerencias costeras Este
                temp_suggestions = []
                for j in range(origin_idx + 1, min(len(cities), origin_idx + 30)):
                    cand = cities[j]
                    try:
                        r2 = searoute.searoute([float(origin_city["lng"]), float(origin_city["lat"])],[float(cand["lng"]), float(cand["lat"])], units="km")
                        # r2 puede ser Feature o FeatureCollection
                        if isinstance(r2, dict) and r2.get("type") == "FeatureCollection":
                            feats = r2.get("features", [])
                            if not feats:
                                continue
                            r2 = feats[0]
                        c2 = r2.get("geometry", {}).get("coordinates", [])  # type: ignore
                        if len(c2) >= 2:
                            sd2 = haversine(float(cand["lat"]), float(cand["lng"]), c2[-1][1], c2[-1][0])
                            if sd2 < THRESHOLD_KM:
                                temp_suggestions.append(cand["name"])
                                if len(temp_suggestions) >= 3:
                                    break
                    except:
                        continue
                if not temp_suggestions:
                    temp_suggestions = [cities[k]["name"] for k in range(origin_idx+1, min(len(cities), origin_idx+4))]
                print(f'[ERROR] origin has no port within {THRESHOLD_KM}km (snap {snapOriginKm:.1f}km) — origen inland', file=sys.stderr)
                print(f'  Sugerencias costeras Este: {", ".join(temp_suggestions)}', file=sys.stderr)
                sys.exit(1)
            elif snapOriginKm > THRESHOLD_KM:
                print(f'[WARN] origin snap {snapOriginKm:.1f}km >{THRESHOLD_KM}km estuarino (ej. Londres Támesis) — continuando como costero')

        # Validar destino inland
        if snapDestKm > THRESHOLD_KM:
            print(f'[SKIP] {dest["name"]} inland snapDest {snapDestKm:.1f}km >{THRESHOLD_KM}km (snapOrigin {snapOriginKm:.1f}km)')
            skipped_inland += 1
            continue
        if snapOriginKm > THRESHOLD_KM:
            # ya advertido, pero log por cada ruta como WARN
            # no descartamos, solo informamos
            print(f'[OK] {dest["name"]} snapOrigin {snapOriginKm:.1f}km (>10 estuarino) snapDest {snapDestKm:.1f}km distance {distanceKm:.1f}km')
        else:
            print(f'[OK] {dest["name"]} snapDest {snapDestKm:.1f}km snapOrigin {snapOriginKm:.1f}km distance {distanceKm:.1f}km')

        # validar distancia y geometría básica antes de acumular
        if not (0 < distanceKm < 40000):
            print(f'[WARN] {dest["name"]} distanceKm fuera de rango: {distanceKm}')
            skipped_error += 1
            continue
        if len(coordinates) < 2:
            print(f'[WARN] {dest["name"]} coordinates <2')
            skipped_error += 1
            continue
        # validar rangos lng/lat
        valid = True
        for lng, lat in coordinates:
            if not (-180 <= lng <= 180 and -90 <= lat <= 90):
                print(f'[WARN] {dest["name"]} coord fuera de rango lng {lng} lat {lat}')
                valid = False
                break
        if not valid:
            skipped_error += 1
            continue

        # acumular candidato
        candidates.append({
            "city": dest,
            "distanceKm": float(distanceKm),
            "geometry": {"type": "LineString", "coordinates": coordinates},
            "snapOriginKm": snapOriginKm,
            "snapDestKm": snapDestKm,
        })

    # fin recorrido
    if not candidates:
        print(f'[WARN] No se encontraron rutas marítimas válidas desde "{origin_name}" hacia el Este (evaluadas {len(cities)-origin_idx-1} ciudades, SKIP inland {skipped_inland}, errores {skipped_error})')
        if not args.dry_run:
            print("[ERROR] 0 rutas halladas — no se escribe sea_routes.json", file=sys.stderr)
            sys.exit(1)
        else:
            print("[INFO] dry-run: 0 rutas, no se escribe")
            sys.exit(0)

    # ordenar por distanceKm ascendente y tomar 5 más cortas
    candidates.sort(key=lambda x: x["distanceKm"])
    selected = candidates[:args.limit]
    print(f'[INFO] {len(candidates)} candidatos válidos, seleccionando {len(selected)} más cortas (limit {args.limit})')
    for idx, cand in enumerate(selected, 1):
        c = cand["city"]
        print(f'  #{idx} {c["name"]} {cand["distanceKm"]:.1f}km snapDest {cand["snapDestKm"]:.1f}km')

    # dry-run: listar y no escribir
    if args.dry_run:
        print(f'[INFO] dry-run: no se escribe {SEA_ROUTES_PATH}')
        # también mostrar que Niamey sería SKIP si estuviera en rango
        # ya listado arriba, pero asegurar que se visualiza
        # verificar que no se creó/modificó archivo
        return

    # construir rutas GeoJSON
    new_routes = []
    for cand in selected:
        dest = cand["city"]
        route = {
            "origin": origin_name,
            "originLat": float(origin_city["lat"]),
            "originLng": float(origin_city["lng"]),
            "destination": dest["name"],
            "destinationLat": float(dest["lat"]),
            "destinationLng": float(dest["lng"]),
            "distanceKm": round(float(cand["distanceKm"]), 1),
            "geometry": cand["geometry"]
        }
        # validación extra
        warns = validate_route(route)
        for w in warns:
            print(f'[WARN] {dest["name"]} validación: {w}')
        new_routes.append(route)

    # validar orden ascendente
    for i in range(len(new_routes)-1):
        if new_routes[i]["distanceKm"] > new_routes[i+1]["distanceKm"]:
            print(f'[WARN] rutas no ordenadas: {new_routes[i]["destination"]} {new_routes[i]["distanceKm"]} > {new_routes[i+1]["destination"]} {new_routes[i+1]["distanceKm"]}')

    # cargar o inicializar sea_routes.json
    sea_data = load_or_init_sea_routes()
    old_routes = sea_data.get("routes", [])
    old_meta = sea_data.get("meta", {})

    # merge idempotente por clave origin::destination
    # construir dict
    route_map = {}
    for r in old_routes:
        key = f'{r.get("origin")}::{r.get("destination")}'
        route_map[key] = r

    changed = False
    for nr in new_routes:
        key = f'{nr["origin"]}::{nr["destination"]}'
        old = route_map.get(key)
        if old is None:
            route_map[key] = nr
            changed = True
            print(f'[INFO] Nueva ruta {key} {nr["distanceKm"]}km')
        else:
            # comparar distanceKm y geometry
            if old.get("distanceKm") != nr.get("distanceKm") or old.get("geometry") != nr.get("geometry"):
                route_map[key] = nr
                changed = True
                print(f'[INFO] Actualizada ruta {key} {old.get("distanceKm")} -> {nr.get("distanceKm")}km')
            else:
                print(f'[INFO] Ruta {key} sin cambios')

    # reconstruir lista ordenada por distanceKm ascendente global? spec dice routes ordenadas por distanceKm ascendente
    # Pero merge debe preservar todas, ordenadas. Ordenamos global por distanceKm.
    merged_routes = list(route_map.values())
    # Ordenar por distanceKm para cumplir criterio de JSON válido ordenado
    # Sin embargo, si hay múltiples orígenes, ordenar global puede mezclar orígenes.
    # Spec ejemplo implica orden por distanceKm ascendente dentro del archivo.
    # Mantendremos orden ascendente global.
    merged_routes.sort(key=lambda x: x["distanceKm"])

    # verificar duplicados origin==destination y clave única
    seen_keys = set()
    deduped = []
    for r in merged_routes:
        k = f'{r["origin"]}::{r["destination"]}'
        if k in seen_keys:
            print(f'[WARN] duplicado {k} omitido')
            continue
        if r["origin"] == r["destination"]:
            print(f'[WARN] ruta origin==destination {k} omitida')
            continue
        seen_keys.add(k)
        deduped.append(r)
    merged_routes = deduped

    # actualizar meta si hubo cambio o force
    new_meta = dict(old_meta) if old_meta else {}
    # asegurar campos base
    new_meta.update({
        "project": "eu.elarreglador.pf",
        "name": "Fogg Sea Routes — Herencia de Phoebe",
        "tool": "fogg-sea-routes",
        "searoute": SEAROUTE_VERSION,
        "units": "km",
        "thresholdKm": THRESHOLD_KM,
        "source": "searoute (avoid land) + GeoNames cities15000"
    })
    # version bump solo si cambió contenido
    old_dump = json.dumps({"meta": old_meta, "routes": old_routes}, sort_keys=True, ensure_ascii=False) if old_routes or old_meta else ""
    new_dump_for_compare = json.dumps({"meta": new_meta, "routes": merged_routes}, sort_keys=True, ensure_ascii=False)
    # comparar solo routes para decidir version bump
    routes_changed = json.dumps(old_routes, sort_keys=True) != json.dumps(merged_routes, sort_keys=True)
    if routes_changed or not old_meta.get("version"):
        # bump version 1.0.0 -> 1.0.1 si ya existe 1.0.0
        curr_ver = old_meta.get("version", "1.0.0")
        if curr_ver == "1.0.0" and routes_changed:
            new_meta["version"] = "1.0.1"
        elif not curr_ver:
            new_meta["version"] = "1.0.0"
        else:
            # si ya 1.0.1 y cambia de nuevo, mantener 1.0.1 (spec dice bump 1.0.0→1.0.1 si cambia)
            new_meta["version"] = curr_ver
    else:
        new_meta["version"] = old_meta.get("version", "1.0.0")

    new_meta["generated"] = date.today().isoformat()

    final_data = {"meta": new_meta, "routes": merged_routes}

    # escribir
    SEA_ROUTES_PATH.parent.mkdir(parents=True, exist_ok=True)
    with open(SEA_ROUTES_PATH, "w", encoding="utf-8") as f:
        json.dump(final_data, f, indent=2, ensure_ascii=False)
        f.write("\n")
    print(f'[INFO] Guardado {len(merged_routes)} rutas ({len(new_routes)} nuevas/actualizadas desde {origin_name}) en {SEA_ROUTES_PATH}')
    # validar JSON
    try:
        with open(SEA_ROUTES_PATH, encoding="utf-8") as f:
            json.load(f)
        print(f'[INFO] JSON válido: {SEA_ROUTES_PATH}')
    except Exception as e:
        print(f'[ERROR] JSON inválido tras escribir: {e}', file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
