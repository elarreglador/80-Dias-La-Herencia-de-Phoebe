# SPEC 023 — Descanso por agotamiento en ruta (carretera)

> **Estado:** Implementado

> **Depende de:** SPEC 012 (GameSession, Fatigue, GameLoop), SPEC 016 (Ruta viva, FoggLeg, foggPositionProvider), SPEC 019 (precios, GeoPricing), SPEC 022 (descanso en hotel, tasas de cansancio, HotelPricing)

> **Fecha:** 2026-10-30

> **Objetivo:** Cuando Phoebe viaja en coche y su cansancio se agota, el tramo se interrumpe en el punto actual: aleatoriamente encuentra hotel/hostel de carretera o duerme en el coche (área de servicio o gasolinera). El descanso recupera cansancio (hotel/hostel al ritmo del hotel en ciudad, coche a un ritmo inferior), se muestra en la misma ventana de viaje, Phoebe puede despertarse antes con un botón y, si se recupera por completo, continúa sola.

---

## 1. Por qué existe esta especificación

Hoy el viaje en coche drena cansancio (8%/h) y, al llegar a 0, solo se bloquea el *inicio* de nuevos tramos sin sleeper (`SleepRequiredException` en `startLeg`). Pero si Phoebe se agota **a mitad de un tramo en coche**, no hay mecanismo para parar: el tramo sigue su curso y el marcador llega al destino con 0% de energía. Tampoco existe un descanso «en carretera» con tipos aleatorios, ni la posibilidad de reanudar antes de recuperarse por completo.

Esta spec introduce la **parada por agotamiento en ruta** para el modo coche, reutilizando las tasas y el patrón de precios de la SPEC 022 y extendiendo `FoggLeg` con un estado de descanso transitorio.

---

## 2. Alcance

**En:**

- **Detección de agotamiento en tramo en coche — `GameSession.tick()`** — cuando la fatiga llega a 0 durante un `FoggTraveling` con `transport == TransportMode.car`, se inicia un descanso en ruta.
- **Tipo aleatorio de descanso — nuevo `RoadRestType` (`lib/domain/models/road_rest_type.dart`)** — hotel 20%, hostel 30%, área de servicio 15%, gasolinera 35%.
- **Pausa del tramo — `FoggLeg` gana `restType`, `restStartedAtUtc`, `restProgress`** — la llegada se retrasa por la duración del descanso; el marcador se congela en el punto de parada.
- **Recuperación por tipo — `Fatigue` gana `carRestRecoverRate = 6.0%/h`** — hotel/hostel recuperan 12.5%/h; área de servicio y gasolinera recuperan 6.0%/h.
- **Precio — `HotelPricing` gana `hostelPriceFor` (0.7 del hotel)** — hotel y hostel descuentan el importe (hostel = 70% del hotel); área de servicio y gasolinera son gratuitos. Si no se puede pagar, se degrada a área de servicio.
- **Reanudación — `GameSession.wakeUpOnRoute()` + auto-continuación al 100%** — botón «Despertar y continuar» disponible siempre; si la fatiga llega a 100%, Phoebe continúa sola.
- **UI — `_TravelingView` (`lib/presentation/pages/fogg_status_page.dart`)** — muestra el descanso en la misma ventana de viaje: tipo, icono, barra de cansancio, botón de despertar.
- **Posición congelada — `foggPositionProvider`** — mientras descansa, devuelve el punto `restProgress` sobre la geometría.
- **GameNotifier — método `wakeUpOnRoute()`**.

**Compartido:** `FoggLeg`, `Fatigue`, `GameSession`, `GameNotifier`, `HotelPricing`, `GeoPricing`, `TransportMode`, `FoggStatus`.

**Fuera del alcance (para futuras especificaciones):**

- Descanso por agotamiento en modos no-coche (tren, barco, mocks).
- Persistencia del descanso.
- Eventos de diario / StoryGenerator.
- Animaciones de la parada.

---

## 3. Modelo y diseño

### 3.1 `RoadRestType` (nuevo, `lib/domain/models/road_rest_type.dart`)

