#!/usr/bin/env python3
"""
fogg-city-enricher — Enriquecimiento para assets/data/locations.json
Proyecto exclusivo eu.elarreglador.pf

- Primario: docs/origenes/cities15000.txt (offline, 19 cols TSV)
- Fallback: Nominatim search + timeapi.io coordinate → IANA timezone
- Solo extrae {name, asciiname, lat, lng, timezone} — sin population
- Valida Regla del Este desenrollada (lng+360) como FoggRoute._isEastward
- Inserta ordenado por lng_u creciente, actualiza meta.update/version

Uso:
  python3 .opencode/skills/fogg-city-enricher/enrich.py --city "Bruselas" --dry-run
  python3 .opencode/skills/fogg-city-enricher/enrich.py --city "Bruselas"
  python3 .opencode/skills/fogg-city-enricher/enrich.py --retro --dry-run
  python3 .opencode/skills/fogg-city-enricher/enrich.py --retro

Stdlib only.
"""
from __future__ import annotations

import argparse
import json
import sys
import time
import unicodedata
from pathlib import Path
from typing import Any
from urllib.request import Request, urlopen
from urllib.parse import quote

# ---------------------------------------------------------------------------
# Rutas
# ---------------------------------------------------------------------------
PROJECT_ROOT = Path(__file__).resolve().parents[3]  # PF/
TSV_PATH = PROJECT_ROOT / "docs" / "origenes" / "cities15000.txt"
JSON_PATH = PROJECT_ROOT / "assets" / "data" / "locations.json"
TOOLS_JSON_PATH = PROJECT_ROOT / "tools" / "locations-map" / "locations.json"
CACHE_PATH = PROJECT_ROOT / "SENSIBLE" / ".cache" / "city_enrich.json"

HEADER = [
    "geonameid",
    "name",
    "asciiname",
    "alternatenames",
    "latitude",
    "longitude",
    "feature_class",
    "feature_code",
    "country_code",
    "cc2",
    "admin1",
    "admin2",
    "admin3",
    "admin4",
    "population",
    "elevation",
    "dem",
    "timezone",
    "modification_date",
]

USER_AGENT = "eu.elarreglador.pf/1.0 (fogg-city-enricher)"

# ---------------------------------------------------------------------------
# Helpers normalización
# ---------------------------------------------------------------------------

def normalize(s: str) -> str:
    """NFD, lower, strip, sin acentos."""
    if not s:
        return ""
    nfkd = unicodedata.normalize("NFKD", s)
    stripped = "".join(c for c in nfkd if not unicodedata.combining(c))
    return stripped.lower().strip()


def load_tsv_index() -> list[dict[str, Any]]:
    """Carga TSV completo en memoria (34k filas) — cacheado por invocación."""
    rows: list[dict[str, Any]] = []
    with open(TSV_PATH, encoding="utf-8") as f:
        for line in f:
            parts = line.rstrip("\n").split("\t")
            if len(parts) != 19:
                continue
            rec = dict(zip(HEADER, parts))
            # tipado mínimo
            try:
                rec["latitude"] = float(rec["latitude"])
                rec["longitude"] = float(rec["longitude"])
                rec["population"] = int(rec["population"]) if rec["population"] else 0
            except ValueError:
                continue
            rows.append(rec)
    return rows


