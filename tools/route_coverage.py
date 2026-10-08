#!/usr/bin/env python3
"""
route_coverage — verificador de cobertura de rutas por ciudad (SPEC 008)

Una ciudad está cubierta si aparece como `origin` de ≥1 ruta y como
`destination` de ≥1 ruta en la unión mar ∪ tierra (sea_routes.json +
car_routes.json). El verificador lista las ciudades descubiertas y sale con
código 2 mientras quede alguna sin `excepción` en docs/ciudades-sin-rutas.md.

Uso:
  python3 tools/route_coverage.py                # diagnóstico por stdout
  python3 tools/route_coverage.py --write-report  # regenera el informe

Stdlib puro, sin pip install. Importable por las skills (validate_dataset).
"""
from __future__ import annotations

import argparse
import json
import sys
import unicodedata
from datetime import date
from pathlib import Path

# Raíz del repo: en las skills el mismo patrón es parents[3] porque viven más
# profundo (.opencode/skills/<skill>/); aquí tools/ está a un solo nivel.
PROJECT_ROOT = Path(__file__).resolve().parents[1]
LOCATIONS_PATH = PROJECT_ROOT / "assets" / "data" / "locations.json"
SEA_ROUTES_PATH = PROJECT_ROOT / "assets" / "data" / "sea_routes.json"
CAR_ROUTES_PATH = PROJECT_ROOT / "assets" / "data" / "car_routes.json"
REPORT_PATH = PROJECT_ROOT / "docs" / "ciudades-sin-rutas.md"

REPORT_HEADERS = ["Ciudad", "Sin salida", "Sin entrada", "Rutas", "Decisión"]


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def normalize(s: str) -> str:
    """NFD, lower, strip, sin acentos (misma normalización que las skills)."""
    if not s:
        return ""
    nfkd = unicodedata.normalize("NFKD", s)
    stripped = "".join(c for c in nfkd if not unicodedata.combining(c))
    return stripped.lower().strip()


def is_exception(decision: str) -> bool:
    """Una ciudad se acepta si su Decisión normalizada empieza por `excepcion`."""
    return normalize(decision).startswith("excepcion")


# ---------------------------------------------------------------------------
# Carga de datos
# ---------------------------------------------------------------------------

def load_locations() -> list[dict]:
    """Ciudades de locations.json (catálogo, solo lectura)."""
    if not LOCATIONS_PATH.exists():
        print(f"[ERROR] No existe {LOCATIONS_PATH}", file=sys.stderr)
        sys.exit(1)
    with open(LOCATIONS_PATH, encoding="utf-8") as f:
        data = json.load(f)
    cities = data.get("cities")
    if not isinstance(cities, list) or not cities:
        print("[ERROR] locations.json sin 'cities' o vacío", file=sys.stderr)
        sys.exit(1)
    return cities


def load_routes(path: Path) -> list[dict]:
    """Rutas de un dataset; lista vacía si el fichero no existe."""
    if not path.exists():
        return []
    with open(path, encoding="utf-8") as f:
        data = json.load(f)
    return data.get("routes") or []


def compute_coverage(cities: list[dict], sea: list[dict],
                     car: list[dict]) -> list[dict]:
    """Cobertura por ciudad sobre la unión mar ∪ tierra.

    Devuelve una lista con {"name", "outbound", "inbound", "total",
    "decision"} por cada ciudad descubierta (sin salida o sin entrada),
    con la `decision` leída del informe previo ('' si no había).
    """
    decisions = read_decisions()
    outbound: dict[str, int] = {}
    inbound: dict[str, int] = {}
    for route in sea + car:
        origin = route.get("origin")
        dest = route.get("destination")
        if origin:
            outbound[origin] = outbound.get(origin, 0) + 1
        if dest:
            inbound[dest] = inbound.get(dest, 0) + 1
    uncovered = []
    for city in cities:
        name = city["name"]
        out_n = outbound.get(name, 0)
        in_n = inbound.get(name, 0)
        if out_n > 0 and in_n > 0:
            continue
        uncovered.append({
            "name": name,
            "outbound": out_n,
            "inbound": in_n,
            "total": out_n + in_n,
            "decision": decisions.get(name, ""),
        })
    uncovered.sort(key=lambda item: normalize(item["name"]))
    return uncovered


def read_decisions(path: Path = REPORT_PATH) -> dict[str, str]:
    """Columna `Decisión` del informe previo, indexada por ciudad.

    El parser lee por encabezado de columna, no por posición: si el formato
    de la tabla cambia por columnas, las decisiones no se pierden.
    """
    if not path.exists():
        return {}
    decisions: dict[str, str] = {}
    name_idx = decision_idx = None
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line.startswith("|"):
            continue
        cells = [cell.strip() for cell in line.strip("|").split("|")]
        if name_idx is None or decision_idx is None:
            normalized = [normalize(cell) for cell in cells]
            if "ciudad" in normalized and "decision" in normalized:
                name_idx = normalized.index("ciudad")
                decision_idx = normalized.index("decision")
            continue
        if set(cells) <= {"-", ""} or len(cells) <= max(name_idx, decision_idx):
            continue  # separador `| --- |` o fila mal formada
        decisions[cells[name_idx]] = cells[decision_idx]
    return decisions