```dart
enum RoadRestType {
  hotel,
  hostel,
  serviceArea,
  gasStation;

  String get label => switch (this) {
        RoadRestType.hotel => 'Hotel de carretera',
        RoadRestType.hostel => 'Hostel de carretera',
        RoadRestType.serviceArea => 'Área de servicio',
        RoadRestType.gasStation => 'Gasolinera',
      };

  /// Tasa de recuperación (puntos/hora) durante el descanso.
  double get recoveryRate => switch (this) {
        RoadRestType.hotel => Fatigue.hotelRecoverRate,   // 12.5
        RoadRestType.hostel => Fatigue.hotelRecoverRate,  // 12.5
        RoadRestType.serviceArea => Fatigue.carRestRecoverRate, // 6.0
        RoadRestType.gasStation => Fatigue.carRestRecoverRate,  // 6.0
      };

  /// Solo hotel y hostel tienen coste.
  bool get isPaid => this == RoadRestType.hotel || this == RoadRestType.hostel;

  /// Elección aleatoria con los pesos acordados.
  static RoadRestType roll({Random? random}) {
    final r = (random ?? Random()).nextInt(100);
    if (r < 20) return RoadRestType.hotel;        // 20%
    if (r < 50) return RoadRestType.hostel;       // 30%
    if (r < 65) return RoadRestType.serviceArea;  // 15%
    return RoadRestType.gasStation;                // 35%
  }
}
```

### 3.2 Tasas de fatiga (`lib/domain/models/fatigue.dart`)

Se añade una constante:

```dart
/// Recuperación (puntos/hora) durmiendo en el coche (área de servicio / gasolinera).
static const double carRestRecoverRate = 6.0;
```

Las existentes no cambian.

### 3.3 `FoggLeg` (`lib/domain/entities/fogg_leg.dart`)

Campos opcionales nuevos (por defecto `null`):

```dart
final RoadRestType? restType;          // null = viajando normalmente
final DateTime? restStartedAtUtc;       // inicio del descanso
final double? restProgress;            // progreso congelado 0..1
```

El constructor `const` actual sigue siendo válido. `progressAt` y `remainingAt` no cambian; la UI y el provider usan `restProgress` cuando `restType != null`.

### 3.4 Precio del hostel (`lib/services/hotel_pricing.dart`)

```dart
/// Importe del hostel: 70% del hotel de la misma zona/país.
static int hostelPriceFor(GeoZone zone, {required double countryMultiplier}) {
  return (priceFor(zone, countryMultiplier: countryMultiplier) * 0.7).round();
}
```

### 3.5 `GameSession` (`lib/services/game_session.dart`)

**Getters nuevos:**

```dart
int get hostelPrice { /* igual que hotelPrice pero con HotelPricing.hostelPriceFor */ }
```

**Método nuevo:**

```dart
void wakeUpOnRoute() {
  final traveling = _status;
  if (traveling is! FoggTraveling) return;
  final leg = traveling.leg;
  if (leg.restType == null) return;
  _resumeFromRest(leg, timeEngine.now());
  _status = FoggTraveling(leg: _currentLeg!, fatigue: _fatigue);
  _emit();
}
```

**Lógica en `tick()` — rama `FoggTraveling`:**

1. Si `leg.restType != null` (descansando):
   - Calcular `elapsedHours` desde `_lastTickTime` (o desde `restStartedAtUtc` si es la primera vez).
   - `_fatigue = _fatigue.recover(elapsedHours * leg.restType!.recoveryRate)`.
   - Si `_fatigue.value >= 100.0`: reanudar (`_resumeFromRest`) y emitir `FoggTraveling` normal.
   - Si no: emitir `FoggTraveling` con el mismo `leg` y la nueva fatiga.
   - `_lastTickTime = now`.
   - `return`.

2. Si `now.isBefore(leg.arrivalUtc)` (viajando normal):
   - `newFatigue = _advanceFatigue(elapsedHours, leg)`.
   - Si `newFatigue.mustSleep && leg.transport == TransportMode.car`:
     - `_fatigue = const Fatigue(value: 0.0)`.
     - Elegir `type = RoadRestType.roll()`.
     - Si `type.isPaid`: calcular precio (hotel/hostel). Si `!budget.canAfford(price)`, degradar `type = RoadRestType.serviceArea`; si no, `budget.spend(price, ...)`.
     - `progress = leg.progressAt(now).clamp(0.0, 1.0)`.
     - Construir `restLeg` con `restType`, `restStartedAtUtc: now`, `restProgress: progress`.
     - `_currentLeg = restLeg`; `_lastTickTime = now`.
     - Emitir `FoggTraveling(leg: restLeg, fatigue: _fatigue)`.
     - `return`.
   - Si no: `_fatigue = newFatigue`; emitir; `return`.

