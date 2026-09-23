# Orígenes — cities15000

Fuente impura previa a modelo de dominio. No versionar derivados pesados sin necesidad.

## Ficheros

| Fichero | Descripción | Tamaño | Versionado |
|---------|-------------|--------|------------|
| `cities15000.txt` | Dump GeoNames `cities15000.zip` — 34 148 ciudades >15k hab. (TSV `\t`, UTF-8, 19 cols, sin cabecera) | 8.2 MB | Sí (origen) |
| `cities15000.json` | Derivado generado por `cities_to_json.py` (array JSON 19 claves) | 17 MB minified / 30 MB pretty | No por defecto* |
| `cities15000.no-alts.json` | Derivado ligero sin 11 claves (`alternatenames`, `feature_*`, `country/admin*`, `elevation`, `dem`) — 8 claves restantes — generado por `strip_alternates.py` | 6.1 MB minified / 9 MB pretty | No por defecto* |
| `cities_to_json.py` | Script Python stdlib (TSV→JSON, recomendado) | 12 KB | Sí |
| `strip_alternates.py` | Script Python stdlib (JSON→JSON sin claves superfluas, por defecto 11) | 5.9 KB | Sí |

*Derivados reproducibles. Si necesita ligereza, genere subset con `--fields` y copie a `frontend/assets/`.

## Esquema TSV (GeoNames)

Orden fijo, 19 columnas (`HEADER` en `cities_to_json.py:18`):

```
0 geonameid        int     PK GeoNames (ej. 3040051)
1 name             string  UTF-8 exónimo local (Sarandë)
2 asciiname        string  ASCII (Sarande)
3 alternatenames   string  coma-separada, multialfabeto ('' si vacío)
4 latitude         float   -90..90
5 longitude        float   -180..180 — clave Regla del Este (AGENTS.md)
6 feature_class    char    siempre 'P'
7 feature_code     enum    PPL 53% | PPLA2 20% | PPLA3 8% | PPLA 7% | PPLX 7% …
8 country_code     string  ISO 3166-1 alpha-2 (IN, US, BR…)
9 cc2              string? 99.9% null
10 admin1          string? 99.9% presente
11 admin2          string? 85% (código admin nivel 2)
12 admin3          string? 43% 
13 admin4          string? 9%
14 population       int     0..24 874 500 (45 filas <15k, 3 con 0)
15 elevation       int?    86% null (metros)
16 dem             int?    SRTM; -9999 → null (58 casos, ej. Palm Jumeirah 6691113)
17 timezone        string  IANA (376 zonas, ej. Europe/Andorra)
18 modification_date string ISO 8601 YYYY-MM-DD
```

Validado: 34 148 filas, siempre 19 cols, `geonameid` únicos, UTF-8 intacto.

## Uso recomendado

Opción recomendada para todo (full, tipado, array):

```bash
# Compacto por defecto (17 MB, ideal PWA/Hive)
python3 docs/origenes/cities_to_json.py

# Legible para inspeccionar
python3 docs/origenes/cities_to_json.py --pretty

# Subset ligero para frontend (ej. solo viaje este)
python3 docs/origenes/cities_to_json.py \
  --fields geonameid,name,asciiname,latitude,longitude,country_code,population,timezone \
  --output frontend/assets/cities.json

# Filtrado por tipo (excluir barrios PPLX) y población
python3 docs/origenes/cities_to_json.py --filter-feature PPL,PPLA,PPLA2,PPLC --filter-pop-min 15000

# Mantener alternatenames como string crudo (no recomendado)
python3 docs/origenes/cities_to_json.py --keep-alternates-string
```

### Eliminar claves superfluas (fichero nuevo ligero)

Por defecto se eliminan 11 claves: `alternatenames`, `feature_class`, `feature_code`, `country_code`, `cc2`, `admin1`..`admin4`, `elevation`, `dem` → quedan 8 claves (`geonameid`, `name`, `asciiname`, `latitude`, `longitude`, `population`, `timezone`, `modification_date`) — ahorro ~65% (6.1 MB minified):

```bash
# Genera docs/origenes/cities15000.no-alts.json (8 claves, 6.1 MB minified)
python3 docs/origenes/strip_alternates.py

# Solo alternatenames (comportamiento previo, 18 claves, 11 MB)
python3 docs/origenes/strip_alternates.py --keys alternatenames

# Custom: elegir qué claves quitar
python3 docs/origenes/strip_alternates.py --keys alternatenames,feature_class,feature_code

# Pretty para inspeccionar
python3 docs/origenes/strip_alternates.py --pretty

# Alternativa sin script extra: regenerar directo con --fields (mismo resultado 8 claves)
python3 docs/origenes/cities_to_json.py --fields geonameid,name,asciiname,latitude,longitude,population,timezone,modification_date --output docs/origenes/cities15000.no-alts.json
```

Salida JSON por objeto (ej. `les Escaldes`):

*Full (19 claves, `cities15000.json`):*
```json
{
  "geonameid": 3040051,
  "name": "les Escaldes",
  "asciiname": "les Escaldes",
  "alternatenames": ["Escaldes","Les Escaldes", "..."],
  "latitude": 42.50729,
  "longitude": 1.53414,
  "feature_class": "P",
  "feature_code": "PPLA",
  "country_code": "AD",
  "cc2": null,
  "admin1": "08",
  "admin2": null,
  "admin3": null,
  "admin4": null,
  "population": 15853,
  "elevation": null,
  "dem": 1033,
  "timezone": "Europe/Andorra",
  "modification_date": "2026-04-13"
}
```

*Ligero (8 claves, `cities15000.no-alts.json` tras strip de 11 claves):*
```json
{
  "geonameid": 3040051,
  "name": "les Escaldes",
  "asciiname": "les Escaldes",
  "latitude": 42.50729,
  "longitude": 1.53414,
  "population": 15853,
  "timezone": "Europe/Andorra",
  "modification_date": "2026-04-13"
}
```

Tipos: `geonameid/population` int, `latitude/longitude` float. En full: `elevation/dem` int|null (`dem -9999 → null`), `cc2/admin*` string|null, `alternatenames` string[] (o string si `--keep-alternates-string`).

## Licencia

GeoNames CC-BY 4.0 — atribución requerida si redistribuye derivado.
