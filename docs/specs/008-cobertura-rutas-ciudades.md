# SPEC 008 — Cobertura mínima de rutas por ciudad (entrada y salida)

> **Estado:** Aprobada

> **Depende de:** SPEC 004 (Fogg Sea Routes), SPEC 006 (Fogg Car Routes), SPEC 007 (Visor de rutas terrestres)

> **Fecha:** 2026-10-08

> **Objetivo:** Garantizar que las 307 ciudades de `locations.json` tengan al menos una ruta de entrada y una de salida en la unión de `sea_routes.json` y `car_routes.json`, mediante una pasada automática de cierre, una verificación que falla y un documento de excepciones revisable.

---

## 1. Por qué existe esta especificación

Medido hoy sobre los datos reales: `locations.json` tiene 307 ciudades, `sea_routes.json` 210 rutas y `car_routes.json` 1001 rutas. Combinando mar y tierra, **55 ciudades no tienen ninguna ruta** (ni entrada ni salida) y **4 más tienen salida pero no entrada** (Bombay, Dakar, Jakarta, Quito): 59 ciudades pendientes de 307. Ejemplos de las aisladas: Madrid, Tarifa, Tánger, Norilsk, Honolulu, Auckland, Taipei.

Las validaciones actuales de `validate_dataset` solo comprueban propiedades internas de cada fichero (rangos, anclajes, Regla del Este, límites por origen). Ninguna mira hacia el catálogo: un dataset puede ser perfectamente válido y dejar ciudades huérfanas. Sin cobertura, el juego no podrá construir ningún itinerario que pase por esas ciudades.

La segunda carencia es la dirección: ambas skills favorecen el Este y solo recurren al Oeste cuando un origen no llega a `MIN_ROUTES_PER_ORIGIN`. Eso cubre las salidas mínimas, pero nadie garantiza que una ciudad sea **destino** de algo. Teresina fue el caso que destapó el problema en SPEC 006 §12; hoy quedan 59 casos.

---

## 2. Alcance

**En:**

- **Crea el verificador de cobertura — `tools/route_coverage.py` — lista ciudades sin ruta de entrada o salida** — CLI con `[INFO]/[WARN]/[ERROR]` en castellano, sale con código 2 si hay pendientes
  - **Entrada:** `assets/data/locations.json` + `assets/data/sea_routes.json` + `assets/data/car_routes.json`, resueltas con `PROJECT_ROOT = Path(__file__).resolve().parents[3]` como en las skills
  - **Criterio:** cobertura = unión mar ∪ tierra; una ciudad está cubierta si aparece como `origin` de ≥1 ruta **y** como `destination` de ≥1 ruta

- **Genera el documento de pendientes — `tools/route_coverage.py --write-report` — escribe `docs/ciudades-sin-rutas.md` sin perder decisiones** — el informe y la lista de excepciones son un único fichero
  - **Tabla:** `| Ciudad | Sin salida | Sin entrada | Rutas | Decisión |` con una fila por ciudad descubierta
  - **Preservación:** al regenerar se conserva la columna `Decisión` de las filas existentes; las ciudades ya cubiertas desaparecen de la tabla
  - **Regla máquina:** una ciudad se acepta si su `Decisión` (normalizada, sin acentos, minúsculas) empieza por `excepcion`; todo lo demás (`pendiente`, vacío, texto libre) sigue fallando

- **Cierra las salidas que faltan en carretera — `.opencode/skills/fogg-land-routes/land_route.py --close-gaps` — ruta de salida para toda ciudad sin ella** — pasada posterior al lote normal, no lo sustituye
  - **Selección:** para cada ciudad sin salida, candidatas ordenadas por `haversine`; pool este primero (`0 < deltaLng <= 180`), si ninguna tiene camino, pool oeste (`-180 <= deltaLng < 0`); se elige la más cercana enrutable con `/table` verificado por `/route`
  - **Presupuesto:** como mucho 1 `/table` + 1 `/route` por hueco de salida, a 1,2 s por petición (hoy ≤59 huecos ≈ 2 minutos)

- **Cierra las entradas que faltan en carretera — `land_route.py --close-gaps` — ruta de llegada para toda ciudad sin ella** — mismo flag, inverso del punto anterior
  - **Selección:** para cada ciudad sin entrada, se itera la ciudad origen más cercana con capacidad (≤ `limitPerOrigin` rutas normales) y se comprueba `origen → destino` con `/table` (`destinations=0`) antes de trazar con `/route`
  - **Sin origen con capacidad:** se permite superar `limitPerOrigin` con rutas marcadas `gapClosed`; el límite sigue vigente para las rutas normales

