# SPEC 013 — Consumo de rutas reales y selector de transporte

> **Estado:** Implementada

> **Depende de:** SPEC 012 (bucle de juego, TimeEngine, BudgetService, GameSession), SPEC 004 (sea_routes.json), SPEC 006 (car_routes.json), SPEC 010 (rail_routes.json), SPEC 001 (WorldMapWidget, AppColors)

> **Fecha:** 2026-10-21

> **Objetivo:** Cargar en la app Flutter las rutas reales (mar, tierra, raíl) y construir un `TransportSelector` que ofrezca destinos hacia el Este con vehículos derivados de ellas, sustituyendo los mocks de `GameSession`.

> **Nota de decisión (2026-10-23):** el modo «a pie» (`foot`) y las rutas peatonales quedan **descartados**. No se implementará `TransportMode.foot` ni se generará `foot.json`; las menciones a `foot` de esta spec se conservan como registro histórico.

---

## 1. Por qué existe esta especificación

El bucle de juego (SPEC 012) ya funciona: tiempo escalado, presupuesto, fatiga y transiciones. Pero los candidatos de destino y sus vehículos son **mocks** (`_buildOptions` inventa ship/train con precios y duraciones fijos, y solo 8 ciudades hardcodeadas). Sin consumo de las rutas reales generadas en SPEC 004/006/010, el juego no avanza por el mundo real: cualquier ciudad costera ofrece los mismos dos barcos/trenes inventados, y los 304 orígenes con rutas reales quedan sin usar. Esta especificación cierra ese hueco: la app lee los JSON de rutas, los indexa por origen y el `TransportSelector` construye `DestinationOption` reales (modos ship/car/train según la ruta disponible, más foot siempre), con duración y precio derivados de la distancia y de tarifas por modo.

---

## 2. Alcance

**En:**

- **Declara los JSON de rutas como assets — `pubspec.yaml` — `rootBundle` puede cargarlos** — añade `assets/data/sea_routes.json`, `assets/data/car_routes.json` y `assets/data/rail_routes.json` a la lista de `assets` (junto a `locations.json`). Sin esto no hay consumo posible.
- **Crea el modelo de ruta real — `lib/domain/models/route_entry.dart` — parsea los 3 JSON con un contrato común** — `RouteEntry` con `origin`, `destination`, `distanceKm`, `durationHours` (nullable), `heading`, `mode` (derivado del fichero) y `geometry`. `RouteCatalog.load(AssetBundle)` lee los 3 ficheros, valida mínimamente y devuelve el catálogo indexado por origen (mapa `origin → List<RouteEntry>`). Prueba: `flutter test test/services/route_catalog_test.dart`.
- **Crea el selector de transporte — `lib/services/transport_selector.dart` — destinos hacia el Este con vehículos reales** — `TransportSelector.optionsFor(FoggCity current, {int limit = 3})` devuelve hasta `limit` `DestinationOption` para las ciudades con lng desenrollada mayor que la actual que tengan al menos una ruta real; cada `VehicleOption` se construye a partir de la ruta (ship/car/train) más un foot siempre, con duración y precio derivados. Prueba: `flutter test test/services/transport_selector_test.dart`.
- **Define tarifas y velocidades por modo — `lib/services/transport_selector.dart` (TariffTable) — precio y duración deterministas** — tabla por `TransportMode` con `pricePerKm` (€/km) y `speedKmh`; duración = `durationHours` del JSON si existe, si no `distanceKm / speedKmh`. Foot usa distancia geodésica (Haversine) y 5 km/h. Sleeper: ship y train `true`; car y foot `false`.
- **Integra el selector en `GameSession` — `lib/services/game_session.dart` — `_buildOptions` deja de ser mock** — añade parámetro opcional `TransportSelector? transportSelector`; si presente usa `optionsFor(current)`, si no mantiene el fallback mock actual (compatibilidad con tests existentes). Prueba: `flutter test test/services/game_session_test.dart` sigue verde.
- **Expone el catálogo vía Riverpod — `lib/presentation/providers/route_catalog_provider.dart` — carga única y selector derivado** — `routeCatalogProvider` (FutureProvider) carga los 3 JSON una sola vez; `transportSelectorProvider` (Provider nullable) devuelve `TransportSelector` cuando el catálogo está listo o `null` mientras carga. `gameSessionProvider` pasa el selector (nullable) al constructor.
- **Añade tests TDD — `test/services/route_catalog_test.dart`, `test/services/transport_selector_test.dart`** — parseo de los 3 JSON, indexación por origen, Regla del Este desenrollada, derivación de duración/precio, foot siempre presente, fallback cuando no hay rutas.
- **Mantiene los modos sin rutas reales como mocks — balloon, horse, camel, motorcycle siguen fuera** — no se generan rutas para ellos; quedan reservados para v1/Final. No se eliminan de `TransportMode`.

