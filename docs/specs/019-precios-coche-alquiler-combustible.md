# SPEC 019 — Precios de coche reales (alquiler + combustible)

> **Estado:** Implementado

> **Depende de:** SPEC 018 (precios ferroviarios, origen de `GeoZone`), SPEC 013 (TransportSelector, tarifas), SPEC 012 (BudgetService, GameSession, FoggLeg), SPEC 006 (rutas por carretera), SPEC 016 (ruta viva, CityCatalog)

> **Fecha:** 2026-10-27

> **Objetivo:** Sustituir el coste plano del coche (0.6 €/km, `TariffTable.defaults[car].pricePerKm`) por el cálculo `alquiler (€ fijo por tramo) + combustible (€/km × distancia)`, ambos escalados por zona geográfica y multiplicador económico del país de llegada, de modo que el precio mostrado sea el que se descuenta del presupuesto. De paso, extraer los factores geográficos comunes (`GeoZone`, zona y multiplicador por huso IANA) de `RailPricing` a un nuevo `GeoPricing`, porque pasarán a consumirlos tren y coche (y más adelante el barco).

---

## 1. Por qué existe esta especificación

El coche se cobra hoy como `distanceKm × 0.6` (`TariffTable.defaults[car].pricePerKm`, en `lib/services/transport_selector.dart`), un valor único que no distingue entre repostar en Suiza o en Chad, ni refleja el alquiler del vehículo. Con la SPEC 013 la ruta real (`car_routes.json`) ya aporta `distanceKm` y origen/destino, y con la SPEC 018 existe el patrón de precios por zona + multiplicador económico. Esta spec aplica el mismo patrón al coche con su propia fórmula de dos componentes: **alquiler** (coste fijo de disponibilidad del vehículo) y **combustible** (coste variable proporcional a los km).

La SPEC 018 dejó `GeoZone`, `zoneForTimezone` y `countryMultiplierForTimezone` dentro de `RailPricing`. Con un segundo consumidor (coche) ese nombre deja de ser honesto: `RailPricing` no debe calcular costes de coche. Esta spec extrae esos factores a `GeoPricing` antes de que exista un tercero (barco).

La dificultad del terreno no se modela como factor separado: si hay montañas, la carretera da rodeos, `km_real` aumenta y el coste se encarece automáticamente de forma proporcional a los kilómetros extra recorridos.

---

## 2. Alcance

**En:**

- **Extrae los factores geográficos comunes — `lib/services/geo_pricing.dart` (nuevo) — `GeoPricing`** — mueve desde `rail_pricing.dart` el enum `GeoZone`, `zoneForTimezone(tz)`, `countryMultiplierForTimezone(tz)` y sus tablas semilla (conjuntos de prefijos y multiplicadores por huso IANA). Comportamiento idéntico al actual; solo cambia el propietario del código.
- **Deja `RailPricing` solo con precios de tren — `lib/services/rail_pricing.dart`** — conserva `basePricePerKm` y `pricePerKm(zone, countryMultiplier)`; importa `geo_pricing.dart`. Sin `GeoZone` ni tablas de país propias.
- **Define precio base de combustible por zona — `lib/services/car_pricing.dart` (nuevo) — `CarPricing.fuelBasePricePerKm`** — tabla en €/km por `GeoZone` (consumo medio × precio del carburante), con fuente y año.
- **Define precio base de alquiler por zona — `CarPricing.rentalBasePrice`** — tabla en € por tramo (fijo, sin escalar con la duración) por `GeoZone`, con fuente y año.
- **Refactoriza `PriceBreakdown` a jerarquía — `lib/domain/models/price_breakdown.dart`** — `PriceBreakdown` pasa a clase base abstracta (`zone`, `countryMultiplier`, `distanceKm`, `total` abstracto) con dos implementaciones concretas: `RailPriceBreakdown` (comportamiento idéntico al actual) y `CarPriceBreakdown` (alquiler + combustible). Preparado para una futura `ShipPriceBreakdown`.
- **Calcula el precio del coche en TransportSelector — `lib/services/transport_selector.dart` — `_buildOption`** — rama `TransportMode.car` con la fórmula usando `GeoPricing` + `CarPricing`; barco sigue con la tarifa mock y `priceBreakdown = null`.
- **Tests TDD — `geo_pricing_test.dart` (nuevo), `car_pricing_test.dart` (nuevo), `rail_pricing_test.dart`, `transport_selector_test.dart`, `game_session_test.dart`** — extracción sin cambio de comportamiento, fórmula del coche, jerarquía del desglose, barco inalterado.
- **Actualiza referencias de la SPEC 018** — `docs/specs/018-precios-ferroviarios-reales.md` recibe una nota que apunta a esta spec para el movimiento de API (ver §10).

