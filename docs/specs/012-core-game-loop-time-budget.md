# SPEC 012 — Bucle de juego: reloj, presupuesto y sesión

> **Estado:** Implementado

> **Depende de:** SPEC 001 (WorldMapWidget, Epsg3857NoRepeat), SPEC 002 (MainScaffold, AppColors), `lib/domain/entities/*`, `lib/services/timezone_service.dart`, `lib/presentation/providers/fogg_status_provider.dart`

> **Fecha:** 2026-10-21

> **Objetivo:** Implementar el reloj de juego escalado, el servicio de presupuesto con libro mayor y la sesión de partida que conecta tiempo, dinero y estado de Phoebe para sustituir los mocks actuales.

---

## 1. Por qué existe esta especificación

Hoy el estado de Phoebe (`FoggStatus`) es mock: las llegadas se simulan con botones debug y los vehículos tienen precios/duraciones inventados. No existe `TimeEngine`, ni `BudgetService`, ni `Ledger`, ni `GameSession`. Sin ellos no hay bucle de juego: no se gasta dinero, no transcurre el tiempo de forma controlada y no se puede verificar la victoria (llegar con presupuesto). Esta especificación cierra ese hueco mínimo para que la app deje de ser un visor y pase a ser un juego jugable en bucle, manteniendo la UI existente.

---

## 2. Alcance

**En:**

- **Crea el reloj de juego escalado — `lib/services/time_engine.dart` — emite tiempo de juego y calcula descanso** — `TimeEngine` con `startUtc`, `timeScale` (forzado a 1.0 en release) y `nextDeparture`.
- **Crea el servicio de presupuesto y libro mayor — `lib/services/budget_service.dart` + `lib/domain/models/ledger_entry.dart` — gasta y registra transacciones** — saldo inicial 1.000.000 € con stream.
- **Crea la sesión de partida y su notifier — `lib/services/game_session.dart` + `lib/presentation/providers/game_notifier.dart` — transiciones de estado reales** — sustituye los mocks por lógica.
- **Añade modelos compartidos mínimos — `lib/domain/models/position.dart`, `diary_entry.dart`, `weather_snapshot.dart`, `fatigue.dart` — base para fases posteriores** — esqueletos con campos mínimos.
- **Implementa barra de fatiga — `lib/domain/models/fatigue.dart` + `GameSession` — drena al viajar y fuerza descanso** — bloquea salidas si fatiga ≤ 0 y no hay sleeper.
- **Migra la UI de estado al nuevo notifier — `lib/presentation/pages/fogg_status_page.dart`, `lib/presentation/providers/countdown_provider.dart` — sin perder funcionalidad** — alias temporal de `foggStatusProvider`.
- **Añade tests TDD para los tres servicios — `test/services/time_engine_test.dart`, `budget_service_test.dart`, `game_session_test.dart`** — cubren escala, descanso, saldo y transiciones.

**Fuera del alcance (para futuras especificaciones):**

- Consumo de rutas reales (`sea_routes.json`, `car_routes.json`, `rail_routes.json`) en Flutter y `TransportSelector` completo.
- `EventEngine` completo (retraso, tormenta, huelga, frontera, avería).
- Integración Open-Meteo viva por posición + `WeatherSnapshot` poblado.
- `Hive` cache offline + sincronización.
- PWA (`manifest.json`, service worker, iconos).
- `DiaryService` + `StoryGenerator` con plantillas/LLM.
- Leaderboard y backend real.

---

## 3. Modelo de datos

```dart
// lib/domain/models/ledger_entry.dart
class LedgerEntry {
  const LedgerEntry({
    required this.timestampUtc,
    required this.amount, // negativo = gasto
    required this.reason,
    required this.balanceAfter,
  });

  final DateTime timestampUtc;
  final int amount; // €
  final String reason;
  final int balanceAfter;
}

// lib/domain/models/position.dart
class Position {
  const Position({
    required this.city, // FoggCity
    required this.utc,
    required this.budget,
    this.fatigue = const Fatigue(),
  });

  final FoggCity city; // reutiliza entidad existente
  final DateTime utc;
  final int budget;
  final Fatigue fatigue;
}

// lib/domain/models/diary_entry.dart
class DiaryEntry {
  const DiaryEntry({
    required this.timestampUtc,
    required this.text,
  });

  final DateTime timestampUtc;
  final String text;
}

// lib/domain/models/weather_snapshot.dart
class WeatherSnapshot {
  const WeatherSnapshot({
    required this.timestampUtc,
    this.temperatureC,
    this.condition,
  });

  final DateTime timestampUtc;
  final double? temperatureC;
  final String? condition;
}

// lib/domain/models/fatigue.dart
class Fatigue {
  const Fatigue({this.value = 100.0});

  final double value; // 0..100

  bool get mustSleep => value <= 0.0;
  Fatigue drain(double amount) => Fatigue(value: (value - amount).clamp(0.0, 100.0));
  Fatigue recover(double amount) => Fatigue(value: (value + amount).clamp(0.0, 100.0));
}
```

