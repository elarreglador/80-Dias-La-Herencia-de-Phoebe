# SPEC 018 — Precios ferroviarios reales (billete, economía por país)

> **Estado:** Aprobado

> **Depende de:** SPEC 010 (rutas ferroviarias), SPEC 011 (visor rutas ferroviarias), SPEC 013 (TransportSelector, tarifas), SPEC 012 (BudgetService, GameSession, FoggLeg), SPEC 016 (ruta viva, CityCatalog)

> **Fecha:** 2026-10-27

> **Objetivo:** Sustituir el billete plano mock del tren (0.8 €/km) por el cálculo `precio base del km (por zona geográfica) × distancia de la ruta × multiplicador económico del país`, de modo que el billete mostrado sea el que se descuenta del presupuesto.

---

## 1. Por qué existe esta especificación

El billete del tren se calcula hoy como `distanceKm × 0.8` (`TariffTable.defaults[train].pricePerKm`, en `lib/services/transport_selector.dart`), un valor único y sin relación con el país ni con la vía. Eso hace que un tramo en los Alpes cueste lo mismo que uno en una llanura, y que un tren en Japón cueste lo mismo que uno en Bulgaria. Con SPEC 013 la ruta real ya aporta `distanceKm` y origen/destino; falta cerrar el precio para que refleje la realidad y alimente el presupuesto (SPEC 012) con un número defendible.

La dificultad del terreno no se modela como factor separado: si hay montañas, la vía da rodeos, `km_real` aumenta y el billete se encarece automáticamente de forma proporcional a los kilómetros extra recorridos.

---

## 2. Alcance

**En:**

- **Define precio base del km por zona geográfica — `lib/services/rail_pricing.dart` (nuevo) — `RailPricing.basePricePerKm(zone)`** — tabla aproximada en €/km por continente/zona equivalente, con fuente y año.
- **Define multiplicador económico por país — `RailPricing.countryMultiplier(tz)` — base España = 1.0** — tabla de multiplicadores relativos derivados del huso horario IANA.
- **Calcula el billete del tren en TransportSelector — `lib/services/transport_selector.dart` — `_buildOption`** — sustituye `tariff.pricePerKm` por la fórmula para `TransportMode.train`; barco y coche mantienen su tarifa mock.
- **Persiste el desglose en VehicleOption/FoggLeg — `destination_option.dart`, `fogg_leg.dart`** — campos opcionales `priceBreakdown` (base, economía); `price` total sigue siendo `int` €.
- **Almacena el multiplicador por país para uso futuro — `PriceBreakdown.countryMultiplier`** — el valor se persiste en `VehicleOption`/`FoggLeg` y queda disponible para futuras mecánicas; en esta spec no se consume más allá del precio.
- **Tests TDD — `test/services/rail_pricing_test.dart`, `transport_selector_test.dart`** — fórmula, zonas, multiplicadores, modos no-tren inalterados.

**Compartido:** `FoggCity` (origen/destino → zona/país vía huso IANA), `RouteEntry`, `RouteCatalog`, `TariffTable` (modos no-tren), `BudgetService`, `FoggLeg`, `VehicleOption`, `CityCatalog`. Sin dependencias nuevas.

**Fuera del alcance (para futuras especificaciones):**

- Barco y coche (futuras specs).
- Tarifas dinámicas por fecha/anticipación.
- Descuentos, tarjetas, pases.
- Conversión multi-moneda (todo en €).
- UI de desglose (solo datos).

---

## 3. Modelo de datos

### 3.1 Zona geográfica (`lib/services/rail_pricing.dart`)

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
```

### 3.2 Precio base por km (`RailPricing`)

```dart
class RailPricing {
  /// Precio base en €/km por zona (2ª clase intercity, tarifa publicada media).
  /// Fuentes: traintrackings.com (2025), T&E Ranking (2024), Pedestrian Observations (2024).
  static const basePricePerKm = <GeoZone, double>{
    GeoZone.europeDeveloped: 0.15,
    GeoZone.northAmerica: 0.16,
    GeoZone.asiaDeveloped: 0.18,   // Japón
    GeoZone.asiaDeveloping: 0.06,  // China, India, SE asiático
    GeoZone.oceania: 0.11,
    GeoZone.africa: 0.05,          // estimación
    GeoZone.southAmerica: 0.08,    // estimación
    GeoZone.middleEast: 0.07,      // estimación
  };