**Compartido:** `GeoPricing`/`GeoZone`, `RailPricing` (solo precios de tren), `RouteEntry`, `RouteCatalog`, `TariffTable` (velocidad/sleeper y tarifa del barco), `BudgetService`, `FoggLeg`, `VehicleOption`, `GameSession`, `CityCatalog`. Sin dependencias nuevas.

**Fuera del alcance (para futuras especificaciones):**

- Barco (spec propia: su fórmula de billete).
- Alquiler escalado por días de uso (decisión explícita de mantenerlo fijo; ver §6).
- Tarifas dinámicas por fecha/anticipación, tipo de vehículo, seguros.
- Conversión multi-moneda (todo en €).
- UI de desglose (solo datos).

---

## 3. Modelo de datos

### 3.1 Zona geográfica y multiplicador — `lib/services/geo_pricing.dart` (nuevo)

Se mueve intacto el contenido de la SPEC 018 (`rail_pricing.dart`) a un servicio con nombre honesto para todos los modos:

```dart
enum GeoZone {
  europeDeveloped,
  northAmerica,
  asiaDeveloped,
  asiaDeveloping,
  oceania,
  africa,
  southAmerica,
  middleEast,
}

/// Factores geográficos comunes de precio: zona por huso IANA y
/// multiplicador económico del país (base España = 1.0).
/// Compartido por tren, coche (SPEC 019) y, en el futuro, barco.
class GeoPricing {
  const GeoPricing._();

  /// Deriva la zona del huso IANA (prefijo de región + país).
  static GeoZone zoneForTimezone(String tz); // cuerpo actual de RailPricing.zoneForTimezone

  /// Multiplicador económico relativo (base España = 1.0).
  /// Fallback 1.0 si el huso no está en la tabla.
  static double countryMultiplierForTimezone(String tz); // ídem
}
```

- **Contrato sin cambios:** mismas reglas de derivación por prefijo (`Europe/`, `Africa/`, `America/` subdividido, `Asia/` con Oriente Medio y Asia desarrollada, `Atlantic/`, fallback `europeDeveloped` para husos genéricos) y misma tabla semilla de multiplicadores por huso IANA exacto, con España = 1.0.
- El país considerado es el de **llegada** (destino), igual que en la SPEC 018.
- `rail_pricing.dart` importa `geo_pricing.dart` y reexporta nada: los consumidores actualizan su import (lista en §4).

### 3.2 Precios base del coche (`lib/services/car_pricing.dart`)