```dart
// lib/services/time_engine.dart
class TimeEngine {
  TimeEngine({
    required DateTime startUtc,
    double timeScale = 1.0,
  })  : _startUtc = startUtc.toUtc(),
        _timeScale = _clampScale(timeScale);

  final DateTime _startUtc;
  final double _timeScale; // 1h real = 60 min juego en dev (scale 60)

  DateTime now(); // tiempo de juego escalado
  Stream<DateTime> clock(); // emite cada segundo (guard de tests)

  // Salida inmediata tras descanso si no hay horario programado.
  DateTime nextDeparture(DateTime arrivalUtc, {bool sleeper = false});

  // Primera salida programada (hora local del origen) >= arrival + descanso.
  // Convierte la hora local a UTC con TimezoneService para el origen.
  DateTime nextScheduledDeparture(
    DateTime arrivalUtc, {
    required String originTimezone,
    required int departureHour,
    required int departureMinute,
    bool sleeper = false,
  });

  // Duración de sueño necesaria para recuperar fatiga hasta 100.
  // Si sleeper == true, el sueño puede hacerse en tránsito.
  Duration sleepNeeded(Fatigue fatigue, {bool sleeper = false});
}
```

```dart
// lib/services/budget_service.dart
class BudgetService {
  BudgetService({int initial = 1000000});

  int get balance;
  Stream<int> get balanceStream;
  Stream<LedgerEntry> get ledgerStream;
  List<LedgerEntry> get ledger;
  bool canAfford(int price);
  LedgerEntry spend(int price, String reason); // lanza InsufficientBudgetException
}
```

```dart
// lib/services/game_session.dart
enum GameStatus { traveling, arrived }

class GameSession {
  GameSession({
    required TimeEngine timeEngine,
    required BudgetService budget,
  });

  GameStatus get status;
  FoggLeg? get currentLeg;
  FoggCity get currentCity;
  Fatigue get fatigue;
  List<DestinationOption> get options; // 3 ciudades hacia el este
  Stream<GameStatus> get statusStream;

  void startLeg({
    required FoggCity from,
    required FoggCity to,
    required VehicleOption vehicle,
  }); // bloquea si mustSleep y !sleeper; calcula salida, gasta, transiciona
  void tick(); // drena fatiga al viajar; transiciona a arrived si now >= arrival
  void sleep({required Duration duration}); // recupera fatiga hasta 100
  void simulateArrival(); // solo debug/QA
  void simulateDeparture(); // solo debug/QA
}
```

Convenciones:
- Tiempo siempre en UTC; offset civil se deriva con `TimezoneService`.
- `timeScale` se fuerza a `1.0` si `kReleaseMode` (guardrail de producción).
- `LedgerEntry.amount` negativo = gasto; positivo reservado para ingresos futuros.
- `VehicleOption` gana `departureHour`/`departureMinute` (hora local del origen, 0–23/0–59). Si son `null`, se usa salida inmediata tras descanso (compatibilidad con mocks). La hora de salida real se calcula con `TimezoneService` para la zona IANA del origen.

---

## 4. Plan de implementación

1. Crear `lib/domain/models/ledger_entry.dart`, `position.dart`, `diary_entry.dart`, `weather_snapshot.dart` con los campos mínimos anteriores. Prueba: `flutter analyze` sin errores nuevos.
1b. Extender `VehicleOption` (`lib/domain/entities/destination_option.dart`) con `departureHour`/`departureMinute` opcionales y migrar los mocks para incluir horarios de ejemplo. Prueba: tests de `fogg_status_provider` siguen verdes.
2. Crear `lib/services/time_engine.dart` con constructor, `now()`, `clock()` y `nextDeparture()`. Añadir guard de `Timer.periodic` para tests (patrón `currentUtcProvider`). Prueba manual: test unitario escala 60×.
3. Crear `test/services/time_engine_test.dart` (TDD): escala, descanso 5–8 h, sleeper salta descanso, clamp en release, conversión hora local→UTC con DST, primera salida programada ≥ llegada+descanso. Ejecutar `flutter test test/services/time_engine_test.dart`.
4. Crear `lib/services/budget_service.dart` con saldo inicial, `canAfford`, `spend`, streams. Crear `InsufficientBudgetException`.
5. Crear `test/services/budget_service_test.dart`: gasto correcto, saldo insuficiente lanza, historial ordenado.
6. Crear `lib/services/game_session.dart` con estado, `startLeg` (calcula salida programada o inmediata), `tick` (drena fatiga), candidatos hacia el este (Regla del Este desenrollada) y streams.
6b. Integrar `Fatigue` en `GameSession`: drenado por hora de viaje, bloqueo de `startLeg` si `mustSleep && !vehicle.sleeper`, y método `sleep()` que recupera hasta 100 usando `TimeEngine.sleepNeeded`.
7. Crear `lib/presentation/providers/game_notifier.dart` como `Notifier<GameStatus>` delgado que delega en `GameSession`.
8. Migrar `countdown_provider.dart` para leer `gameNotifierProvider` en lugar de `foggStatusProvider`; mantener `FoggTraveling`/`FoggArrived` como vistas derivadas.
9. Migrar `FoggStatusPage` para usar `gameNotifierProvider`; conservar `_DebugToggle` llamando a `simulateArrival`/`simulateDeparture`.
10. Añadir alias `foggStatusProvider` → `gameNotifierProvider` (compatibilidad con tests existentes) y marcar como deprecated.
11. Crear `test/services/game_session_test.dart`: gasto atómico al iniciar leg, transición a `arrived` cuando `tick()` con tiempo suficiente, 3 candidatos hacia el este, descanso aplicado, drenado de fatiga y bloqueo por sueño.
12. Ejecutar `flutter analyze` y `flutter test`. Objetivo: 0 errores y solo el info preexistente de `prefer_const_constructors`.