def find_in_tsv(city: str, rows: list[dict[str, Any]]) -> dict[str, Any] | None:
    """Busca normalizado en name/asciiname/alternatenames. Prioriza capital luego población."""
    norm = normalize(city)
    candidates: list[dict[str, Any]] = []
    for r in rows:
        alt_list = r["alternatenames"].split(",") if r["alternatenames"] else []
        pool = [r["name"], r["asciiname"]] + alt_list
        for cand in pool:
            if normalize(cand) == norm:
                candidates.append(r)
                break
            # también match parcial para casos como "New York City" vs "New York"
            # pero solo si pool contiene norm como token separado — evitar falsos
    if not candidates:
        es_map = {
            "cancun": "cancun",
            "cancún": "cancun",
            "bruselas": "brussels",
            "londres": "london",
            "parís": "paris",
            "paris": "paris",
            "estambul": "istanbul",
            "bombay": "mumbai",
            "tokio": "tokyo",
            "nueva york": "new york",
            "san francisco": "san francisco",
            "estocolmo": "stockholm",
            "oslo": "oslo",
            "amsterdam": "amsterdam",
            "lisboa": "lisbon",
            "inverness": "inverness",
            "portsmouth": "portsmouth",
            "riga": "riga",
            "moscu": "moscow",
            "moscú": "moscow",
            "kazan": "kazan",
            "cheliabinsk": "chelyabinsk",
            "chelyabinsk": "chelyabinsk",
            "cheliábinsk": "chelyabinsk",
            "petropavi": "petropavl",
            "petropavlovsk": "petropavl",
            "omsk": "omsk",
            "astana": "astana",
            "karaganda": "karagandy",
            "karagandy": "karagandy",
            "novosibirsk": "novosibirsk",
            "krasnoyarsk": "krasnoyarsk",
            "semey": "semey",
            "helsinki": "helsinki",
            "tallin": "tallinn",
            "tallinn": "tallinn",
            "urumchi": "urumqi",
            "urumqi": "urumqi",
            "kumul": "hami",
            "hami": "hami",
            "yinchuan": "yinchuan",
            "xining": "xining",
            "lanzhou": "lanzhou",
            "xi'an": "xian",
            "xian": "xian",
            "shanxi": "taiyuan",
            "taiyuan": "taiyuan",
            "pekin": "beijing",
            "beijing": "beijing",
            "tianjin": "tianjin",
            "jinan": "jinan",
            "dalian": "dalian",
            "qingdao": "qingdao",
            "nakin": "nanjing",
            "nanjing": "nanjing",
            "nankin": "nanjing",
            "hanoi": "hanoi",
            "hanói": "hanoi",
            "chengdu": "chengdu",
            "chongqing": "chongqing",
            "kunming": "kunming",
            "wuhan": "wuhan",
            "shenzhen": "shenzhen",
            "taiwan": "taiwan",
            "taipei": "taipei",
            "hangzhou": "hangzhou",
            "shangai": "shanghai",
            "shanghai": "shanghai",
            "severo-kunisk": "severo-kurilsk",
            "severo-kurilsk": "severo-kurilsk",
            "kurilsk": "severo-kurilsk",
            "san blas": "san blas, mexico",
            "la celba": "la ceiba",
            "la ceiba": "la ceiba",
            "puerto ayora": "puerto ayora",
            "santa fe": "santa fe, new mexico",
            "dener": "denver",
            "denver": "denver",
            "great falls": "great falls",
            "lincoln": "lincoln",
            "dallas": "dallas",
            "houston": "houston",
            "horta": "horta, azores",
            "porta delgada": "ponta delgada",
            "ponta delgada": "ponta delgada",
            "funchal": "funchal",
            "santa cruz de tenerife": "santa cruz de tenerife",
            "memphis": "memphis",
            "tuxtla gutierrez": "tuxtla gutierrez",
            "tuxtla": "tuxtla gutierrez",
            "tehuacan": "tehuacan",
            "ciudad de mexico": "mexico city",
            "san luis potosi": "san luis potosi",
            "tampico": "tampico",
            "tampco": "tampico",
            "puerto vallarta": "puerto vallarta",
            "monterey": "monterrey",
            "monterrey": "monterrey",
            "trinidad": "trinidad, bolivia",
            "lima": "lima",
            "quito": "quito",
            "bogota": "bogota",
            "medellin": "medellin",
        }
        mapped = es_map.get(norm)
        if mapped:
            for r in rows:
                if normalize(r["name"]) == mapped or normalize(r["asciiname"]) == mapped:
                    candidates.append(r)
        if not candidates:
            return None
    # Prioridad: población descendente primaria, luego capitalidad (PPLC/PPLA)
    # Para desambiguar homónimos (San Francisco AR vs US vs SV), gana el más poblado
    # Caso especial Cancun: prefiere MX sobre CN (Changchun) aunque Changchun sea más poblado
    if norm == "cancun":
        mx_candidates = [c for c in candidates if c["country_code"] == "MX"]
        if mx_candidates:
            candidates = mx_candidates
    def rank(r: dict[str, Any]) -> tuple[int, int]:
        # -population primero, luego prioridad feature para desempate en poblaciones similares
        code = r["feature_code"]
        prio = {"PPLC": 0, "PPLA": 1, "PPLA2": 2, "PPLA3": 3, "PPL": 4}.get(code, 5)
        return (-r["population"], prio)
    candidates.sort(key=rank)
    return candidates[0]