3. Si ya llegó (`!now.isBefore(arrivalUtc)`): rama de llegada actual (sin cambios).

**Método privado `_resumeFromRest(FoggLeg leg, DateTime now)`:**

```dart
final restDuration = now.difference(leg.restStartedAtUtc!);
final newLeg = FoggLeg(
  from: leg.from, to: leg.to, transport: leg.transport,
  departureUtc: leg.departureUtc.add(restDuration),
  arrivalUtc: leg.arrivalUtc.add(restDuration),
  price: leg.price, sleeper: leg.sleeper, path: leg.path,
  priceBreakdown: leg.priceBreakdown,
  // restType, restStartedAtUtc, restProgress = null
);
_currentLeg = newLeg;
_legStartFatigue = _fatigue.value;
_lastTickTime = now;
```

### 3.6 `GameNotifier` (`lib/presentation/providers/game_notifier.dart`)

```dart
void wakeUpOnRoute() {
  _session.wakeUpOnRoute();
  state = _session.status;
}
```

### 3.7 `foggPositionProvider` (`lib/presentation/providers/fogg_position_provider.dart`)

```dart
FoggTraveling(leg: final leg) => (leg.restType != null && leg.restProgress != null)
    ? (leg.path?.positionAt(leg.restProgress!) ?? LatLng(leg.from.lat, leg.from.lng))
    : (leg.path?.positionAt(leg.progressAt(now)) ?? LatLng(leg.from.lat, leg.from.lng)),
```

### 3.8 UI — `_TravelingView` (`lib/presentation/pages/fogg_status_page.dart`)

Si `leg.restType != null`, renderizar variante de descanso:

- Cabecera: «Phoebe está descansando».
- Subtítulo: `${leg.restType!.label} · ${leg.from.name} → ${leg.to.name}`.
- Icono grande según tipo (hotel `Icons.hotel`, hostel `Icons.bed`, área de servicio `Icons.local_parking`, gasolinera `Icons.local_gas_station`).
- Barra de cansancio (valor actual) con color por umbral (SPEC 021).
- Texto: «Se despertará sola al recuperarse» (cuando no está al 100%).
- Botón elevado: «Despertar y continuar» → `ref.read(gameNotifierProvider.notifier).wakeUpOnRoute()`.
- La barra de progreso de la ruta se congela en `leg.restProgress`.

Si `leg.restType == null`, renderizar la UI actual de viaje sin cambios.

---

## 4. Plan de implementación

1. Crear `lib/domain/models/road_rest_type.dart` con el enum y `roll()`.
2. Añadir `carRestRecoverRate = 6.0` a `Fatigue`.
3. Añadir `hostelPriceFor` a `HotelPricing`.
4. Añadir campos `restType`, `restStartedAtUtc`, `restProgress` a `FoggLeg`.
5. Actualizar `GameSession`: getter `hostelPrice`, método `wakeUpOnRoute`, lógica de descanso en `tick()`, `_resumeFromRest`.
6. Añadir `wakeUpOnRoute()` a `GameNotifier`.
7. Actualizar `foggPositionProvider` para posición congelada.
8. Actualizar `_TravelingView` para la variante de descanso.
9. Actualizar tests existentes afectados (fatiga en viaje, posición) y añadir tests nuevos.
10. `flutter analyze` y `flutter test`.

---

## 5. Criterios de aceptación

- [ ] Cuando Phoebe viaja en coche y la fatiga llega a 0, el tramo se interrumpe y se inicia un descanso en ruta.
- [ ] El tipo se elige con probabilidades 20/30/15/35 (hotel/hostel/área de servicio/gasolinera).
- [ ] Hotel y hostel recuperan 12.5%/h; área de servicio y gasolinera recuperan 6.0%/h.
- [ ] Hotel y hostel descuentan su importe (hostel = 70% del hotel); área de servicio y gasolinera son gratuitos.
- [ ] Si no se puede pagar hotel/hostel, se degrada a área de servicio.
- [ ] El marcador se congela en el punto de parada durante el descanso.
- [ ] La llegada se retrasa por la duración del descanso.
- [ ] El botón «Despertar y continuar» reanuda la ruta aunque la fatiga no esté al 100%.
- [ ] Al llegar la fatiga al 100%, Phoebe continúa sola.
- [ ] El descanso puede repetirse varias veces en el mismo tramo.
- [ ] Todo se muestra en la misma ventana de viaje (`_TravelingView`).
- [ ] `flutter analyze` sin errores nuevos y `flutter test` verde.