---

## 5. Criterios de aceptación

- [ ] `TimeEngine.now()` avanza 60× más rápido que el reloj real cuando `timeScale = 60`.
- [ ] En `kReleaseMode`, `timeScale` se fuerza a `1.0` aunque se pase otro valor.
- [ ] `nextDeparture` devuelve al menos 5 h después de la llegada sin sleeper y permite salida inmediata con sleeper.
- [ ] `nextScheduledDeparture` devuelve la primera salida con hora local del origen que cae en o después de llegada + descanso, convertida correctamente a UTC (incluido DST).
- [ ] Si `VehicleOption.departureHour/Minute` son `null`, `startLeg` usa salida inmediata tras descanso.
- [ ] `Fatigue` se drena mientras `status == traveling` y se recupera con `sleep()`.
- [ ] Si `fatigue.mustSleep` y el vehículo no es sleeper, `startLeg` lanza `SleepRequiredException` y no gasta presupuesto.
- [ ] `BudgetService.spend` reduce el saldo en el precio y añade un `LedgerEntry` con `balanceAfter` correcto.
- [ ] `spend` lanza `InsufficientBudgetException` si el precio supera el saldo y no modifica el saldo.
- [ ] `GameSession.startLeg` descuenta el precio y transiciona a `traveling` con `FoggLeg` válido.
- [ ] `GameSession.tick` transiciona a `arrived` cuando el tiempo de juego alcanza `arrivalUtc`.
- [ ] Al llegar, `options` contiene exactamente 3 ciudades con lng desenrollada mayor que la actual.
- [ ] `countdownProvider` sigue emitiendo la duración restante sin timers pendientes en tests.
- [ ] `flutter analyze` no introduce errores nuevos (solo el info preexistente).
- [ ] `flutter test` pasa con todos los tests verdes.

---

## 6. Decisiones

- **Sí:** tiempo real escalado (1 h real = 1 min de juego) solo en debug; **No:** pasos manuales, porque el reloj debe correr solo.
- **Sí:** preselección del transporte más caro en la UI; **No:** auto-reserva automática, porque el jugador debe confirmar.
- **Sí:** `START_DATE` = fecha actual de inicio; **No:** fecha del lore (1872), para simplificar DST y datos.
- **Sí:** servicio `GameSession` + `Notifier` delgado; **No:** `StateProvider` con lógica inline, por testabilidad y SOLID.
- **Sí:** mantener nombres `Fogg*` y entidades existentes; **No:** crear paquete `shared_models` separado, que ya no existe en el repo.
- **Sí:** guardrail `kReleaseMode` fuerza `timeScale = 1.0`; **No:** permitir escala en producción.
- **Sí:** alias temporal de `foggStatusProvider`; **No:** migración brusca que rompa tests existentes.
- **Sí:** fatiga como recurso 0–100 con descanso forzado; **No:** muerte por fatiga (solo bloquea acciones hasta dormir).
- **Sí:** horarios de salida en hora local del origen (convertidos a UTC con `TimezoneService`); **No:** persistir horas en UTC, porque cambiarían con DST y romperían el lore.

---

## 7. Riesgos

| Riesgo | Mitigación |
|---|---|
| `Timer.periodic` pendiente rompe `flutter test` | Guard de `TestWidgetsFlutterBinding` como en `currentUtcProvider` |
| Carrera entre `tick()` y UI | `GameSession` serializa transiciones y `Notifier` emite estado inmutable |
| Saldo negativo por doble gasto | `spend` atómico con comprobación previa y excepción |
| Regla del Este mal aplicada en candidatos | Reutilizar `FoggRoute.validated` / lng desenrollada y tests |
| Conversión hora local→UTC en transición DST | Usar `TimezoneService.offsetAt` para la fecha concreta de salida, no offset fijo |
| Drenado de fatiga desincronizado con el reloj | Drenar en `tick()` según tiempo de juego transcurrido, no tiempo real |
| Migración rompe tests existentes | Alias temporal + tests de compatibilidad en Fase 4 |

---

## Lo que **no** está en esta especificación

- Consumo de rutas reales en el mapa Flutter.
- `EventEngine` completo y Open-Meteo vivo.
- Persistencia offline (Hive) y PWA.
- `DiaryService` + `StoryGenerator`.
- Leaderboard y backend real.

Cada uno de ellos, si aterriza, irá en su propia especificación.