- **Cierra huecos también por mar — `.opencode/skills/fogg-sea-routes/sea_route.py --close-gaps` — análogo sobre `sea_routes.json`** — misma lógica con la malla de `searoute`
  - **Restricción de puerto:** solo ciudades con puerto resuelto (`THRESHOLD_KM` + `FORCED_COASTAL_KM`); las que no lo tienen emiten `[WARN]` y quedan pendientes para el documento
  - **Offline:** `searoute` no tiene rate limit; la pasada marítima no consume red externa

- **Marca las rutas de cierre en los dos JSON — campo `routes[].gapClosed: true` — distingue cierre de lote normal** — esquema aditivo, no breaking
  - **Meta:** `meta.gapClosedRoutes` (recuento) y `meta.coverage` (`cities`, `withoutOutbound`, `withoutInbound`, `exceptions`) al terminar la pasada
  - **`heading`:** `east` o `west` según el signo de `deltaLng`, igual que el lote normal

- **Fallará la validación si queda ciudad descubierta — `validate_dataset` de ambas skills — impide escribir datasets con huecos** — importa el verificador desde `PROJECT_ROOT / "tools"`
  - **Mensaje:** `[ERROR]` con la lista de ciudades sin cobertura y sin `excepción` en `docs/ciudades-sin-rutas.md`; la validación termina con problemas, no sigue de largo

- **Añade un test de Flutter de cobertura — `test/data/route_coverage_test.dart` — rojo si una ciudad pierde entrada o salida** — red final contra regresiones de datos
  - **Lectura:** `dart:io` sobre los tres ficheros desde la raíz del paquete (no pasa por `pubspec.yaml` ni por `rootBundle`)
  - **Excepciones:** aplica la misma regla `excepcion*` de la columna `Decisión`

- **Documenta el cierre de huecos — `SKILL.md` de ambas skills — flag, límites y flujo de excepciones** — incluye el presupuesto de peticiones y la regla de la columna `Decisión`

**Compartido:** esquema v3 de rutas de SPEC 004/006 (solo se añaden campos); `locations.json` en solo lectura; helpers geodésicos ya existentes (`haversine`, `eastward_delta`, `anchor_to_cities`); formato `[INFO]/[WARN]/[ERROR]` y `PROJECT_ROOT` con `parents[3]` de ambas skills; rate limit de OSRM y caché en `SENSIBLE/.cache/`; sin cambios en `lib/`, `pubspec.yaml` ni `tools/locations-map/`.

**Fuera del alcance (para futuras especificaciones):**

- Editar o purgar `assets/data/locations.json` (quitar ciudades descubiertas). El catálogo es el catálogo.
- Cambios en el visor `tools/locations-map` (ya carga los dos ficheros y no distingue `gapClosed`).
- Cambios en la app Flutter: `WorldMapWidget`, `FoggRoute`, `TransportSelector`, `TimeEngine`, `BudgetService`.
- Regenerar los datasets completos desde cero; esta spec solo añade la pasada de cierre.
- Otros perfiles de OSRM, OSRM propio o nuevas fuentes de datos.
- Resolver las excepciones pendientes: el pase manual ciudad a ciudad sobre `docs/ciudades-sin-rutas.md` es del Señor, no de la herramienta.
- Un mecanismo de excepciones distinto del documento (p. ej. un JSON aparte).

---

## 3. Modelo de datos

### 3.1 Adiciones a `assets/data/car_routes.json` y `assets/data/sea_routes.json`

Solo campos nuevos; los ficheros existentes siguen siendo válidos para el visor sin tocar `app.js`.

```jsonc
// meta (añadidos al final del lote de cierre)
{
  "gapClosedRoutes": 42,
  "coverage": { "cities": 307, "withoutOutbound": 0, "withoutInbound": 0, "exceptions": 6 }
}

// routes[] — solo en las rutas creadas por --close-gaps
{
  "origin": "Madrid", "destination": "Valencia", /* campos v3 habituales */
  "heading": "east",          // o "west", coherente con el signo de deltaLng
  "gapClosed": true           // ausente en las rutas del lote normal
}
```

Convenciones:

- `limitPerOrigin` sigue limitando las rutas **normales**; las `gapClosed` no cuentan para el límite (pero sí para la cobertura).
- La Regla del Este (`0 < deltaLng <= 180` con `heading: east`) sigue obligatoria para las rutas normales; solo las `gapClosed` pueden tener `heading: west` sin cumplir el mínimo `minRoutesPerOrigin`.
- `validate_dataset` exige: `gapClosed` booleano si existe, `heading` coherente con `deltaLng` (ya lo hace), extremos anclados a ciudades (ya lo hace).

### 3.2 `docs/ciudades-sin-rutas.md` (nuevo, generado + anotado a mano)

```markdown
# Ciudades sin rutas

> Generado por `tools/route_coverage.py` el 2026-10-08 — 307 ciudades, 59 pendientes.
> Edite solo la columna **Decisión**. Marque `excepción — <motivo>` para aceptar
> una ciudad que no se pueda conectar; el resto de texto es solo notas suyas.
> Regenerar con `python3 tools/route_coverage.py --write-report` conserva esta columna.

| Ciudad | Sin salida | Sin entrada | Rutas | Decisión |
| --- | --- | --- | --- | --- |
| Alofi | sí | sí | 0 | excepción — isla sin red ni puerto |
| Madrid | sí | sí | 0 |  |
```

Reglas:

- La tabla lista **todas** las ciudades descubiertas, con o sin decisión.
- Una ciudad pasa a estar aceptada cuando su `Decisión` normalizada (minúsculas, sin acentos) empieza por `excepcion`.
- El verificador sale con `[ERROR]` (código 2) mientras quede alguna fila sin `excepcion*`.
- Cuando una ciudad queda cubierta, desaparece de la tabla al regenerar; su decisión histórica se pierde a propósito (ya no hace falta).

### 3.3 Estructura efímera del verificador (no persistida)

```python
coverage = {"name": "Madrid", "outbound": 0, "inbound": 0, "total": 0, "decision": ""}
# outbound/inbound: nº de rutas en la unión mar ∪ tierra
# decision: texto de la columna Decisión leído del informe previo ('' si no había)
```

---

## 4. Plan de implementación

Cada paso deja el sistema ejecutable y comprobable.

1. **Esqueleto del verificador — `tools/route_coverage.py` — cobertura calculable hoy mismo** — `load_locations()`, `load_routes(path)`, `compute_coverage(cities, sea, car)` que devuelve `outbound`/`inbound` por ciudad; CLI sin flags que imprime `[INFO]` con totales y `[ERROR]` con la lista de pendientes; exit code 2 si los hay. Prueba: `python3 tools/route_coverage.py` reporta 59 pendientes (55 sin ninguna ruta, 4 solo sin entrada) y sale con 2.

2. **Escritura del informe con decisiones preservadas — `tools/route_coverage.py --write-report` — `docs/ciudades-sin-rutas.md` reanudable** — lee la tabla existente si la hay, mantiene la columna `Decisión`, reescribe cabecera y filas. Prueba: marcar `excepción — prueba` en una ciudad, regenerar, la marca sigue ahí y esa ciudad deja de generar `[ERROR]`.

3. **Cierre de salidas en carretera — `land_route.py --close-gaps` — salida para toda ciudad que no la tenga** — nuevo flag en `argparse`; calcula las ciudades descubiertas con la misma función de cobertura, resuelve pool este → pool oeste por `haversine`, verifica con `/table` y traza con `/route` (`overview=simplified`, `anchor_to_cities`, rate limit y caché existentes); escribe `gapClosed: true`. Prueba: Madrid pasa a tener salida y `car_routes.json` sigue pasando `validate_dataset`.

4. **Cierre de entradas en carretera — `land_route.py --close-gaps` — llegada para toda ciudad que no la tenga** — inverso del paso anterior: para cada ciudad sin entrada, candidatas origen por distancia, `/table` con `destinations=0`, ruta con destino final; respeta `limitPerOrigin` y solo lo supera con rutas `gapClosed`. Prueba: Bombay, Dakar, Jakarta y Quito pasan a tener entrada.

5. **Cierre marítimo — `sea_route.py --close-gaps` — misma pasada sobre `sea_routes.json`** — reutiliza `resolve_ports`, `select_routes` y `anchor_to_cities`; ciudades sin puerto emiten `[WARN]` y quedan pendientes. Prueba: las islas con puerto cubiertas desaparecen del informe; las sin puerto siguen con `[WARN]`.