# ---------------------------------------------------------------------------
# Informe
# ---------------------------------------------------------------------------

def write_report(uncovered: list[dict], total_cities: int,
                 path: Path = REPORT_PATH) -> None:
    """Escribe docs/ciudades-sin-rutas.md conservando la columna Decisión."""
    pendientes = sum(1 for item in uncovered if not is_exception(item["decision"]))
    lines = [
        "# Ciudades sin rutas",
        "",
        f"> Generado por `tools/route_coverage.py` el {date.today().isoformat()} — "
        f"{total_cities} ciudades, {pendientes} pendientes.",
        "> Edite solo la columna **Decisión**. Marque `excepción — <motivo>` para aceptar",
        "> una ciudad que no se pueda conectar; el resto de texto es solo notas suyas.",
        "> Regenerar con `python3 tools/route_coverage.py --write-report` conserva esta columna.",
        "",
        "| " + " | ".join(REPORT_HEADERS) + " |",
        "| " + " | ".join("---" for _ in REPORT_HEADERS) + " |",
    ]
    for item in uncovered:
        lines.append(
            f"| {item['name']} "
            f"| {'sí' if item['outbound'] == 0 else ''} "
            f"| {'sí' if item['inbound'] == 0 else ''} "
            f"| {item['total']} "
            f"| {item['decision']} |"
        )
    lines.append("")
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(lines), encoding="utf-8")


# ---------------------------------------------------------------------------
# Integración con validate_dataset (SPEC 008 paso 7)
# ---------------------------------------------------------------------------

def coverage_problems(sea: list, car: list) -> list[str]:
    """Problemas de cobertura para validate_dataset: ciudades descubiertas
    sin `excepción` en el informe. Lista vacía = cobertura completa.

    Recibe las rutas **en memoria** del fichero que se va a validar (la otra
    mitad de la unión se lee de disco): validar contra los ficheros sería
    mirar datos previos justo antes de escribir los nuevos.
    """
    cities = load_locations()
    uncovered = compute_coverage(cities, sea, car)
    return [
        f"cobertura: {item['name']} "
        f"({'sin salida' if item['outbound'] == 0 else ''}"
        f"{' y ' if item['outbound'] == 0 and item['inbound'] == 0 else ''}"
        f"{'sin entrada' if item['inbound'] == 0 else ''}) "
        f"sin excepción en {REPORT_PATH.relative_to(PROJECT_ROOT)}"
        for item in uncovered
        if not is_exception(item["decision"])
    ]


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def main() -> None:
    parser = argparse.ArgumentParser(
        description="Verificador de cobertura de rutas por ciudad (SPEC 008)"
    )
    parser.add_argument("--write-report", action="store_true",
                        help=f"Regenera {REPORT_PATH.relative_to(PROJECT_ROOT)} "
                             f"conservando la columna Decisión")
    args = parser.parse_args()

    cities = load_locations()
    sea = load_routes(SEA_ROUTES_PATH)
    car = load_routes(CAR_ROUTES_PATH)
    uncovered = compute_coverage(cities, sea, car)

    without_out = sum(1 for item in uncovered if item["outbound"] == 0)
    without_in = sum(1 for item in uncovered if item["inbound"] == 0)
    with_out = len(cities) - without_out
    with_in = len(cities) - without_in
    no_route = sum(1 for item in uncovered
                   if item["outbound"] == 0 and item["inbound"] == 0)
    exceptions = [item for item in uncovered if is_exception(item["decision"])]
    pending = [item for item in uncovered if not is_exception(item["decision"])]

    print(f"[INFO] {len(cities)} ciudades — {len(sea)} rutas marítimas + "
          f"{len(car)} terrestres = {len(sea) + len(car)} (unión mar ∪ tierra)")
    print(f"[INFO] Salida: {with_out} ciudades con ≥1 ruta de salida, "
          f"{without_out} sin salida")
    print(f"[INFO] Entrada: {with_in} ciudades con ≥1 ruta "
          f"de entrada, {without_in} sin entrada")
    print(f"[INFO] Descubiertas: {len(uncovered)} "
          f"({no_route} sin ninguna ruta, {len(uncovered) - no_route} solo sin "
          f"entrada) — excepciones: {len(exceptions)}")
    print(f"[INFO] Pendientes: {len(pending)}")

    if args.write_report:
        write_report(uncovered, len(cities))
        print(f"[INFO] Informe escrito en {REPORT_PATH.relative_to(PROJECT_ROOT)} "
              f"({len(uncovered)} filas)")

    if pending:
        print(f"[ERROR] {len(pending)} ciudades sin cobertura y sin excepción: "
              + ", ".join(item["name"] for item in pending))
        sys.exit(2)
    print("[INFO] 0 pendientes")


if __name__ == "__main__":
    main()