```dart
import 'geo_pricing.dart';

class CarPricing {
  const CarPricing._();

  /// Combustible en €/km por zona.
  /// Cálculo: consumo medio 7,5 L/100 km × precio medio del carburante por zona.
  /// Fuentes: Global Petrol Prices (2025), IEA (2025).
  static const fuelBasePricePerKm = <GeoZone, double>{
    GeoZone.europeDeveloped: 0.12,
    GeoZone.northAmerica: 0.06,
    GeoZone.asiaDeveloped: 0.10,   // Japón
    GeoZone.asiaDeveloping: 0.07,
    GeoZone.oceania: 0.09,
    GeoZone.africa: 0.08,
    GeoZone.southAmerica: 0.08,
    GeoZone.middleEast: 0.05,
  };

  /// Alquiler del coche en € por tramo (tarifa de un día de turismo económico,
  /// fija: NO escala con la duración del trayecto).
  /// Fuente: estimación sobre tarifas públicas de alquiler (2025).
  static const rentalBasePrice = <GeoZone, double>{
    GeoZone.europeDeveloped: 50,
    GeoZone.northAmerica: 45,
    GeoZone.asiaDeveloped: 55,
    GeoZone.asiaDeveloping: 25,
    GeoZone.oceania: 45,
    GeoZone.africa: 40,
    GeoZone.southAmerica: 35,
    GeoZone.middleEast: 30,
  };
}
```

**Fórmula (contrato):**

- `combustible = fuelBasePricePerKm[zone] × countryMultiplier × distanceKm`
- `alquiler = rentalBasePrice[zone] × countryMultiplier` (independiente de `distanceKm`)
- `total = alquiler + combustible`

`CarPricing` **no** define zonas ni tablas de país: importa `GeoZone` de `geo_pricing.dart` y consume el multiplicador desde `GeoPricing` en `TransportSelector`.

### 3.3 Desglose del precio — jerarquía (`lib/domain/models/price_breakdown.dart`)

```dart
import '../../services/geo_pricing.dart';

abstract class PriceBreakdown {
  const PriceBreakdown({
    required this.zone,
    required this.countryMultiplier,
    required this.distanceKm,
  });

  final GeoZone zone;
  final double countryMultiplier;
  final double distanceKm;

  double get total;
}

class RailPriceBreakdown extends PriceBreakdown {
  const RailPriceBreakdown({
    required this.basePricePerKm,
    required super.zone,
    required super.countryMultiplier,
    required super.distanceKm,
  });

  final double basePricePerKm;

  @override
  double get total => basePricePerKm * distanceKm * countryMultiplier;
}

class CarPriceBreakdown extends PriceBreakdown {
  const CarPriceBreakdown({
    required this.fuelBasePricePerKm,
    required this.rentalBasePrice,
    required super.zone,
    required super.countryMultiplier,
    required super.distanceKm,
  });

  /// €/km de combustible de la zona (sin multiplicador).
  final double fuelBasePricePerKm;

  /// € fijos de alquiler de la zona (sin multiplicador).
  final double rentalBasePrice;

  double get fuel => fuelBasePricePerKm * countryMultiplier * distanceKm;
  double get rental => rentalBasePrice * countryMultiplier;

  @override
  double get total => rental + fuel;
}
```

**Notas:**

- `RailPriceBreakdown` es el `PriceBreakdown` actual renombrado; su `total` y campos no cambian, solo se añade `abstract` a la base. Los tests de la SPEC 018 siguen verdes salvo el tipo del constructor.
- `zone`, `countryMultiplier` y `distanceKm` viven en la base porque los tres modos (tren, coche y el futuro barco) los comparten; solo los componentes de precio van en las subclases.
- La base importa `geo_pricing.dart` (para `GeoZone`), no `rail_pricing.dart` ni `car_pricing.dart`: los campos de precio son `double` puros.

### 3.4 Cambios en entidades existentes

- **`VehicleOption`** (`lib/domain/entities/destination_option.dart`): el tipo de `priceBreakdown` sigue siendo `PriceBreakdown?` (ahora abstracto). **Sin cambios de firma.**
- **`FoggLeg`** (`lib/domain/entities/fogg_leg.dart`): ídem, `PriceBreakdown?`.
- **`GameSession.startLeg`** (`lib/services/game_session.dart`): sin cambios; ya propaga `vehicle.priceBreakdown`.
- **`TariffTable.defaults[car].pricePerKm` (0.6)**: queda **sin uso para el precio** (igual que el 0.8 del tren tras la SPEC 018). La entrada se conserva porque `speedKmh` y `sleeper` sí se consumen.