6. **Regenera el informe tras las dos pasadas — `tools/route_coverage.py --write-report` — lista real de lo que queda** — ejecutar cierres de tierra, después de mar, después el informe. Prueba: la tabla baja de 59 filas a las ciudades genuinamente inconexas (islas sin red y sin puerto).

7. **Integra la cobertura en `validate_dataset` — ambos skills — fallan ante huecos no excepcionados** — import de `tools/route_coverage.py` vía `PROJECT_ROOT / "tools"` insertado en `sys.path`; se ejecuta al final de la validación y añade sus problemas a la lista. Prueba: borrar manualmente una ruta de cobertura en una copia → la validación devuelve el `[ERROR]` con el nombre de la ciudad.

8. **Pase manual del Señor (tarea humana) — `docs/ciudades-sin-rutas.md` — 0 pendientes sin excepción** — ciudad a ciudad, o se resuelve añadiendo rutas o se marca `excepción — <motivo>`. Prueba: `python3 tools/route_coverage.py` sale con código 0 y `[INFO] 0 pendientes`.

9. **Test de Flutter — `test/data/route_coverage_test.dart` — red de regresión sobre los datos** — lee los tres JSON con `dart:io`, aplica la regla `excepcion*`, `expect(pendientes, isEmpty)` con mensaje que lista las ciudades. Prueba: `flutter test` verde; romper un fichero a mano lo pone rojo.

10. **Documenta y verifica — `SKILL.md` de ambas skills + `README.md` — flujo reproducible** — flag `--close-gaps`, presupuesto de peticiones, regla de la columna `Decisión` y cómo regenerar el informe. Prueba: `flutter analyze`, `flutter test` y revisión del diff (sin secretos, sin `SENSIBLE/`).

---

## 5. Criterios de aceptación

- [ ] `python3 tools/route_coverage.py` imprime `[INFO]` con el recuento de ciudades, rutas de salida y rutas de entrada, y sale con código 2 mientras haya pendientes.
- [ ] Con los datos actuales, el verificador identifica exactamente las 59 ciudades descubiertas de hoy (55 sin ninguna ruta + Bombay, Dakar, Jakarta, Quito sin entrada).
- [ ] `--write-report` crea `docs/ciudades-sin-rutas.md` con la tabla `| Ciudad | Sin salida | Sin entrada | Rutas | Decisión |` y la cabecera de uso.
- [ ] Regenerar el informe conserva la columna `Decisión` escrita a mano; una ciudad marcada `excepción — …` deja de generar `[ERROR]` sin quitar su fila.
- [ ] `land_route.py --close-gaps` añade rutas con `gapClosed: true`, `heading` coherente con `deltaLng`, extremos anclados a ciudades y respeta 1 petición/segundos con la caché existente.
- [ ] Tras la pasada de tierra, ninguna ciudad de `locations.json` carece de salida por tierra o mar salvo las que el verificador lista como pendientes.
- [ ] Tras la pasada de mar, toda ciudad con puerto resuelto tiene entrada saliente o entrante según le falte; las ciudades sin puerto emiten `[WARN]` y no abortan la pasada.
- [ ] Las rutas previas (210 marítimas y 1001 terrestres) no cambian de contenido; solo se añaden campos a `meta`.
- [ ] `meta.gapClosedRoutes` y `meta.coverage` existen en ambos ficheros tras la pasada y coinciden con el recuento real.
- [ ] `validate_dataset` de cualquiera de las dos skills devuelve `[ERROR]` con el nombre de la ciudad si una ciudad queda sin entrada o salida y no está marcada `excepción` en `docs/ciudades-sin-rutas.md`.
- [ ] `python3 tools/route_coverage.py` termina con código 0 e `[INFO] 0 pendientes` una vez completado el pase manual.
- [ ] `test/data/route_coverage_test.dart` pasa con los tres ficheros reales y falla (listando ciudades) si se elimina una ruta de cobertura.
- [ ] `flutter analyze` y `flutter test` terminan correctamente; no se modifica `pubspec.yaml`, `lib/`, `tools/locations-map/` ni `assets/data/locations.json`.
- [ ] `SKILL.md` de `fogg-land-routes` y `fogg-sea-routes` documenta `--close-gaps`, su presupuesto de peticiones y la regla de excepciones.
- [ ] El diff no contiene secretos ni ficheros de `SENSIBLE/`.

---

## 6. Decisiones tomadas y descartadas