  /// Deriva la zona del huso IANA (prefijo de región + país).
  static GeoZone zoneForTimezone(String tz);

  /// Multiplicador económico relativo (base España = 1.0).
  /// Tabla semilla por país; si no hay entrada, devuelve 1.0.
  static double countryMultiplierForTimezone(String tz);

  /// Precio final por km para un tramo concreto.
  static double pricePerKm({
    required GeoZone zone,
    required double countryMultiplier,
  }) =>
      basePricePerKm[zone]! * countryMultiplier;
}
```

**Reglas de derivación (contrato):**

- `zoneForTimezone`: prefijo `Europe/` → `europeDeveloped`; `Africa/` → `africa`; `Australia/` y `Pacific/` → `oceania`; `Asia/` se subdivide en `asiaDeveloped` (Japón, Corea del Sur, Taiwán, Singapur) y `asiaDeveloping` (resto); `America/` se subdivide en `northAmerica` (EE.UU., Canadá) y `southAmerica` (resto); Oriente Medio (`Asia/` con países del Golfo/Levante) → `middleEast`.
- `countryMultiplierForTimezone`: tabla semilla keyed por el huso IANA exacto (o por país derivado), con España = 1.0. Fallback 1.0 si no hay entrada. La tabla completa se puebla en implementación para todos los países con ciudades en `locations.json`.

### 3.3 Desglose del precio (`lib/domain/models/price_breakdown.dart`)

```dart
class PriceBreakdown {
  const PriceBreakdown({
    required this.basePricePerKm,
    required this.zone,
    required this.countryMultiplier,
    required this.distanceKm,
  });

  final double basePricePerKm;
  final GeoZone zone;
  final double countryMultiplier;
  final double distanceKm;