**Compartido:** `FoggCity`, `FoggRoute`/Regla del Este desenrollada, `DestinationOption`/`VehicleOption`, `TransportMode` (8 valores intactos), `TimezoneService`, `GameSession` (alias `foggStatusProvider` intacto), `AppColors`. Sin nuevas dependencias. Sin cambios en `tools/`, `assets/data/` (solo lectura) ni skills.

**Fuera del alcance (para futuras especificaciones):**

- Auto-reserva del vehículo más caro en la UI (regla asíncrona) y preselección por defecto en `FoggStatusPage`.
- `EventEngine` (retraso, tormenta, huelga, frontera, avería) y Open-Meteo vivo.
- `Hive` cache offline + sincronización.
- PWA (`manifest.json`, service worker, iconos).
- `DiaryService` + `StoryGenerator`.
- Modos balloon/horse/camel/motorcycle con rutas reales.
- Persistencia del catálogo entre sesiones.
- Consumo de rutas en `WorldMapWidget` (capa de rutas en el mapa de juego).

---

## 3. Modelo de datos

### 3.1 Ruta real (`lib/domain/models/route_entry.dart`)

```dart
enum RouteSource { sea, car, rail }

class RouteEntry {
  const RouteEntry({
    required this.source,
    required this.origin,
    required this.destination,
    required this.distanceKm,
    this.durationHours,
    required this.heading, // 'east' | 'west'
    required this.geometry, // lista de [lng, lat]
  });

  final RouteSource source;
  final String origin;
  final String destination;
  final double distanceKm;
  final double? durationHours;
  final String heading;
  final List<List<double>> geometry;

  TransportMode get mode => switch (source) {
        RouteSource.sea => TransportMode.ship,
        RouteSource.car => TransportMode.car,
        RouteSource.rail => TransportMode.train,
      };
}
```

### 3.2 Catálogo (`lib/services/route_catalog.dart`)

```dart
class RouteCatalog {
  RouteCatalog(this.byOrigin);
  final Map<String, List<RouteEntry>> byOrigin; // clave = nombre de ciudad origen

  List<RouteEntry> routesFrom(String origin) => byOrigin[origin] ?? const [];

  static Future<RouteCatalog> load(AssetBundle bundle) async {
    // lee sea_routes.json, car_routes.json, rail_routes.json
    // valida meta/estructura mínima; ignora ficheros ausentes (lista vacía)
    // devuelve byOrigin fusionado (un origen puede tener rutas de varios modos)
  }
}
```

### 3.3 Tarifas (`lib/services/transport_selector.dart`)

```dart
class Tariff {
  const Tariff({required this.pricePerKm, required this.speedKmh, required this.sleeper});
  final double pricePerKm; // €/km
  final double speedKmh;   // km/h (solo si no hay durationHours)
  final bool sleeper;
}

class TariffTable {
  static const defaults = <TransportMode, Tariff>{
    TransportMode.ship: Tariff(pricePerKm: 1.2, speedKmh: 25, sleeper: true),
    TransportMode.train: Tariff(pricePerKm: 0.8, speedKmh: 80, sleeper: true),
    TransportMode.car: Tariff(pricePerKm: 0.6, speedKmh: 60, sleeper: false),
    TransportMode.foot: Tariff(pricePerKm: 0.5, speedKmh: 5, sleeper: false),
  };
}
```

### 3.4 Selector

```dart
class TransportSelector {
  TransportSelector({required this.catalog, this.tariffs = TariffTable.defaults});
  final RouteCatalog catalog;
  final Map<TransportMode, Tariff> tariffs;

  List<DestinationOption> optionsFor(FoggCity current, {int limit = 3}) {
    // 1. candidatos con lng desenrollada > current.lng (Regla del Este)
    // 2. filtrar los que tengan ≥1 ruta real en catalog
    // 3. ordenar por longitud desenrollada ascendente, take(limit)
    // 4. por cada destino: vehicles = rutas reales disponibles (dedup por mode) + foot
    //    duration = route.durationHours ?? distanceKm / speedKmh
    //    price = (distanceKm * pricePerKm).round()
    //    departureHour/Minute por modo (ship 8:00, train 9:30, car 7:00, foot 6:00)
  }
}
```