### 3.5 `TransportSelector` (`lib/services/transport_selector.dart`)

Imports nuevos: `geo_pricing.dart` y `car_pricing.dart` (además de `rail_pricing.dart`, que ya estaba). En `_buildOption`, el cálculo pasa a ser:

```dart
PriceBreakdown? priceBreakdown;
if (mode == TransportMode.train) {
  final zone = GeoPricing.zoneForTimezone(city.timezone);
  final countryMult = GeoPricing.countryMultiplierForTimezone(city.timezone);
  priceBreakdown = RailPriceBreakdown(
    basePricePerKm: RailPricing.basePricePerKm[zone]!,
    zone: zone,
    countryMultiplier: countryMult,
    distanceKm: route.distanceKm,
  );
} else if (mode == TransportMode.car) {
  final zone = GeoPricing.zoneForTimezone(city.timezone);
  final countryMult = GeoPricing.countryMultiplierForTimezone(city.timezone);
  priceBreakdown = CarPriceBreakdown(
    fuelBasePricePerKm: CarPricing.fuelBasePricePerKm[zone]!,
    rentalBasePrice: CarPricing.rentalBasePrice[zone]!,
    zone: zone,
    countryMultiplier: countryMult,
    distanceKm: route.distanceKm,
  );
}
final price = priceBreakdown != null
    ? priceBreakdown.total.round()
    : (route.distanceKm * tariff.pricePerKm).round(); // solo barco
```

- Tren y coche fijan `price` desde `total.round()` (misma fórmula que antes para el tren: `distanceKm × base × mult`).
- Barco: `priceBreakdown = null` y tarifa mock intacta.

---

## 4. Plan de implementación

1. Crear `lib/services/geo_pricing.dart` moviendo `GeoZone`, `zoneForTimezone`, `countryMultiplierForTimezone` y sus tablas desde `rail_pricing.dart` (cuerpos sin cambios).
2. Reducir `lib/services/rail_pricing.dart` a `basePricePerKm` + `pricePerKm`, importando `geo_pricing.dart`.
3. Actualizar imports y llamadas: `price_breakdown.dart` (`GeoZone` vía `geo_pricing.dart`), `transport_selector.dart` (`GeoPricing.*` + `CarPricing`).
4. Crear `test/services/geo_pricing_test.dart` moviendo los grupos `zoneForTimezone` y `countryMultiplierForTimezone` desde `rail_pricing_test.dart`; este último queda solo con la fórmula y cobertura de `basePricePerKm`.
5. Actualizar imports en `transport_selector_test.dart` y `game_session_test.dart` (`GeoPricing`/`GeoZone` desde `geo_pricing.dart`).
6. Refactorizar `lib/domain/models/price_breakdown.dart`: base abstracta + `RailPriceBreakdown` + `CarPriceBreakdown`.
7. Crear `lib/services/car_pricing.dart` con `fuelBasePricePerKm` y `rentalBasePrice` (fuentes y año en el docstring).
8. Añadir la rama `TransportMode.car` en `TransportSelector._buildOption` y unificar `price` vía `total.round()`.
9. Actualizar `test/services/game_session_test.dart` (`PriceBreakdown(...)` → `RailPriceBreakdown(...)`).
10. Crear `test/services/car_pricing_test.dart`: fórmula (combustible, alquiler, total), zona/multiplicador desde `GeoPricing`, alquiler independiente de la distancia, fallback `countryMultiplier = 1.0`.
11. Actualizar `test/services/transport_selector_test.dart`: cast a `RailPriceBreakdown` donde se lee `basePricePerKm`; el test «barco y coche mantienen la tarifa mock» pasa a solo barco; nuevo test «el coche usa alquiler + combustible y rellena priceBreakdown».
12. Añadir la nota en `docs/specs/018-precios-ferroviarios-reales.md` (§10).
13. Grep de referencias residuales (`RailPricing.zoneForTimezone`, `RailPricing.countryMultiplierForTimezone`, `import ... rail_pricing` donde solo se usaba `GeoZone`) y verificar que `rail_pricing.dart` ya no declara `GeoZone`.
14. `flutter analyze` y `flutter test`.