- **Sí:** pasada posterior de cierre de huecos (`--close-gaps`) en las dos skills (opción B). Por qué: ataca la causa sin tocar el lote normal ni su presupuesto de peticiones; cada skill cierra sus propios huecos y una ciudad puede quedar cubierta por mar y por tierra por separado. **No:** ampliar el pool de 5 candidatos del lote normal — encarece cada regeneración completa y no garantiza nunca la cobertura de **llegada**.
- **Sí:** relajar la dirección solo dentro del cierre (opción C): este primero, después cualquier dirección con `|deltaLng| <= 180`. Por qué: el cierre existe exactamente para esos casos y `heading` ya documenta el signo. **No:** relajar la Regla del Este del lote normal ni de `FoggRoute.validated` — sigue siendo la invariante del juego (`lib/domain/entities/fogg_route.dart:106`). **Consecuencia registrada:** una ruta con `heading: west` (ya existen) **nunca podrá formar parte de un `FoggRoute` validado**, porque `_isEastward` exige `lng` creciente; las rutas oeste son cobertura de fichero, no tramo de itinerario.
- **Sí:** cobertura = unión mar ∪ tierra, con ≥1 salida y ≥1 entrada. Por qué: lo pedido por el Señor — "no importa si es por mar o por tierra". **No:** exigir ruta marítima y terrestre por separado — duplicaría el trabajo sin beneficio de juego.
- **Sí:** `docs/ciudades-sin-rutas.md` como informe **y** archivo de excepciones, con la columna `Decisión` preservada entre regeneraciones. Por qué: una sola fuente de verdad, el documento es legible para el Señor y parseable para la máquina. **No:** un `coverage_exceptions.json` aparte — dos ficheros para el mismo estado se desincronizan. **No:** informe sin persistencia — sin la columna no hay forma de que la validación acepte excepciones.
- **Sí:** regenerar el informe con la herramienta (el Señor solo edita la columna). Por qué: así el documento siempre refleja el estado real de los datos. **No:** documento creado y mantenido a mano — se pondría viejo en la primera regeneración de rutas.
- **Sí:** la validación de cobertura **falla** (`[ERROR]`), integrada en `validate_dataset`. Por qué: un aviso en un log es justo lo que nadie lee (precedente SPEC 006 §6). **No:** warning tolerante — dejaría regenerar datasets rotos.
- **Sí:** test de Flutter sobre los ficheros con `dart:io`. Por qué: es la red que impide mergear datos que rompan la cobertura; coste bajo, sin tocar `pubspec.yaml`. **No:** verificación solo en Python — nada la ejecuta en el flujo normal de `flutter test`.
- **Sí:** módulo único `tools/route_coverage.py` importado por ambas skills vía `PROJECT_ROOT / "tools"`. Por qué: DRY — el criterio de cobertura debe ser idéntico para mar y tierra, y ya existe el patrón `PROJECT_ROOT` con `parents[3]` en los dos scripts. **No:** duplicar la función en cada skill — la lógica es más grande que un `haversine` y divergiría.
- **Sí:** `limitPerOrigin` no cuenta las rutas `gapClosed`. Por qué: el límite existe para acotar el lote normal; el cierre es una necesidad puntual y medible. **No:** subir el límite global — arrastraría el techo de peticiones a todas las regeneraciones.
- **Sí:** el pase manual del Señor queda como paso del plan (paso 8) y no se automatiza. Por qué: decisión explícita — "las haré una a una".
- **Nota:** el catálogo tiene hoy 307 ciudades, no las 304 que documenta `AGENTS.md`; el verificador lee el fichero, no el número histórico.

---

## 7. Riesgos identificados

