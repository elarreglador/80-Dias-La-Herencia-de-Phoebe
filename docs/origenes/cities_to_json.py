#!/usr/bin/env python3
"""
cities_to_json.py — Convierte docs/origenes/cities15000.txt (GeoNames TSV) a JSON.

Origen: GeoNames cities15000 (19 columnas, TSV \\t, UTF-8, sin cabecera).
Destino: JSON array de objetos con tipos correctos y nulos normalizados.

Opción recomendada (por defecto si no se pasan flags):
  - Python stdlib, sin dependencias
  - 19 campos completos, claves en snake_case GeoNames
  - alternatenames → string[] (split por ',')
  - elevation "" → null, dem -9999 → null, cc2/admin* vacíos → null
  - latitude/longitude → float, population/dem/elevation → int
  - pretty = False (compacto, ~10 MB) ; use --pretty para indent=2 (~22 MB, legible)

Uso:
  python3 docs/origenes/cities_to_json.py
  python3 docs/origenes/cities_to_json.py --input docs/origenes/cities15000.txt --output docs/origenes/cities15000.json --pretty
  python3 docs/origenes/cities_to_json.py --minify  # alias de compacto
  python3 docs/origenes/cities_to_json.py --keep-alternates-string  # alternatenames como string crudo
  python3 docs/origenes/cities_to_json.py --filter-feature PPL,PPLA  # whitelist
  python3 docs/origenes/cities_to_json.py --fields geonameid,name,latitude,longitude,population

Licencia origen: GeoNames CC-BY 4.0 — mantenga atribución si redistribuye.
Prefijo proyecto: eu.elarreglador.pf — ver AGENTS.md.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any

# Orden GeoNames oficial para cities15000.txt
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

# Campos tipados
INT_FIELDS = {"geonameid", "population"}
INT_NULLABLE_FIELDS = {"elevation", "dem"}
FLOAT_FIELDS = {"latitude", "longitude"}
STRING_NULLABLE_FIELDS = {"cc2", "admin1", "admin2", "admin3", "admin4", "elevation"}


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(
        description="Convierte cities15000.txt (GeoNames TSV) a JSON",
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )
    p.add_argument(
        "--input",
        "-i",
        type=Path,
        default=Path(__file__).with_name("cities15000.txt"),
        help="Ruta al TSV origen",
    )
    p.add_argument(
        "--output",
        "-o",
        type=Path,
        default=Path(__file__).with_name("cities15000.json"),
        help="Ruta al JSON destino",
    )
    g = p.add_mutually_exclusive_group()
    g.add_argument(
        "--pretty",
        action="store_true",
        help="JSON indentado (2 espacios, legible, más grande)",
    )
    g.add_argument(
        "--minify",
        action="store_true",
        help="JSON compacto sin espacios (alias de no --pretty, explícito)",
    )
    p.add_argument(
        "--keep-alternates-string",
        action="store_true",
        help="Mantiene alternatenames como string crudo en vez de string[] (recomendado: array)",
    )
    p.add_argument(
        "--fields",
        type=str,
        default="",
        help="Subset de campos coma-separados (ej. geonameid,name,latitude,longitude). Vacío = todos",
    )
    p.add_argument(
        "--filter-feature",
        type=str,
        default="",
        help="Filtra por feature_code coma-separados (ej. PPL,PPLA). Vacío = sin filtro",
    )
    p.add_argument(
        "--filter-pop-min",
        type=int,
        default=None,
        help="Filtra population >= N (ej. 15000). None = sin filtro",
    )
    p.add_argument(
        "--validate",
        action="store_true",
        default=True,
        help="Valida rangos lat/lng y unicidad geonameid (por defecto activo)",
    )
    p.add_argument(
        "--no-validate",
        dest="validate",
        action="store_false",
        help="Desactiva validación",
    )
    return p.parse_args()


def _to_int_or_null(value: str) -> int | None:
    v = value.strip()
    if v == "":
        return None
    try:
        return int(v)
    except ValueError:
        return None


def _to_float(value: str) -> float | None:
    v = value.strip()
    if v == "":
        return None
    try:
        return float(v)
    except ValueError:
        return None


def convert_row(
    cols: list[str],
    split_alternates: bool = True,
    selected_fields: set[str] | None = None,
) -> dict[str, Any]:
    """Convierte una fila TSV (19 cols) a dict tipado."""
    if len(cols) != 19:
        raise ValueError(f"Fila con {len(cols)} columnas, esperaba 19: {cols[:3]}")

    obj: dict[str, Any] = {}

    # Helper para incluir solo campos seleccionados si se pidió --fields
    def include(field: str) -> bool:
        return selected_fields is None or field in selected_fields

    # 0 geonameid
    if include("geonameid"):
        obj["geonameid"] = int(cols[0].strip())
    # 1 name
    if include("name"):
        obj["name"] = cols[1]
    # 2 asciiname
    if include("asciiname"):
        obj["asciiname"] = cols[2]
    # 3 alternatenames
    if include("alternatenames"):
        raw = cols[3]
        if split_alternates:
            if raw.strip() == "":
                obj["alternatenames"] = []
            else:
                # split por coma, preservando vacíos? GeoNames no genera vacíos internos
                obj["alternatenames"] = [a for a in raw.split(",") if a != ""]
        else:
            obj["alternatenames"] = raw
    # 4 latitude
    if include("latitude"):
        obj["latitude"] = float(cols[4].strip())
    # 5 longitude
    if include("longitude"):
        obj["longitude"] = float(cols[5].strip())
    # 6 feature_class
    if include("feature_class"):
        obj["feature_class"] = cols[6]
    # 7 feature_code
    if include("feature_code"):
        obj["feature_code"] = cols[7]
    # 8 country_code
    if include("country_code"):
        obj["country_code"] = cols[8]
    # 9 cc2
    if include("cc2"):
        obj["cc2"] = cols[9].strip() or None
    # 10 admin1
    if include("admin1"):
        obj["admin1"] = cols[10].strip() or None
    # 11 admin2
    if include("admin2"):
        obj["admin2"] = cols[11].strip() or None
    # 12 admin3
    if include("admin3"):
        obj["admin3"] = cols[12].strip() or None
    # 13 admin4
    if include("admin4"):
        obj["admin4"] = cols[13].strip() or None
    # 14 population
    if include("population"):
        obj["population"] = int(cols[14].strip())
    # 15 elevation
    if include("elevation"):
        v = cols[15].strip()
        obj["elevation"] = int(v) if v != "" else None
    # 16 dem
    if include("dem"):
        v = cols[16].strip()
        if v == "" or v == "-9999":
            obj["dem"] = None
        else:
            obj["dem"] = int(v)
    # 17 timezone
    if include("timezone"):
        obj["timezone"] = cols[17]
    # 18 modification_date
    if include("modification_date"):
        obj["modification_date"] = cols[18].strip()

    return obj


def main() -> int:
    args = parse_args()

    input_path: Path = args.input
    output_path: Path = args.output

    if not input_path.exists():
        print(f"[error] No existe input: {input_path}", file=sys.stderr)
        return 2

    split_alternates = not args.keep_alternates_string
    pretty = args.pretty and not args.minify

    selected_fields: set[str] | None = None
    if args.fields.strip():
        requested = [f.strip() for f in args.fields.split(",") if f.strip()]
        invalid = [f for f in requested if f not in HEADER]
        if invalid:
            print(f"[error] Campos inválidos en --fields: {invalid}. Válidos: {HEADER}", file=sys.stderr)
            return 2
        selected_fields = set(requested)

    filter_codes: set[str] | None = None
    if args.filter_feature.strip():
        filter_codes = {c.strip() for c in args.filter_feature.split(",") if c.strip()}

    filter_pop_min: int | None = args.filter_pop_min

    rows: list[dict[str, Any]] = []
    seen_ids: set[int] = set()
    errors = 0

    # Lectura TSV
    try:
        with input_path.open("r", encoding="utf-8", newline="") as f:
            for lineno, line in enumerate(f, start=1):
                # rstrip solo \n / \r\n, preserva tabs internos y espacios en nombres
                if line.endswith("\r\n"):
                    line = line[:-2]
                elif line.endswith("\n"):
                    line = line[:-1]
                # línea vacía -> skip
                if line == "":
                    continue
                cols = line.split("\t")
                if len(cols) != 19:
                    print(f"[warn] línea {lineno}: {len(cols)} cols !=19, se omite", file=sys.stderr)
                    errors += 1
                    continue

                # filtros previos a conversión completa (baratos)
                if filter_codes is not None:
                    if cols[7] not in filter_codes:
                        continue
                if filter_pop_min is not None:
                    try:
                        pop = int(cols[14].strip())
                        if pop < filter_pop_min:
                            continue
                    except ValueError:
                        continue

                try:
                    obj = convert_row(cols, split_alternates=split_alternates, selected_fields=selected_fields)
                except Exception as e:
                    print(f"[warn] línea {lineno} geonameid={cols[0]} error: {e}", file=sys.stderr)
                    errors += 1
                    continue

                # validación opcional
                if args.validate:
                    gid = obj.get("geonameid") if selected_fields is None or "geonameid" in obj else None
                    if gid is not None:
                        if gid in seen_ids:
                            print(f"[warn] geonameid duplicado {gid} en línea {lineno}", file=sys.stderr)
                        seen_ids.add(gid)
                    lat = obj.get("latitude")
                    lng = obj.get("longitude")
                    if lat is not None and not (-90 <= lat <= 90):
                        print(f"[warn] lat fuera de rango {lat} línea {lineno}", file=sys.stderr)
                    if lng is not None and not (-180 <= lng <= 180):
                        print(f"[warn] lng fuera de rango {lng} línea {lineno}", file=sys.stderr)

                rows.append(obj)
    except OSError as e:
        print(f"[error] No se pudo leer {input_path}: {e}", file=sys.stderr)
        return 2

    # Escritura JSON
    try:
        output_path.parent.mkdir(parents=True, exist_ok=True)
        with output_path.open("w", encoding="utf-8", newline="\n") as out:
            if pretty:
                json.dump(rows, out, ensure_ascii=False, indent=2)
                out.write("\n")
            else:
                # compacto: separadores mínimos, ensure_ascii=False para preservar UTF-8
                json.dump(rows, out, ensure_ascii=False, separators=(",", ":"))
                out.write("\n")
    except OSError as e:
        print(f"[error] No se pudo escribir {output_path}: {e}", file=sys.stderr)
        return 2

    # Resumen
    size = output_path.stat().st_size
    size_mb = size / (1024 * 1024)
    print(
        f"[ok] {len(rows)} objetos → {output_path} ({size} bytes, {size_mb:.2f} MB) "
        f"{'pretty' if pretty else 'minified'} split_alternates={split_alternates} "
        f"errors={errors}",
        file=sys.stderr,
    )
    if args.validate and selected_fields is None:
        print(f"[ok] geonameid únicos: {len(seen_ids)}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