---

## 5. Criterios de aceptación

- [x] `CarPriceBreakdown.total = rental + fuel`, con `fuel = fuelBasePricePerKm × countryMultiplier × distanceKm` y `rental = rentalBasePrice × countryMultiplier`.
- [x] `GeoPricing.zoneForTimezone('Europe/Madrid')` = `europeDeveloped` y `GeoPricing.countryMultiplierForTimezone('Europe/Madrid')` = 1.0 (mismo comportamiento que antes del movimiento).
- [x] `rail_pricing.dart` ya no declara `GeoZone`, `zoneForTimezone` ni `countryMultiplierForTimezone`.
- [x] Ningún fichero de coche (`car_pricing.dart`, ni la rama de coche del selector) importa `RailPricing`.
- [x] `TransportSelector` calcula el precio del coche con la fórmula y rellena `CarPriceBreakdown`; el `price` coincide con `total.round()`.
- [x] El alquiler es fijo: para la misma zona y país, dos rutas de distinta distancia pagan el mismo componente de alquiler.
- [x] El precio del tren no cambia (mismo `total` que antes del refactor); el barco mantiene tarifa mock y `priceBreakdown = null`.
- [x] `PriceBreakdown` es abstracto; `RailPriceBreakdown` reproduce el comportamiento del `PriceBreakdown` actual.
- [x] `FoggLeg.priceBreakdown` se propaga desde `VehicleOption` en `GameSession.startLeg` también para coche.
- [x] La SPEC 018 contiene la nota de referencia a esta spec.
- [x] `flutter analyze` sin errores nuevos; `flutter test` verde.

---

## 6. Decisiones tomadas y descartadas

- **Sí:** extraer `GeoZone`/zona/multiplicador a `GeoPricing` **ahora** (no posponerlo a la spec del barco). Justificación: `RailPricing` calculando precios de coche sería un engaño nominal; el coste es bajo (los cuerpos no cambian, solo el propietario) y los tests ya cubren el comportamiento. La regla de tres se anticipa por claridad, no por necesidad.
- **Sí:** nombre `GeoPricing` — «factores geográficos de precio». Descartados `PricingZone` (no dice que sea precio), `WorldPricing` (demasiado amplio) y mantenerlo en `RailPricing` (ver arriba).
- **Sí:** alquiler de precio **fijo por tramo**, sin escalar con la duración de uso del vehículo. Decisión del Señor (2026-10-27): mantiene la fórmula pedida `alquiler = base × zona × país` y evita modelar días.
- **Sí:** reutilizar `GeoZone`, `zoneForTimezone` y `countryMultiplierForTimezone` de la SPEC 018 (movidos, no duplicados). Justificación: DRY; el multiplicador ya refleja el nivel económico del país y su tabla ya está poblada y testada.
- **Sí:** cifras base propias para coche (combustible y alquiler), con fuentes y año distintas a las del tren.
- **Sí:** la dificultad del terreno no se modela como factor separado. Justificación: si hay montañas, la carretera da rodeos, `km_real` aumenta y los componentes variables se encarecen proporcionalmente a los km extra.
- **Sí:** `PriceBreakdown` pasa a base abstracta con `RailPriceBreakdown`/`CarPriceBreakdown`. Justificación: los componentes de precio difieren por modo, pero zona/multiplicador/distancia son comunes; la base abierta admite `ShipPriceBreakdown` en la spec del barco sin tocar entidades. Alternativa descartada: campos nullable extra en una sola clase (acopla modos y deja campos sin sentido en cada modo).
- **Sí:** zona y país del **destino** (llegada). Justificación: coherencia con la SPEC 018.
- **Sí:** el precio final sigue siendo `int` € (redondeo una sola vez sobre `total`). Justificación: `BudgetService` y UI esperan `int`.
- **Sí:** nota en la SPEC 018 que referencia esta spec. Justificación: la 018 sigue siendo la fuente de las reglas de derivación, pero su API cambió de propietario; la nota evita que alguien busque el código donde la 018 dice que está.
- **No:** alquiler por días. Decisión explícita del Señor; si más adelante se quiere, cambia solo `CarPriceBreakdown.rental`.
- **No:** tarifas dinámicas, tipo de vehículo, seguros, multi-moneda, UI de desglose.