def fetch_json(url: str, headers: dict[str, str] | None = None) -> Any:
    req = Request(url, headers=headers or {})
    with urlopen(req, timeout=15) as resp:
        data = resp.read()
        return json.loads(data.decode("utf-8"))


def fallback_nominatim(city: str) -> tuple[float, float, str, str] | None:
    """Nominatim → lat/lon + display name. 1 req/s."""
    url = f"https://nominatim.openstreetmap.org/search?q={quote(city)}&format=json&limit=1&addressdetails=1&accept-language=en"
    headers = {"User-Agent": USER_AGENT}
    try:
        data = fetch_json(url, headers)
        time.sleep(1)
        if not data:
            return None
        item = data[0]
        lat = float(item["lat"])
        lon = float(item["lon"])
        display = item.get("display_name", city).split(",")[0].strip()
        return lat, lon, display, display
    except Exception as e:
        print(f"[fallback] Nominatim error for '{city}': {e}", file=sys.stderr)
        time.sleep(1)
        return None


def fallback_timezone(lat: float, lng: float) -> str | None:
    """timeapi.io → IANA. 1 req/s."""
    url = f"https://timeapi.io/api/TimeZone/coordinate?latitude={lat}&longitude={lng}"
    try:
        data = fetch_json(url, {"User-Agent": USER_AGENT})
        time.sleep(1)
        tz = data.get("timeZone") or data.get("timezone")
        if tz and "/" in tz:
            return tz
        return None
    except Exception as e:
        print(f"[fallback] timeapi.io error {lat},{lng}: {e}", file=sys.stderr)
        time.sleep(1)
        return None


def derive_gmt_fallback(lng: float) -> str:
    """Deriva Etc/GMT±X por lng/15 (inverso signo POSIX)."""
    offset = round(lng / 15)
    # Etc/GMT signo invertido: GMT+5 = UTC-5
    if offset == 0:
        return "Etc/GMT"
    sign = "-" if offset > 0 else "+"
    return f"Etc/GMT{sign}{abs(offset)}"


def validate_east(cities_lng: list[float]) -> bool:
    """Replica FoggRoute._isEastward desenrollado."""
    if len(cities_lng) <= 1:
        return True
    offset = 0.0
    prev = cities_lng[0]
    for curr_real in cities_lng[1:]:
        curr = curr_real + offset
        if curr <= prev:
            curr += 360
            offset += 360
            if curr <= prev:
                return False
        prev = curr
    return True


def compute_insertion_index(existing: list[dict[str, Any]], new_lng: float) -> int:
    """Calcula índice por lng_u creciente (desenrollado)."""
    if not existing:
        return 0
    # Desenrolla existentes
    unwrapped: list[float] = []
    offset = 0.0
    prev = existing[0]["lng"]
    unwrapped.append(prev)
    for c in existing[1:]:
        curr_real = c["lng"]
        curr = curr_real + offset
        if curr <= prev:
            curr += 360
            offset += 360
        unwrapped.append(curr)
        prev = curr
    # Para nuevo, evalúa todas las posiciones East-válidas y elige la de menor recorrido total
    # (minimiza maxUnwrapped - minUnwrapped). Así Bruselas 4.34 va tras París (idx 2)
    # en vez de idx 0 que también valida pero da vuelta completa.
    best_idx = None
    best_span = float("inf")
    best_trial_unwrapped: list[float] | None = None
    for idx in range(len(existing) + 1):
        trial_lng = [c["lng"] for c in existing[:idx]] + [new_lng] + [c["lng"] for c in existing[idx:]]
        if not validate_east(trial_lng):
            continue
        # Calcula unwrapped para span
        unw = []
        off = 0.0
        prev_u = trial_lng[0]
        unw.append(prev_u)
        for curr_real in trial_lng[1:]:
            curr = curr_real + off
            if curr <= prev_u:
                curr += 360
                off += 360
            unw.append(curr)
            prev_u = curr
        span = unw[-1] - unw[0]
        if span < best_span:
            best_span = span
            best_idx = idx
            best_trial_unwrapped = unw
    if best_idx is not None:
        return best_idx
    # Si ninguno válido, append al final con offset extra (loop 360)
    return len(existing)