### 3.5 Integración `GameSession`

```dart
class GameSession {
  GameSession({
    required this.timeEngine,
    required this.budget,
    List<FoggCity>? cities,
    TransportSelector? transportSelector, // NUEVO, opcional
  });
  // _buildOptions usa transportSelector.optionsFor(current) si != null
  // si null o lanza, fallback al mock actual (8 ciudades + ship/train)
}
```

### 3.6 Providers (`lib/presentation/providers/route_catalog_provider.dart`)

```dart
final routeCatalogProvider = FutureProvider<RouteCatalog>((ref) async {
  return RouteCatalog.load(rootBundle);
});

final transportSelectorProvider = Provider<TransportSelector?>((ref) {
  final catalog = ref.watch(routeCatalogProvider).valueOrNull;
  if (catalog == null) return null;
  return TransportSelector(catalog: catalog);
});
```

`gameSessionProvider` pasa `transportSelector: ref.watch(transportSelectorProvider)`.

Convenciones:
- Tiempo y distancia en unidades del JSON (km, horas). Precio en € entero.
- `RouteCatalog.load` ignora ficheros ausentes (lista vacía) y campos desconocidos; no lanza por rutas individuales inválidas (las salta con log).
- Foot siempre se añade para cada destino candidato, con distancia geodésica (Haversine) y tarifa foot.
- La Regla del Este usa longitud desenrollada, como en `FoggRoute.validated`.
- `kReleaseMode` no afecta al catálogo.

---

## 4. Plan de implementación

1. **Declara assets — `pubspec.yaml` — añade los 3 JSON a `assets`** — ejecuta `flutter pub get`. Prueba: `flutter analyze` sin errores.
2. **Crea `RouteEntry` — `lib/domain/models/route_entry.dart` — modelo + enum `RouteSource`**. Prueba: `flutter analyze`.
3. **Crea `RouteCatalog` — `lib/services/route_catalog.dart` — `load(AssetBundle)` lee y fusiona los 3 JSON** — parsea `routes[].origin/destination/distanceKm/durationHours/heading/geometry`; asigna `source` por fichero; ignora ficheros ausentes y rutas inválidas. Prueba: `flutter test test/services/route_catalog_test.dart` (incluye carga de los 3 assets reales).
4. **Crea `test/services/route_catalog_test.dart` (TDD)** — parseo de `sea_routes.json`/`car_routes.json`/`rail_routes.json`, indexación por origen, conteo de rutas, `durationHours` nullable en marítimas, campos desconocidos aceptados. Ejecutar `flutter test test/services/route_catalog_test.dart`.
5. **Crea `TariffTable` + `TransportSelector` — `lib/services/transport_selector.dart`** — tarifas por modo, `optionsFor` con Regla del Este desenrollada, dedup por modo, foot siempre, derivación de duración/precio, departureHour/Minute por modo. Prueba: `flutter analyze`.
6. **Crea `test/services/transport_selector_test.dart` (TDD)** — 3 destinos hacia el Este, solo ciudades con ruta real, ship/car/train según disponibilidad, foot siempre, precio = round(km * tarifa), duración de marítimas estimada por velocidad, Regla del Este cruzando antimeridiano. Ejecutar `flutter test test/services/transport_selector_test.dart`.
7. **Integra en `GameSession` — `lib/services/game_session.dart` — parámetro opcional `transportSelector`** — `_buildOptions` usa selector si presente; fallback mock si null o si el selector devuelve lista vacía. Mantén firma compatible (parámetro con default null). Prueba: `flutter test test/services/game_session_test.dart` sigue verde.
8. **Crea providers — `lib/presentation/providers/route_catalog_provider.dart`** — `routeCatalogProvider` (FutureProvider) + `transportSelectorProvider` (Provider nullable). Modifica `gameSessionProvider` para pasar el selector.
9. **Ejecuta `flutter analyze` y `flutter test`** — objetivo: 0 errores nuevos (solo info preexistente) y todos los tests verdes.

---

## 5. Criterios de aceptación

