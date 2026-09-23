#!/usr/bin/env python3
"""
strip_alternates.py — Crea un fichero nuevo sin claves superfluas.

Entrada: docs/origenes/cities15000.json (generado por cities_to_json.py, 19 claves)
Salida:  docs/origenes/cities15000.no-alts.json (mismo contenido sin claves indicadas)

Por defecto elimina: alternatenames, feature_class, feature_code, country_code,
cc2, admin1, admin2, admin3, admin4, elevation, dem → quedan 8 claves:
geonameid, name, asciiname, latitude, longitude, population, timezone, modification_date.
Opción recomendada: minified (compacto, ~5 MB vs 17 MB full).

Uso:
  python3 docs/origenes/strip_alternates.py
  python3 docs/origenes/strip_alternates.py --keys alternatenames --pretty
  python3 docs/origenes/strip_alternates.py --input docs/origenes/cities15000.json --output docs/origenes/cities15000.no-alts.json --keys alternatenames,feature_class,feature_code
  python3 docs/origenes/strip_alternates.py --keep-empty  # mantiene claves con []/null en vez de borrar

Prefijo: eu.elarreglador.pf — ver AGENTS.md.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(
        description="Elimina claves superfluas del JSON de ciudades (por defecto 11 claves)",
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )
    p.add_argument(
        "--input",
        "-i",
        type=Path,
        default=Path(__file__).with_name("cities15000.json"),
        help="JSON origen (con todas las claves)",
    )
    p.add_argument(
        "--output",
        "-o",
        type=Path,
        default=Path(__file__).with_name("cities15000.no-alts.json"),
        help="JSON destino sin claves indicadas",
    )
    g = p.add_mutually_exclusive_group()
    g.add_argument("--pretty", action="store_true", help="JSON indentado (2 espacios)")
    g.add_argument("--minify", action="store_true", help="JSON compacto (alias de no --pretty)")
    p.add_argument(
        "--keep-empty",
        action="store_true",
        help="Mantiene las claves con []/null en vez de eliminarlas (no recomendado)",
    )
    p.add_argument(
        "--keys",
        type=str,
        default="alternatenames,feature_class,feature_code,country_code,cc2,admin1,admin2,admin3,admin4,elevation,dem",
        help="Claves coma-separadas a eliminar (por defecto 11 claves admin/feature/dem)",
    )
    # Compatibilidad con --key singular previo
    p.add_argument(
        "--key",
        type=str,
        default=None,
        help=argparse.SUPPRESS,
    )
    return p.parse_args()


def main() -> int:
    args = parse_args()
    input_path: Path = args.input
    output_path: Path = args.output
    pretty = args.pretty and not args.minify
    # --key tiene prioridad por compatibilidad, si no se usa se toma --keys
    keys_raw = args.key if args.key is not None else args.keys
    keys: list[str] = [k.strip() for k in keys_raw.split(",") if k.strip()]
    if not keys:
        print("[error] No se indicaron claves a eliminar (--keys vacío)", file=sys.stderr)
        return 2

    if not input_path.exists():
        print(f"[error] No existe input: {input_path}", file=sys.stderr)
        print(f"  Sugerencia: genere primero con python3 docs/origenes/cities_to_json.py", file=sys.stderr)
        return 2

    try:
        with input_path.open("r", encoding="utf-8") as f:
            data = json.load(f)
    except (OSError, json.JSONDecodeError) as e:
        print(f"[error] No se pudo leer JSON {input_path}: {e}", file=sys.stderr)
        return 2

    if not isinstance(data, list):
        print(f"[error] JSON raíz no es array (es {type(data).__name__})", file=sys.stderr)
        return 2

    # Contadores por clave
    removed_per_key: dict[str, int] = {k: 0 for k in keys}
    kept_empty = 0
    for obj in data:
        if not isinstance(obj, dict):
            continue
        for k in keys:
            if k in obj:
                removed_per_key[k] += 1
                if args.keep_empty:
                    # alternatenames → [], resto → null
                    obj[k] = [] if k == "alternatenames" else None
                    kept_empty += 1
                else:
                    del obj[k]

    total_removed = sum(removed_per_key.values())

    # Si --keep-empty, removed == kept_empty; si no, se borra la clave
    try:
        output_path.parent.mkdir(parents=True, exist_ok=True)
        with output_path.open("w", encoding="utf-8", newline="\n") as out:
            if pretty:
                json.dump(data, out, ensure_ascii=False, indent=2)
                out.write("\n")
            else:
                json.dump(data, out, ensure_ascii=False, separators=(",", ":"))
                out.write("\n")
    except OSError as e:
        print(f"[error] No se pudo escribir {output_path}: {e}", file=sys.stderr)
        return 2

    size = output_path.stat().st_size
    size_mb = size / (1024 * 1024)
    in_size = input_path.stat().st_size
    saved = in_size - size
    saved_pct = (saved / in_size * 100) if in_size else 0
    keys_str = ",".join(keys)

    print(
        f"[ok] {len(data)} objetos → {output_path} ({size} bytes, {size_mb:.2f} MB) "
        f"{'pretty' if pretty else 'minified'} claves='{keys_str}' eliminadas={total_removed} "
        f"({', '.join(f'{k}:{v}' for k, v in removed_per_key.items())}) "
        f"{'keep_empty' if args.keep_empty else 'borradas'} ahorro={saved} bytes ({saved_pct:.1f}%)",
        file=sys.stderr,
    )

    # Verificación: ningún objeto debe contener las claves si no es keep-empty
    if not args.keep_empty:
        for k in keys:
            leaked = sum(1 for o in data if k in o)
            if leaked:
                print(f"[warn] {leaked} objetos aún contienen '{k}'", file=sys.stderr)
                return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