def load_cache() -> dict[str, Any]:
    if CACHE_PATH.exists():
        try:
            return json.loads(CACHE_PATH.read_text(encoding="utf-8"))
        except Exception:
            return {}
    return {}


def save_cache(cache: dict[str, Any]) -> None:
    CACHE_PATH.parent.mkdir(parents=True, exist_ok=True)
    CACHE_PATH.write_text(json.dumps(cache, ensure_ascii=False, indent=2), encoding="utf-8")


def enrich_city(city_input: str, tsv_rows: list[dict[str, Any]]) -> dict[str, Any] | None:
    """Retorna {name, asciiname, lat, lng, timezone} o None."""
    # Check cache first
    cache = load_cache()
    key = normalize(city_input)
    if key in cache:
        rec = cache[key]
        # compat: cache puede tener population, ignoramos
        return {k: rec[k] for k in ("name", "asciiname", "lat", "lng", "timezone") if k in rec}

    hit = find_in_tsv(city_input, tsv_rows)
    if hit:
        result = {
            "name": hit["name"] if normalize(hit["name"]) != "" else city_input,
            "asciiname": hit["asciiname"],
            "lat": hit["latitude"],
            "lng": hit["longitude"],
            "timezone": hit["timezone"],
        }
        # Para castellano, preserva input como name si el dump tiene inglés? 
        # Pero respetamos name del dump para consistencia; alternativamente map es→en ya resuelto
        # Si input es "Bruselas" y dump tiene "Brussels", usamos "Bruselas" como name narrativo
        es_map_reverse = {"brussels": "Bruselas", "london": "Londres", "paris": "París", "istanbul": "Estambul", "mumbai": "Bombay", "tokyo": "Tokio"}
        norm_input = normalize(city_input)
        if norm_input in ("bruselas", "londres", "parís", "estambul", "bombay", "tokio", "nueva york", "san francisco", "savile row"):
            result["name"] = city_input  # preserva castellano del usuario
        else:
            # Si input tiene acentos y dump no, preserva input
            if normalize(result["name"]) != norm_input:
                # si el dump name es inglés, mantén input como name narrativo
                result["name"] = city_input
        cache[key] = result
        save_cache(cache)
        return result

    # Fallback Nominatim + timeapi.io — usa mapeo es→en si existe (corrige typos como severo-kunisk)
    fallback_query = city_input
    norm_input = normalize(city_input)
    es_fallback_map = {
        "severo-kunisk": "Severo-Kurilsk",
        "severo-kurilsk": "Severo-Kurilsk",
        "kurilsk": "Severo-Kurilsk",
        "magadan": "Magadan",
        "evensk": "Evensk",
        "san blas": "San Blas, Mexico",
        "puerto ayora": "Puerto Ayora, Galapagos",
        "horta": "Horta, Azores",
        "porta delgada": "Ponta Delgada, Azores",
        "ponta delgada": "Ponta Delgada, Azores",
        "funchal": "Funchal, Madeira",
        "santa cruz de tenerife": "Santa Cruz de Tenerife, Canary Islands",
    }
    if norm_input in es_fallback_map:
        fallback_query = es_fallback_map[norm_input]
    print(f"[enrich] '{city_input}' no hallado en TSV, probando Nominatim...", file=sys.stderr)
    nom = fallback_nominatim(fallback_query)
    if not nom:
        print(f"[enrich] Nominatim sin resultados para '{city_input}'", file=sys.stderr)
        return None
    lat, lng, name, asciiname = nom
    tz = fallback_timezone(lat, lng)
    if not tz:
        tz = derive_gmt_fallback(lng)
        note = "timezone fallback lng/15"
    else:
        note = None
    result = {"name": city_input, "asciiname": asciiname, "lat": lat, "lng": lng, "timezone": tz}
    if note:
        result["note"] = note
    cache[key] = result
    save_cache(cache)
    return result