---

## 7. Riesgos identificados

| Riesgo | Mitigación |
|---|---|
| Datos de precio base aproximados y estáticos | Tablas con fuente y año; actualización manual documentada. |
| El alquiler fijo ignora tramos largos («regala» días de coche) | Decisión documentada en §6; revisable en futura spec. |
| Mover la API de la SPEC 018 rompe sus tests y referencias | Los cuerpos no cambian; `geo_pricing_test.dart` hereda sus tests; grep de residuos (§4.13); nota en la 018. |
| Solapamiento entre precio base (zona) y multiplicador (país) | Documentar que el base refleja coste de carburante/tarifa de la zona y el multiplicador el nivel económico. |
| El refactor de `PriceBreakdown` rompe constructores y lecturas de campos | `RailPriceBreakdown` mantiene campos y `total` idénticos; actualizar `game_session_test` y el cast de `basePricePerKm` en `transport_selector_test`. |
| Precio de coche sospechosamente parecido al de tren en algunos tramos | Cifras base revisables; los tests verifican la fórmula, no la paridad entre modos. |
| Huso IANA sin país claro | Fallback `countryMultiplier = 1.0` y zona por prefijo de región (mismo comportamiento que SPEC 018). |

---

## 8. Lo que **no** está en esta especificación

- Barco (spec propia).
- Alquiler escalado por días de uso.
- Tarifas dinámicas por fecha/anticipación, tipo de vehículo, seguros.
- Conversión multi-moneda.
- UI de desglose.

---

## 9. Referencias

- `lib/services/transport_selector.dart` — tarifa mock actual del coche (`0.6 €/km`).
- `lib/services/rail_pricing.dart` — `basePricePerKm`, `pricePerKm` (SPEC 018; `GeoZone` se mueve a `geo_pricing.dart` en esta spec).
- `lib/services/geo_pricing.dart` — nuevo hogar de `GeoZone`, `zoneForTimezone`, `countryMultiplierForTimezone`.
- `lib/domain/models/price_breakdown.dart` — desglose actual del tren.
- `lib/domain/entities/destination_option.dart`, `lib/domain/entities/fogg_leg.dart` — entidades con `priceBreakdown`.
- `lib/services/budget_service.dart` — consumo del precio.
- `lib/services/game_session.dart` — `startLeg`.
- `assets/data/car_routes.json` — rutas por carretera reales (`distanceKm`, `durationHours`, husos).
- `assets/data/locations.json` — ciudades con huso IANA.
- Global Petrol Prices (2025), IEA (2025) — precio medio del carburante por zona; tarifas públicas de alquiler de turismo económico (2025) — alquiler.

---

## 10. Nota para la SPEC 018

En `docs/specs/018-precios-ferroviarios-reales.md` se añade una nota en la cabecera indicando que `GeoZone`, `zoneForTimezone` y `countryMultiplierForTimezone` pasan de `RailPricing` (`rail_pricing.dart`) a `GeoPricing` (`geo_pricing.dart`) con esta SPEC 019, sin cambio de comportamiento. La 018 sigue siendo la fuente de las reglas de derivación por huso.
