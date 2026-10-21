# SPEC 014 — EventEngine mock (retraso + tormenta Open-Meteo)

> **Estado:** Implementado

> **Depende de:** SPEC 012 (bucle de juego, TimeEngine, BudgetService, GameSession), SPEC 013 (rutas reales, TransportSelector), SPEC 001 (AppColors)

> **Fecha:** 2026-10-21

> **Objetivo:** Añadir un `EventEngine` mínimo que genere dos eventos durante un trayecto —retraso (`delay`) y tormenta (`storm`)— a partir de un `WeatherSnapshot` (mock en tests, Open-Meteo en runtime), y aplicar su efecto al `FoggLeg`/fatiga/presupuesto sin romper el bucle de juego existente.

---

## 1. Por qué existe esta especificación

El bucle de juego (SPEC 012) ya gestiona tiempo, presupuesto, fatiga y transiciones, y SPEC 013 conecta rutas reales. Pero el trayecto es determinista: no hay imprevistos. Sin `EventEngine`, la narrativa de Phoebe no tiene fricción (retrasos, tormentas) y no se consume el `WeatherSnapshot` ni Open-Meteo. Esta especificación cierra ese hueco con un motor **mock** de dos eventos, determinista en tests y con integración opcional para no romper los tests existentes.

---

## 2. Alcance

**En:**

- **Modelo de eventos — `lib/domain/models/travel_event.dart`** — sealed `TravelEvent` con `DelayEvent(hours)` y `StormEvent(severity, extraFatigue)`. Incluye `applyTo(FoggLeg)`/`applyTo(Fatigue)` según corresponda.
- **Motor — `lib/services/event_engine.dart`** — `EventEngine` con `roll({required FoggLeg leg, required WeatherSnapshot weather, Random? rng})` que devuelve `List<TravelEvent>` (0..n) usando reglas deterministas. Sin dependencia de red.
- **Clima — `lib/services/weather_service.dart`** — `WeatherService.fetch(lat, lng, atUtc)` que consulta Open-Meteo (sin key) y devuelve el snapshot de la hora más cercana; caché básica por `(lat, lng, hour)`; en tests se inyecta un fake. No bloquea `main()`.
- **Integración opcional en `GameSession` — `lib/services/game_session.dart`** — parámetro opcional `EventEngine? eventEngine`; si presente, al arrancar un leg (`startLeg`) calcula eventos y aplica retraso a `arrivalUtc` y tormenta a fatiga; si null, comportamiento actual. Fallback si lanza.
- **Tests TDD — `test/services/event_engine_test.dart`** — reglas de activación (tormenta si condition == 'storm' o precipitación > umbral; retraso si viento > umbral), determinismo con seed, aplicación de retraso, no eventos en buen tiempo.
- **Mantiene compatibilidad** — tests existentes de `GameSession` siguen verdes con `eventEngine == null`.

**Compartido:** `FoggLeg`, `FoggCity`, `Fatigue`, `WeatherSnapshot`, `TimezoneService`, `GameSession`, `TransportSelector`. Sin nuevas dependencias (http opcional? usar `package:http` si ya existe; si no, `dart:io`/`HttpClient` para evitar dependencia).

**Fuera del alcance (para futuras especificaciones):**
- `EventEngine` completo (huelga, frontera, avería).
- Clima detallado por vehículo y caché avanzada (SPEC 015).
- `Hive` cache offline.
- Persistencia de eventos en `Ledger`/diario.
- UI de alerta de evento en `FoggStatusPage`.

---

## 3. Modelo de datos

### 3.1 Evento (`lib/domain/models/travel_event.dart`)

```dart
sealed class TravelEvent {
  const TravelEvent();
}

class DelayEvent extends TravelEvent {
  const DelayEvent({required this.hours});
  final double hours; // horas añadidas a arrivalUtc
}

class StormEvent extends TravelEvent {
  const StormEvent({required this.severity, required this.extraFatigue});
  final int severity; // 1..3
  final double extraFatigue; // puntos de fatiga adicionales drenados
}
```

### 3.2 Motor (`lib/services/event_engine.dart`)

```dart
class EventEngine {
  EventEngine({this.delayWindKmh = 40, this.stormPrecipMm = 5});

  final double delayWindKmh;
  final double stormPrecipMm;

  List<TravelEvent> roll({
    required FoggLeg leg,
    required WeatherSnapshot weather,
    Random? rng,
  });
}
```

Reglas (mock):
- `DelayEvent(hours: 2)` si `weather` indica viento > `delayWindKmh` (o `condition == 'windy'`).
- `StormEvent(severity, extraFatigue)` si `condition == 'storm'` o precipitación > `stormPrecipMm` (mock: `WeatherSnapshot.condition` puede ser `'storm'`).
- Si ambas condiciones, ambos eventos.
- Si ninguna, lista vacía.
- Determinismo: sin RNG para reglas basadas en weather; RNG solo para variación futura (opcional, no usado en mock).

### 3.3 Clima (`lib/services/weather_service.dart`)

```dart
class WeatherService {
  Future<WeatherSnapshot> fetch(double lat, double lng, DateTime atUtc);
}
```

Usa Open-Meteo con variables horarias y selecciona la hora más cercana a `atUtc`. Parsea a `WeatherSnapshot` (timestampUtc, temperatureC, condition). Caché básica por `(lat, lng, hour)`. Si falla, devuelve snapshot neutro (sin eventos).