  double get total => basePricePerKm * distanceKm * countryMultiplier;
}
```

### 3.4 Cambios en entidades existentes

- **`VehicleOption`** (`lib/domain/entities/destination_option.dart`): añade campo opcional `final PriceBreakdown? priceBreakdown;` (default `null`). Solo se rellena para `TransportMode.train`.
- **`FoggLeg`** (`lib/domain/entities/fogg_leg.dart`): añade campo opcional `final PriceBreakdown? priceBreakdown;` (default `null`).
- **`GameSession.startLeg`** (`lib/services/game_session.dart`): propaga `vehicle.priceBreakdown` a `FoggLeg.priceBreakdown`.

### 3.5 `TransportSelector` (`lib/services/transport_selector.dart`)

En `_buildOption`, para `TransportMode.train`:

```dart
final zone = RailPricing.zoneForTimezone(city.timezone); // destino (país de llegada)
final countryMult = RailPricing.countryMultiplierForTimezone(city.timezone);
final pricePerKm = RailPricing.pricePerKm(zone: zone, countryMultiplier: countryMult);
final price = (route.distanceKm * pricePerKm).round();
```

El `VehicleOption` se crea con `priceBreakdown: PriceBreakdown(basePricePerKm: RailPricing.basePricePerKm[zone]!, zone: zone, countryMultiplier: countryMult, distanceKm: route.distanceKm)`.

Barco y coche siguen usando `tariff.pricePerKm` y `priceBreakdown = null`.

---

## 4. Plan de implementación

1. Crear `lib/domain/models/price_breakdown.dart` con `PriceBreakdown`.
2. Crear `lib/services/rail_pricing.dart` con `GeoZone`, `zoneForTimezone`, `countryMultiplierForTimezone` y tabla `basePricePerKm` (seed).
3. Añadir `priceBreakdown` opcional a `VehicleOption` y `FoggLeg`.
4. Extender `TransportSelector` para calcular precio del tren con la fórmula; propagar `priceBreakdown`.
5. Propagar `priceBreakdown` en `GameSession.startLeg`.
6. Tests TDD: `rail_pricing_test.dart` (zonas, multiplicadores, fórmula) y actualizar `transport_selector_test.dart` (precio tren nuevo, modos no-tren inalterados, desglose).

---

## 5. Criterios de aceptación

- [ ] `RailPricing.pricePerKm(...)` devuelve `base × countryMultiplier`.
- [ ] `zoneForTimezone('Europe/Madrid')` = `europeDeveloped`; `zoneForTimezone('Asia/Tokyo')` = `asiaDeveloped`; `zoneForTimezone('America/Sao_Paulo')` = `southAmerica`.
- [ ] `countryMultiplierForTimezone('Europe/Madrid')` = 1.0.
- [ ] `TransportSelector` calcula el precio del tren con la fórmula y rellena `priceBreakdown`; barco y coche mantienen su precio anterior.
- [ ] `FoggLeg.priceBreakdown` se propaga desde `VehicleOption` en `GameSession.startLeg`.
- [ ] `PriceBreakdown.countryMultiplier` se persiste en `VehicleOption` y `FoggLeg` para uso futuro.
- [ ] `flutter analyze` sin errores nuevos; `flutter test` verde.
- [ ] Los tests existentes de `TransportSelector` que asumían 0.8 €/km se actualizan al nuevo cálculo.

---

## 6. Decisiones tomadas y descartadas

- **Sí:** solo trenes en esta spec; barco y coche mantienen tarifa mock. Justificación: acota el alcance y evita tocar otros modos sin datos.
- **Sí:** precio base por zona geográfica (continente o equivalente). Justificación: el usuario lo pidió y refleja coste de infraestructura.
- **Sí:** multiplicador económico por país con base España = 1.0. Justificación: coherencia con el proyecto (origen Madrid) y simplicidad relativa.
- **Sí:** la dificultad del terreno no se modela como factor separado. Justificación: si hay montañas, la vía da rodeos, `km_real` aumenta y el billete se encarece automáticamente de forma proporcional a los kilómetros extra recorridos.
- **Sí:** desglose opcional en entidades (`priceBreakdown` nullable). Justificación: trazabilidad sin romper tests ni constructores existentes.
- **Sí:** el multiplicador por país se persiste en `PriceBreakdown` aunque no se consuma más allá del precio. Justificación: se usará en mecánicas futuras; almacenarlo ahora evita recalcularlo.
- **Sí:** precio final sigue siendo `int` € (redondeo). Justificación: `BudgetService` y UI esperan `int`.
- **No:** tarifas dinámicas por fecha. Se pospone: requiere datos de anticipación no disponibles.
- **No:** conversión multi-moneda. Todo en €; los multiplicadores absorben diferencias de nivel económico.
- **No:** UI de desglose. Solo datos; la UI se abordará en otra spec.

---

## 7. Riesgos identificados

| Riesgo | Mitigación |
|---|---|
| Datos de precio base aproximados y estáticos | Tabla con fuente y año; actualización manual documentada. |
| Zona geográfica mal clasificada por huso | Tests de `zoneForTimezone` para casos límite; overrides explícitos. |
| Solapamiento entre precio base (zona) y multiplicador (país) | Documentar que el base refleja infraestructura y el multiplicador el nivel económico. |
| Tests existentes asumen 0.8 €/km | Actualizar `transport_selector_test.dart` al nuevo cálculo. |
| Huso IANA sin país claro (zonas genéricas) | Fallback `countryMultiplier = 1.0` y zona por prefijo de región. |

---

## 8. Lo que **no** está en esta especificación

- Barco y coche (futuras specs).
- Tarifas dinámicas por fecha/anticipación.
- Descuentos, tarjetas, pases.
- Conversión multi-moneda.
- UI de desglose.

---

## 9. Referencias

- `lib/services/transport_selector.dart` — tarifa mock actual (`0.8 €/km`).
- `lib/domain/entities/destination_option.dart`, `lib/domain/entities/fogg_leg.dart` — entidades con `price`.
- `lib/services/budget_service.dart` — consumo del precio.
- `lib/services/game_session.dart` — `startLeg`.
- `assets/data/rail_routes.json` — rutas ferroviarias reales (distanceKm, husos).
- `assets/data/locations.json` — ciudades con huso IANA.
- traintrackings.com (2025), T&E European Ranking of Rail Operators (2024), Pedestrian Observations (2024) — fuentes de precio base.