---

## 6. Decisiones tomadas y descartadas

- **Sí:** pausar el tramo y retrasar la llegada. Justificación: el descanso consume tiempo de juego real; la geometría y el progreso se congelan.
- **Sí:** solo coche. Justificación: el vocabulario (área de servicio, gasolinera) es de carretera; tren y barco son sleeper y no se agotan normalmente.
- **Sí:** `RoadRestType` como enum en `domain/models`. Justificación: es lógica de dominio pura, sin dependencias de UI.
- **Sí:** hostel = 70% del hotel. Decisión del Señor (2026-10-30).
- **Sí:** tasa de coche = 6.0%/h. Decisión del Señor (2026-10-30): inferior al hotel (12.5) y al sleeper (10.0), pero mejor que la nada.
- **Sí:** degradación a área de servicio si no se puede pagar. Justificación: evita bloquear el viaje y excepciones sin UI en ruta.
- **Sí:** campos de descanso en `FoggLeg` (no un estado nuevo). Justificación: el tramo sigue siendo el mismo; el descanso es un atributo transitorio del tramo, igual que el flag `_restingAtHotel` de la SPEC 022.
- **Sí:** auto-continuación al 100%. Justificación: el jugador no debe esperar si ya se recuperó.
- **Sí:** botón de despertar siempre disponible. Justificación: el jugador controla cuándo partir.
- **No:** descanso en modos no-coche. Descartado por alcance; si se quiere, spec propia.
- **No:** persistencia. Descartado (spec propia).

---

## 7. Riesgos identificados

| Riesgo | Mitigación |
|---|---|
| `Timer.periodic` pendiente en tests | Se reutiliza `TimeEngine.clock()`; los tests de descanso usan `overrideWith` o inyectan reloj. |
| Múltiples descansos desincronizan `departureUtc` | Cada reanudación desplaza `departureUtc` y `arrivalUtc` por la duración del descanso; `_legStartFatigue` se actualiza al valor actual. |
| La fatiga no llega exactamente a 0 | `_advanceFatigue` clampa a 0.0; la detección usa `mustSleep` (≤ 0). |
| El marcador se mueve durante el descanso | `foggPositionProvider` usa `restProgress` cuando `restType != null`. |
| `FoggLeg` inmutable: hay que reconstruir en reanudación | `_resumeFromRest` construye un nuevo `FoggLeg` con los campos de descanso a `null`. |
| Presupuesto insuficiente en ruta | Degradación a área de servicio (gratuito). |

---

## 8. Lo que **no** está en esta especificación

- Descanso por agotamiento en tren, barco o modos mock.
- Persistencia del descanso o de la partida.
- Eventos de diario / StoryGenerator.
- Animaciones de la parada.
- Cambios en el terminador solar o en el mapa más allá de congelar el marcador.

---

## 9. Referencias

- `lib/domain/models/fatigue.dart` — tasas de cansancio.
- `lib/services/hotel_pricing.dart` — precios de hotel.
- `lib/services/game_session.dart` — `tick()`, `_advanceFatigue`, `_restingAtHotel`.
- `lib/domain/entities/fogg_leg.dart` — tramo.
- `lib/presentation/pages/fogg_status_page.dart` — `_TravelingView`.
- `lib/presentation/providers/fogg_position_provider.dart` — posición de Phoebe.
- `lib/presentation/providers/game_notifier.dart` — `GameNotifier`.
- `docs/specs/022-descansar-en-hotel.md` — tasas y patrón de descanso en hotel.

---

## 10. Preguntas abiertas (resueltas)

1. ¿Qué modos? → Solo coche.
2. ¿El viaje se pausa? → Sí, la llegada se retrasa.
3. ¿El marcador se congela? → Sí.
4. ¿Auto-continuación? → Sí, al 100%.
5. ¿Botón de despertar? → Sí, siempre disponible.
6. ¿Precio del hostel? → 70% del hotel.
7. ¿Tasa en coche? → 6.0%/h.
8. ¿Presupuesto insuficiente? → Degradar a área de servicio.
9. ¿Repetición? → Sí, tantas como haga falta.
10. ¿Dónde se muestra? → En la misma ventana de viaje (`_TravelingView`).

---

**Número:** 023. **Slug:** descanso-por-agotamiento-en-ruta.