- [ ] `pubspec.yaml` declara `assets/data/sea_routes.json`, `assets/data/car_routes.json` y `assets/data/rail_routes.json`; `flutter pub get` no falla.
- [ ] `RouteCatalog.load(rootBundle)` carga los 3 ficheros sin lanzar y devuelve ≥ 1 ruta por al menos 200 orígenes distintos.
- [ ] Las rutas marítimas tienen `durationHours == null` y las terrestres/ferroviarias `durationHours != null` (según el JSON).
- [ ] `TransportSelector.optionsFor(current)` devuelve ≤ 3 destinos, todos con lng desenrollada mayor que `current.lng` (Regla del Este, incluido cruce de antimeridiano).
- [ ] Solo aparecen destinos que tienen al menos una ruta real en el catálogo; ciudades sin ruta se omiten.
- [ ] Cada `DestinationOption` incluye los modos disponibles según las rutas reales (ship si hay sea route, car si hay car route, train si hay rail route) más foot siempre.
- [ ] `VehicleOption.duration` = `durationHours` del JSON cuando existe; si no, `distanceKm / speedKmh` del modo.
- [ ] `VehicleOption.price` = `round(distanceKm * pricePerKm)` del modo correspondiente.
- [ ] Sleeper es `true` para ship y train, `false` para car y foot.
- [ ] `departureHour`/`departureMinute` no son null para los 4 modos (ship 8:00, train 9:30, car 7:00, foot 6:00).
- [ ] Si `transportSelector` es null, `GameSession._buildOptions` mantiene el comportamiento mock actual (tests existentes siguen verdes).
- [ ] `routeCatalogProvider` carga una sola vez; `transportSelectorProvider` devuelve `null` mientras carga y un `TransportSelector` cuando termina.
- [ ] `flutter analyze` no introduce errores nuevos (solo el info preexistente de `prefer_const_constructors`).
- [ ] `flutter test` pasa con todos los tests verdes (incluyendo los nuevos `route_catalog_test` y `transport_selector_test`).
- [ ] No se modifican `assets/data/*.json`, `tools/`, ni skills de generación.

---

## 6. Decisiones tomadas y descartadas

- **Sí:** cargar los 3 JSON vía `rootBundle` declarándolos en `pubspec.yaml`. Por qué: es el mecanismo estándar de Flutter y ya se usa para `locations.json`; evita dependencias nuevas.
- **No:** fetch HTTP en runtime. Por qué: los datos son estáticos y versionados; fetch añade latencia y fallo offline.
- **Sí:** `RouteEntry.mode` derivado de la fuente (sea→ship, car→car, rail→train). Por qué: el JSON no lleva un campo `mode` unificado; la fuente es inequívoca.
- **No:** unificar los 3 JSON en uno solo. Por qué: cada uno tiene esquema y ciclo de generación propio (specs 004/006/010); fusionarlos rompería las skills.
- **Sí:** tarifas por modo en `TariffTable.defaults` (€/km y km/h). Por qué: el JSON no trae precio ni velocidad; una tabla centralizada es editable y testeable. Valores: ship 1.2 €/km @25 km/h, train 0.8 @80, car 0.6 @60, foot 0.5 @5.
- **No:** precio aleatorio o por dificultad. Por qué: determinismo necesario para tests y balance.
- **Sí:** foot siempre disponible para cada destino, con distancia geodésica (Haversine) y tarifa foot. Por qué: el MVP exige 3 modos (train/ship/foot) y foot no tiene ruta real; estimar por distancia recta es suficiente y mantiene el catálogo de 3.
- **No:** generar rutas a pie reales. Por qué: fuera de alcance; OSRM peatón añadiría otra skill y otro JSON.
- **Sí:** `durationHours` del JSON cuando existe (car, rail); estimación por velocidad para sea y foot. Por qué: el dato real es más preciso; la estimación cubre los casos sin dato.
- **Sí:** `transportSelector` opcional en `GameSession` con fallback mock. Por qué: no rompe los tests existentes de SPEC 012 y permite carga asíncrona del catálogo.
- **No:** recrear `GameSession` al cargar el catálogo perdiendo estado. Por qué: se acepta la recreación en MVP (riesgo documentado); en v1 se hará mutable con `setTransportSelector`.
- **Sí:** hasta 3 destinos por llegada, los más cercanos hacia el Este por longitud desenrollada. Por qué: coherente con el comportamiento actual de `_buildOptions`.
- **No:** mostrar todos los destinos con ruta. Por qué: la UI actual está diseñada para 3 tarjetas; ampliarla es otra spec.
- **Sí:** deduplicar vehículos por modo (si hay varias rutas marítimas al mismo destino, solo un ship). Por qué: la UI muestra un chip por modo; varias rutas al mismo destino se colapsan al más corto (menor `distanceKm`).
- **No:** mostrar la ruta elegida en el mapa de juego. Por qué: consumo visual en `WorldMapWidget` es una spec mayor (fuera de alcance).
- **Sí:** ignorar ficheros ausentes y rutas individuales inválidas (saltar, no lanzar). Por qué: robustez en dev; el catálogo parcial sigue siendo útil.
- **No (decisión posterior, 2026-10-23):** implementar el modo «a pie» ni rutas peatonales. Se descarta por completo — ni `TransportMode.foot` ni `foot.json`. Sustituye a la decisión «foot siempre disponible» de esta spec (ver nota de cabecera).