### 3.4 Integración `GameSession`

```dart
GameSession({
  required this.timeEngine,
  required this.budget,
  List<FoggCity>? cities,
  TransportSelector? transportSelector,
  EventEngine? eventEngine, // NUEVO, opcional
});
```

En `startLeg`, si `eventEngine != null`:
- obtiene un `WeatherSnapshot` neutro por defecto (sin eventos) o uno inyectado; no llama a red en MVP.
- calcula eventos y aplica:
  - `DelayEvent`: tiempo adicional sobre `arrivalUtc` (independiente de la duración base y del retraso meteorológico de SPEC 015).
  - `StormEvent`: drenaje adicional de fatiga.
- Fallback si lanza.

Simplificación MVP: `GameSession` acepta `EventEngine?` y lo llama con un snapshot neutro por defecto, de modo que la integración queda lista para cuando `WeatherService` se conecte. No rompe tests.

---

## 4. Plan de implementación

1. **Crea `TravelEvent` — `lib/domain/models/travel_event.dart`** — sealed + `DelayEvent`/`StormEvent`. Prueba: `flutter analyze`.
2. **Crea `EventEngine` — `lib/services/event_engine.dart`** — reglas deterministas por weather. Prueba: `flutter analyze`.
3. **Crea `test/services/event_engine_test.dart` (TDD)** — tormenta si condition storm, retraso si viento alto, ambos, ninguno. Ejecutar `flutter test test/services/event_engine_test.dart`.
4. **Crea `WeatherService` — `lib/services/weather_service.dart`** — fetch Open-Meteo + parseo + fallback. Prueba: `flutter analyze`.
5. **Integra en `GameSession` — parámetro opcional `eventEngine`** — aplica retraso a `arrivalUtc` y tormenta a fatiga si hay eventos; fallback si lanza. Prueba: `flutter test test/services/game_session_test.dart`.
6. **Ejecuta `flutter analyze` y `flutter test`** — objetivo: 0 errores nuevos y todos los tests verdes.

---

## 5. Criterios de aceptación

- [ ] `TravelEvent` sealed con `DelayEvent` y `StormEvent`.
- [ ] `EventEngine.roll` devuelve `DelayEvent` cuando el weather indica viento fuerte.
- [ ] `EventEngine.roll` devuelve `StormEvent` cuando condition == 'storm' o precipitación alta.
- [ ] Puede devolver ambos; puede devolver lista vacía.
- [ ] `WeatherService.fetch` parsea Open-Meteo o devuelve snapshot neutro si falla (sin lanzar).
- [ ] `GameSession` con `eventEngine == null` mantiene comportamiento actual (tests verdes).
- [ ] `GameSession` con `eventEngine != null` aplica retraso a `arrivalUtc` cuando hay `DelayEvent`.
- [ ] `flutter analyze` sin errores nuevos.
- [ ] `flutter test` pasa con todos los tests verdes.
- [ ] No se modifican `assets/data/*.json`, `tools/`, ni skills.

---

## 6. Decisiones tomadas y descartadas

- **Sí:** mock de 2 eventos (retraso + tormenta) antes que EventEngine completo. Por qué: MVP mínimo, determinista y testeable.
- **No:** Open-Meteo en tests. Por qué: tests no deben depender de red; se inyecta fake/neutral.
- **Sí:** `eventEngine` opcional en `GameSession` con fallback. Por qué: no rompe SPEC 012.
- **No:** modificar `FoggLeg` con eventos. Por qué: el efecto se aplica a `arrivalUtc`/fatiga; el leg sigue siendo inmutable.
- **Sí:** `WeatherService` con `HttpClient` (sin nueva dependencia). Por qué: evita añadir `package:http`.

---

## 7. Riesgos

| Riesgo | Mitigación |
|---|---|
| Open-Meteo no disponible en runtime | Fallback a snapshot neutro; sin eventos meteorológicos. |
| Aplicar retraso rompe tests de llegada | Solo si `eventEngine != null`; tests existentes usan null. |
| Doble aplicación de tormenta | `roll` se llama una vez por `startLeg`. |

---

## 8. Lo que **no** está en esta especificación

- EventEngine completo (huelga, frontera, avería, viento, nieve).
- Open-Meteo vivo por posición + caché.
- Hive cache offline.
- Persistencia de eventos en Ledger/diario.
- UI de alerta de evento.

---

## 9. Referencias

- `lib/services/game_session.dart` — `startLeg`, `tick`.
- `lib/domain/models/weather_snapshot.dart` — `WeatherSnapshot`.
- `lib/domain/models/fatigue.dart` — `Fatigue`.
- `lib/domain/entities/fogg_leg.dart` — `FoggLeg`, `arrivalUtc`.
- `docs/specs/012-core-game-loop-time-budget.md` — bucle base.
- `docs/specs/013-consumo-rutas-reales-transport-selector.md` — rutas reales.

---

## 10. Preguntas abiertas (resueltas)

- ¿Eventos? → Mock de 2: retraso y tormenta.
- ¿Fuente de clima? → Open-Meteo (sin key) en runtime, fake en tests.
- ¿Integración? → Opcional en `GameSession`, fallback null.
- ¿Determinismo? → Reglas basadas en weather, sin RNG en MVP.

**Número:** 014. **Slug:** event-engine-mock.