def cmd_retro(dry_run: bool) -> int:
    """Verifica 8 existentes contra dump."""
    tsv_rows = load_tsv_index()
    data = json.loads(JSON_PATH.read_text(encoding="utf-8"))
    cities = data.get("cities", [])
    ok = 0
    mism = 0
    manual = 0
    for entry in cities:
        name = entry.get("name", "")
        # Caso manual Savile Row no está en dump — preservar
        if normalize(name) == normalize("Savile Row"):
            print(f"[retro] {name}: MANUAL PRESERVE {entry.get('lat')},{entry.get('lng')} {entry.get('timezone')} — OK")
            manual += 1
            ok += 1
            continue
        hit = find_in_tsv(name, tsv_rows)
        if not hit:
            # Intenta por asciiname
            hit = find_in_tsv(entry.get("asciiname", ""), tsv_rows)
        if not hit:
            print(f"[retro] {name}: MISS en TSV — fallback requerido", file=sys.stderr)
            mism += 1
            continue
        exp_lat = hit["latitude"]
        exp_lng = hit["longitude"]
        exp_tz = hit["timezone"]
        exp_ascii = hit["asciiname"]
        got_lat = entry.get("lat")
        got_lng = entry.get("lng")
        got_tz = entry.get("timezone")
        got_ascii = entry.get("asciiname")
        lat_ok = abs(got_lat - exp_lat) < 1e-5 if isinstance(got_lat, (int, float)) else False
        lng_ok = abs(got_lng - exp_lng) < 1e-5 if isinstance(got_lng, (int, float)) else False
        tz_ok = got_tz == exp_tz
        ascii_ok = got_ascii == exp_ascii
        if lat_ok and lng_ok and tz_ok and ascii_ok:
            print(f"[retro] {name}: OK {got_lat},{got_lng} {got_tz}")
            ok += 1
        else:
            print(f"[retro] {name}: MISMATCH")
            print(f"  esperado: {exp_lat},{exp_lng} {exp_tz} ascii={exp_ascii}")
            print(f"  actual:   {got_lat},{got_lng} {got_tz} ascii={got_ascii}")
            mism += 1
            if not dry_run:
                # corrige in-place
                entry["lat"] = exp_lat
                entry["lng"] = exp_lng
                entry["timezone"] = exp_tz
                entry["asciiname"] = exp_ascii
    print(f"\n[retro] Resumen: {ok} OK, {mism} MISMATCH, {manual} MANUAL")
    if not dry_run and mism > 0:
        # valida East antes de escribir
        lngs = [c["lng"] for c in cities]
        if not validate_east(lngs):
            print("[retro] ERROR: Regla del Este violada tras corrección — no escribo", file=sys.stderr)
            return 2
        # actualiza meta
        import datetime
        data["meta"]["update"] = datetime.date.today().isoformat()
        # bump version si hubo cambios
        data["meta"]["version"] = "1.0.1"
        JSON_PATH.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        print(f"[retro] Corregidos {mism}, escrito {JSON_PATH}")
        # sync opcional para visor file:// — mantiene tools/locations-map fresco
        if TOOLS_JSON_PATH.parent.exists():
            try:
                TOOLS_JSON_PATH.write_text(JSON_PATH.read_text(encoding="utf-8"), encoding="utf-8")
                print(f"[retro] Sincronizado → {TOOLS_JSON_PATH}")
            except Exception as e:
                print(f"[retro] Aviso: no se pudo sincronizar {TOOLS_JSON_PATH}: {e}", file=sys.stderr)
    return 0 if mism == 0 else 1