| Riesgo | Mitigación |
| --- | --- |
| El cierre puede no bastar: islas sin red rodada ni puerto (Alofi, Avarua…) no tienen solución técnica | Es el motivo del documento: quedan como `[WARN]` + fila pendiente y el Señor decide `excepción` o retira la ciudad a mano. El verificador distingue "pendiente" de "imposible" por la columna, no por un veredicto automático. |
| `validate_dataset` pasará a fallar mientras queden pendientes sin excepción | Es intencionado: el paso 8 del plan (pase manual) precede a la integración efectiva de la validación en el flujo de trabajo; además el `[ERROR]` lista todas las ciudades de una vez, no una por ejecución. |
| Las rutas con `heading: west` no pueden usarse en un `FoggRoute` validado | Decisión registrada en §6; son cobertura de fichero. Si el motor de itinerarios necesita tramos oestes, eso es otra especificación (reformular `_isEastward`). |
| Coste de OSRM en el cierre: ~59 huecos × (1 tabla + 1 ruta) por eje | Presupuesto ≤ ~250 peticiones ≈ 5 min a 1,2 s, con la misma caché, backoff y `User-Agent` existentes; muy por debajo del lote completo (1.402 peticiones). |
| Regenerar el informe podría pisar decisiones si cambia el formato de la tabla | El parser lee por encabezado de columna (`Decisión`), no por posición; el plan verifica la preservación en el paso 2 antes de escribir nada más. |
| El test de Flutter lee ficheros fuera de `pubspec.yaml` | `flutter test` se ejecuta con cwd en la raíz del paquete, donde ya viven `assets/data/*.json` y `docs/`; si algún día se ejecuta desde otro directorio, el test falla de forma ruidosa y localizable. |
| Dos skills importando un módulo de `tools/` crea acoplamiento fuera de `.opencode/skills/` | Ya comparten `locations.json`, el esquema v3 y el patrón `PROJECT_ROOT`; el módulo es de solo lectura y sin dependencias (stdlib), así que una skill copiada fuera del repo solo pierde la validación de cobertura, no el trazado. |

---

## 8. Lo que **no** está en esta especificación

- Editar, podar o reordenar `assets/data/locations.json`.
- Cambios en `tools/locations-map`, en el visor o en sus botones.
- Cambios en `lib/`, `pubspec.yaml` o los assets declarados de Flutter.
- Regeneración completa de `sea_routes.json` o `car_routes.json` (solo la pasada `--close-gaps`).
- Perfiles distintos de `car`, OSRM propio o nuevas fuentes de trazado.
- El pase manual de excepciones del Señor (paso 8 del plan): esta spec entrega la herramienta y el documento, él decide.
- Itinerarios del juego: `FoggRoute`, `_isEastward`, `TransportSelector`, presupuesto o tiempo de viaje.

Cada uno, si aterriza, irá en su propia especificación.

---

## 9. Referencias

- `assets/data/locations.json` — 307 ciudades, fuente del catálogo.
- `assets/data/sea_routes.json` — 210 rutas, esquema v3 (SPEC 004).
- `assets/data/car_routes.json` — 1001 rutas, esquema 1.1.0 (SPEC 006 §12).
- `.opencode/skills/fogg-land-routes/land_route.py:277` — `build_pool(direction)`, base de la selección de candidatos del cierre.
- `.opencode/skills/fogg-land-routes/land_route.py:458` — `validate_dataset`, que pasará a importar la cobertura.
- `.opencode/skills/fogg-land-routes/land_route.py:49` — `PROJECT_ROOT` con `parents[3]`, patrón a replicar en `tools/route_coverage.py`.
- `.opencode/skills/fogg-sea-routes/sea_route.py:292` — `select_routes(direction)`, análogo marítimo.
- `.opencode/skills/fogg-sea-routes/sea_route.py:384` — `validate_dataset` marítimo.
- `.opencode/skills/fogg-sea-routes/sea_route.py:533` — `resolve_ports`, restricción de puerto del cierre marítimo.
- `docs/specs/006-fog-car-routes.md:278` — addendum §12: pool oeste, `heading` y el precedente de Teresina (ciudad solo como destino).
- `lib/domain/entities/fogg_route.dart:106` — `_isEastward`, invariante que las rutas oeste no pueden satisfacer.
- `AGENTS.md` — sin avión, naming `Fogg*`, verificación con `flutter analyze` y `flutter test`.

---

## 10. Preguntas abiertas (resueltas por esta especificación)

- Solo diagnóstico o también arreglo → también arreglo: ≥1 salida y ≥1 entrada por ciudad.
- Mecanismo de cierre → B (pasada posterior de cierre) y C (relajación direccional), ambos aceptados.
- Ciudades que no se puedan conectar → `docs/ciudades-sin-rutas.md`, generado por la herramienta con columna `Decisión` para el pase manual uno a uno del Señor.
- Dónde vive la verificación → script Python con `[INFO]/[WARN]/[ERROR]` + `validate_dataset` que falla + test de Flutter.
- Criterio de cobertura → unión mar ∪ tierra; no importa el modo de transporte.
- Orden → primero máquina (pasadas de cierre), después el pase manual sobre el residuo.
- Alcance de la automatización → en las dos skills.
- Próximo número de spec: `008`, slug `cobertura-rutas-ciudades`.
