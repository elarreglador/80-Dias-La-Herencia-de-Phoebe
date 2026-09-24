---
name: fogg-city-enricher
description: Enriquecimiento offline de cities15000 + fallback timeapi.io para locations.json (solo lat/lng/timezone IANA), validación Regla del Este desenrollada. Exclusiva proyecto eu.elarreglador.pf.
---

Cuando el usuario pida añadir una ciudad a `assets/data/locations.json` o verificar las existentes, usa esta skill.

## Cuándo usar

- Iteración por ciudad dictada por el Señor: `enrich.py --city "Bruselas"` (inserta en orden Este).
- Verificación retroactiva: `enrich.py --retro --dry-run` (compara 8 existentes contra dump).
- Fallback solo si miss en dump local.

## Fuentes

- **Primario (offline, sin key):** `docs/origenes/cities15000.txt` — TSV 19 cols, `latitude` col 4, `longitude` col 5, `timezone` col 17 (376 zonas IANA), `name` col 1, `asciiname` col 2, `alternatenames` col 3. Tipado según `docs/origenes/01_cities_to_json.py`.
- **Fallback 1 — Nominatim:** `https://nominatim.openstreetmap.org/search?q=<city>&format=json&limit=1&addressdetails=1&accept-language=en` — `User-Agent: eu.elarreglador.pf/1.0` obligatorio. **1 req/s** `sleep 1`.
- **Fallback 2 — timeapi.io:** `https://timeapi.io/api/TimeZone/coordinate?latitude=<lat>&longitude=<lng>` — sin key, `sleep 1`. Devuelve `timeZone` IANA. Si ambos fallan → deriva `Etc/GMT±X` por `lng/15` + `note: "timezone fallback lng/15"`.

## Flujo

1. **Busca** en `docs/origenes/cities15000.txt` normalizando NFD, case-insensitive, sobre `name`, `asciiname` y `alternatenames` (split `,`). Si múltiples hits, prioriza `PPLC`/`PPLA` (capital) luego mayor `population`.
2. **Extrae** `{name, asciiname, lat, lng, timezone}` — sin `population` (acuerdo punto 4).
3. **Valida Regla del Este** desenrollada (`lib/domain/entities/fogg_route.dart:_isEastward` con `offset+=360`, `currUnwrapped>prev`). Calcula `lng_u` para inserción ordenada. Rechaza si viola East.
4. **Inserta** en `assets/data/locations.json` en posición `lng_u` creciente (antimeridiano `Tokio 139.69 → SF -122.41` con offset). Actualiza `meta.update` a hoy, `version 1.0.0→1.0.1` si cambia. No muta `pubspec.yaml` ni `population`.
5. **Valida** JSON + `FoggRoute.validated` (assert) + `flutter analyze` lógico.
6. **Caché** `SENSIBLE/.cache/city_enrich.json` clave `city.lower()` para idempotencia.

## Rate limiting

- Nominatim: `sleep 1` entre llamadas.
- timeapi.io: `sleep 1`.
- `429` → `backoff 5s` y reintenta 1 vez.

## Archivos del proyecto

- `docs/origenes/cities15000.txt` → fuente offline.
- `assets/data/locations.json` → catálogo destino (esquema 6 claves).
- `SENSIBLE/.cache/city_enrich.json` → caché (ignorado por `.gitignore`).
- `lib/domain/entities/fogg_city.dart` → entidad IANA (`timezone`).
- `lib/services/timezone_service.dart` → deriva offset civil DST-correcto.

## Ejemplos

```bash
python3 .opencode/skills/fogg-city-enricher/enrich.py --city "Bruselas" --dry-run
# → Brussels 50.85045/4.34878 Europe/Brussels East OK → insert idx 1

python3 .opencode/skills/fogg-city-enricher/enrich.py --city "Bruselas"
# inserta real en locations.json, valida East, update meta

python3 .opencode/skills/fogg-city-enricher/enrich.py --retro --dry-run
# verifica 8 existentes: 7 OK + Savile Row MANUAL PRESERVE

python3 .opencode/skills/fogg-city-enricher/enrich.py --city "Savile Row" --dry-run
# miss dump → Nominatim + timeapi.io → 51.5107/-0.141 Europe/London
```

## Límites

- Sin `population` (acuerdo). Si necesita población, consulte `cities15000.txt` col 14 manualmente.
- No persiste offset numérico; la hora civil `-7/+2` se deriva en app vía `TimezoneService`.
- `Savile Row` es manual (no en dump) — se preserva `note` si existe.