def cmd_city(city: str, dry_run: bool) -> int:
    tsv_rows = load_tsv_index()
    enriched = enrich_city(city, tsv_rows)
    if not enriched:
        print(f"[city] No se pudo enriquecer '{city}'", file=sys.stderr)
        return 2
    print(f"[city] Enriquecido: {enriched['name']} {enriched['lat']},{enriched['lng']} {enriched['timezone']} ascii={enriched['asciiname']}")

    data = json.loads(JSON_PATH.read_text(encoding="utf-8"))
    cities = data.get("cities", [])

    # valida duplicado
    norm_new = normalize(enriched["name"])
    for c in cities:
        if normalize(c["name"]) == norm_new or normalize(c.get("asciiname","")) == normalize(enriched["asciiname"]):
            print(f"[city] '{city}' ya existe como '{c['name']}' — no inserto", file=sys.stderr)
            return 1

    idx = compute_insertion_index(cities, enriched["lng"])
    # valida East con trial
    trial_lng = [c["lng"] for c in cities[:idx]] + [enriched["lng"]] + [c["lng"] for c in cities[idx:]]
    if not validate_east(trial_lng):
        print(f"[city] Inserción en idx {idx} viola Regla del Este (lng {enriched['lng']}) — rechazado", file=sys.stderr)
        return 2
    entry: dict[str, Any] = {
        "name": enriched["name"],
        "asciiname": enriched["asciiname"],
        "lat": enriched["lat"],
        "lng": enriched["lng"],
        "timezone": enriched["timezone"],
    }
    if "note" in enriched:
        entry["note"] = enriched["note"]

    print(f"[city] Inserción East OK → idx {idx} (0-based) — previa lng {cities[idx-1]['lng'] if idx>0 else '—'} → {enriched['lng']} → {cities[idx]['lng'] if idx < len(cities) else '—'}")
    if dry_run:
        print("[city] --dry-run: no escribo")
        print(json.dumps(entry, ensure_ascii=False, indent=2))
        return 0

    cities.insert(idx, entry)
    # valida East final
    if not validate_east([c["lng"] for c in cities]):
        print("[city] ERROR East tras inserción — rollback", file=sys.stderr)
        return 2
    import datetime
    data["meta"]["update"] = datetime.date.today().isoformat()
    # bump version 1.0.0→1.0.1
    ver = data["meta"].get("version", "1.0.0")
    if ver == "1.0.0":
        data["meta"]["version"] = "1.0.1"
    data["cities"] = cities
    JSON_PATH.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"[city] Insertado en idx {idx}, escrito {JSON_PATH}")
    # sync opcional para visor file:// — mantiene tools/locations-map fresco
    if TOOLS_JSON_PATH.parent.exists():
        try:
            TOOLS_JSON_PATH.write_text(JSON_PATH.read_text(encoding="utf-8"), encoding="utf-8")
            print(f"[city] Sincronizado → {TOOLS_JSON_PATH}")
        except Exception as e:
            print(f"[city] Aviso: no se pudo sincronizar {TOOLS_JSON_PATH}: {e}", file=sys.stderr)
    return 0


def main() -> None:
    p = argparse.ArgumentParser(description="fogg-city-enricher — cities15000 → locations.json (solo lat/lng/timezone)")
    group = p.add_mutually_exclusive_group(required=True)
    group.add_argument("--city", type=str, help="Ciudad a enriquecer e insertar")
    group.add_argument("--retro", action="store_true", help="Verifica 8 existentes contra dump")
    p.add_argument("--dry-run", action="store_true", help="No escribe, solo muestra")
    args = p.parse_args()

    if args.retro:
        sys.exit(cmd_retro(dry_run=args.dry_run))
    else:
        sys.exit(cmd_city(args.city, dry_run=args.dry_run))


if __name__ == "__main__":
    main()