---

## 7. Riesgos identificados

| Riesgo | Mitigación |
|---|---|
| `car_routes.json` pesa ~3 MB y ralentiza el arranque | Carga en `FutureProvider` (no bloquea `main()`); spinner en UI mientras carga; fallback mock hasta que termine. |
| Recreación de `GameSession` al cambiar selector pierde estado de partida | Aceptado en MVP; en v1 hacer `transportSelector` mutable con `setTransportSelector` sin recrear sesión. |
| Duplicados por modo al mismo destino | Dedup por modo eligiendo la ruta de menor `distanceKm`. |
| Regla del Este mal aplicada en candidatos | Reutilizar desenrollado de `FoggRoute` y tests con cruce de antimeridiano (Tokio → San Francisco). |
| `durationHours` null en marítimas rompe `VehicleOption.duration` | Estimación por velocidad; test verifica que nunca es null en el `VehicleOption`. |
| Precio 0 o negativo por tarifa mal configurada | Tarifas positivas en `TariffTable.defaults`; test verifica `price > 0`. |
| Ficheros ausentes en tests de widget | `RouteCatalog.load` tolera ausencia; tests inyectan catálogo mock. |
| `rootBundle` no disponible en tests puros | `RouteCatalog.load` acepta cualquier `AssetBundle`; tests usan `MemoryAssetBundle` o un bundle fake. |

---

## 8. Lo que **no** está en esta especificación

- Auto-reserva del vehículo más caro en la UI y preselección por defecto.
- `EventEngine`, Open-Meteo vivo y `WeatherSnapshot` poblado.
- `Hive` cache offline y sincronización.
- PWA (`manifest.json`, service worker, iconos).
- `DiaryService` + `StoryGenerator`.
- Modos balloon, horse, camel, motorcycle con rutas reales.
- Visualización de rutas en `WorldMapWidget`.
- Persistencia del catálogo entre sesiones.
- Edición o regeneración de los JSON de rutas.

Cada uno, si aterriza, irá en su propia especificación.

---

## 9. Referencias

- `lib/services/game_session.dart:150-180` — `_buildOptions` mock actual a sustituir.
- `lib/domain/entities/destination_option.dart` — `VehicleOption`, `DestinationOption`.
- `lib/domain/entities/transport_mode.dart` — 8 modos (sin flight).
- `lib/domain/entities/fogg_city.dart` — `name`, `lat`, `lng`, `timezone`.
- `lib/domain/entities/fogg_route.dart:12` — `FoggRoute.validated` y `_isEastward` (longitud desenrollada).
- `lib/presentation/providers/game_notifier.dart:21-26` — `gameSessionProvider` a modificar.
- `lib/services/time_engine.dart` — `nextScheduledDeparture` (usa departureHour/Minute).
- `assets/data/sea_routes.json` — esquema v3.1.0 (sin `durationHours`).
- `assets/data/car_routes.json` — v1.1.0 (con `durationHours`).
- `assets/data/rail_routes.json` — v1.0.0 (con `durationHours`).
- `pubspec.yaml:64-65` — lista de assets a ampliar.
- `docs/specs/012-core-game-loop-time-budget.md` — bucle de juego base.
- `docs/specs/004-fogg-sea-routes.md`, `006-fog-car-routes.md`, `010-fogg-rail-routes.md` — generación de datos.

---

## 10. Preguntas abiertas (resueltas)

- ¿Fuente de datos? → Los 3 JSON existentes (`sea_routes.json`, `car_routes.json`, `rail_routes.json`), solo lectura.
- ¿Precio? → Tarifa €/km por modo en `TariffTable.defaults`, determinista.
- ¿Duración marítima? → Estimada por velocidad (25 km/h) al no existir `durationHours`.
- ¿Foot? → Siempre, con distancia geodésica y tarifa foot.
- ¿Cuántos destinos? → 3, los más cercanos hacia el Este con ruta real.
- ¿Compatibilidad tests? → `transportSelector` opcional con fallback mock.
- ¿Modos sin rutas? → Se mantienen en `TransportMode` pero no se generan rutas (balloon/horse/camel/motorcycle).

**Número:** 013. **Slug:** consumo-rutas-reales-transport-selector.
