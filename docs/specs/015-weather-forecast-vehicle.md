# SPEC 015 — Previsión meteorológica por vehículo

> **Estado:** Implementado

> **Depende de:** SPEC 012 (bucle de juego, TimeEngine, BudgetService, GameSession), SPEC 013 (rutas reales, TransportSelector), SPEC 014 (EventEngine mock, WeatherService), SPEC 001 (AppColors)

> **Fecha:** 2026-10-21

> **Objetivo:** Mostrar, junto a cada vehículo disponible, la previsión meteorológica del peor tramo (origen o destino) para su hora de salida/llegada, y aplicar retrasos proporcionales o cancelaciones según el clima, sin alterar el precio.

---

## 1. Por qué existe esta especificación

SPEC 014 introduce el clima y los eventos, pero el jugador aún no ve la previsión al elegir vehículo. Sin información meteorológica en la UI, no puede evitar un barco que se retrasará por viento en contra o un tren cancelado por nieve. Esta especificación cierra ese hueco: la previsión acompaña a cada opción y el motor aplica el impacto al tiempo de viaje (precio intacto).

---

## 2. Alcance

**En:**

- **Amplía `WeatherSnapshot` — `lib/domain/models/weather_snapshot.dart`** — añade `windSpeedKmh`, `windDirectionDeg`, `windGustsKmh`, `visibilityM`, `precipitationMm`, `snowfallCm`, `snowDepthM`, `weatherCode`. Mantiene campos existentes.
- **Servicio meteorológico — `lib/services/weather_service.dart`** — `fetch(lat, lng, atUtc)` consulta Open-Meteo (horario) y devuelve el snapshot de la hora más cercana; caché básica en memoria por `(lat, lng, hour)`; fallback neutro si falla (sin lanzar).
- **Impacto por modo — `lib/domain/models/weather_impact.dart`** — `WeatherImpact { delay, cancelled, reason }` y `WeatherImpact.forMode(mode, origin, destination, departureUtc, arrivalUtc)` usando el peor de origen/destino.
- **Reglas lineales y umbrales — `lib/services/weather_impact_rules.dart`** (o integrado en `WeatherImpact`) — retraso proporcional por viento en contra y cancelación por umbrales fijos por modo.
- **Integración en `TransportSelector` — `lib/services/transport_selector.dart`** — parámetro opcional `WeatherService? weatherService` (y `DateTime? now`); si presente, cada `VehicleOption` incluye `weatherImpact` y `duration` ya incluye el retraso; si null, comportamiento actual (compatible con tests).
- **Integración en `GameSession` — `lib/services/game_session.dart`** — no selecciona vehículos cancelados (lanza `WeatherCancellationException` si se intenta); aplica retraso ya incluido en `duration`.
- **UI — `lib/presentation/widgets/destination_card.dart` y `vehicle_choice_chip`** — muestra icono/temp/viento/riesgo y deshabilita con motivo si cancelado.
- **Tests TDD — `test/services/weather_impact_test.dart`, `test/services/weather_service_test.dart`** — reglas con snapshots fake, sin red.

**Compartido:** `FoggCity`, `FoggLeg`, `VehicleOption`, `DestinationOption`, `TransportMode`, `WeatherSnapshot`, `TimezoneService`, `GameSession`, `TransportSelector`, `EventEngine`. Sin nuevas dependencias (usa `dart:io` HttpClient).

**Fuera del alcance:**
- API marina (oleaje/swell) en vivo; se usa viento como proxy en MVP.
- Persistencia de previsión entre sesiones.
- Notificaciones push por clima.
- Recálculo de previsión en tiempo real durante el viaje.

---

## 3. Modelo de datos

### 3.1 Snapshot ampliado (`lib/domain/models/weather_snapshot.dart`)

```dart
class WeatherSnapshot {
  const WeatherSnapshot({
    required this.timestampUtc,
    this.temperatureC,
    this.condition,
    this.windSpeedKmh = 0,
    this.windDirectionDeg = 0,
    this.windGustsKmh = 0,
    this.visibilityM = 10000,
    this.precipitationMm = 0,
    this.snowfallCm = 0,
    this.snowDepthM = 0,
    this.weatherCode = 0,
  });
  ...
}
```

### 3.2 Impacto (`lib/domain/models/weather_impact.dart`)

```dart
class WeatherImpact {
  const WeatherImpact({this.delay = Duration.zero, this.cancelled = false, this.reason});
  final Duration delay;
  final bool cancelled;
  final String? reason;
}
```

### 3.3 Reglas por modo

Retraso lineal por viento en contra (solo si componente headwind > 0):

- Barco: `delay = headwindKmh * 0.06 h` (tope 6 h).
- Tren: `delay = headwindKmh * 0.03 h` (tope 3 h) + nieve moderada.
- Coche: `delay = headwindKmh * 0.02 h` (tope 2 h) + precipitación.
- A pie: `delay = headwindKmh * 0.01 h` (tope 1 h) + precipitación.

Cancelación (umbrales fijos):

- **Barco**: viento ≥63 km/h, ráfagas ≥75 km/h, visibilidad <926 m, thunderstorm (weatherCode 95/96/99), precipitación >20 mm/h.
- **Tren**: nieve >0.10 m, temp <-20 °C o >45 °C, viento ≥100 km/h, visibilidad <500 m, thunderstorm, precipitación >20 mm/h.
- **Coche**: visibilidad <200 m, nieve >0.20 m, viento ≥120 km/h, precipitación >30 mm/h, temp <-25 °C o >45 °C.
- **A pie**: temp <-10 °C o >35 °C, visibilidad <500 m, precipitación >5 mm/h, viento ≥60 km/h, nieve >0.05 m.

> **Nota de decisión (2026-10-23):** el modo «a pie» no se implementa en el juego; estas reglas se conservan como referencia y no se aplican a ningún vehículo real.

Si cancelado, `reason` describe el motivo (ej. "Viento ≥63 km/h").

### 3.4 Servicio (`lib/services/weather_service.dart`)

```dart
class WeatherService {
  Future<WeatherSnapshot> fetch(double lat, double lng, DateTime atUtc);
}
```

Consulta `https://api.open-meteo.com/v1/forecast?latitude=..&longitude=..&hourly=temperature_2m,wind_speed_10m,wind_direction_10m,wind_gusts_10m,visibility,precipitation,snowfall,snow_depth,weather_code&timezone=UTC`. Selecciona la hora más cercana a `atUtc`. Caché en memoria por `(lat, lng, hour)`. Si falla, devuelve snapshot neutro.

### 3.5 Integración `TransportSelector`

```dart
TransportSelector({
  required this.catalog,
  this.tariffs = TariffTable.defaults,
  this.weatherService, // opcional
  this.now,            // opcional, default DateTime.now().toUtc()
});
```

Para cada vehículo:
- obtiene snapshot de origen y destino para la hora de salida/llegada (aprox. salida para origen, llegada estimada para destino);
- calcula `WeatherImpact`;
- `duration = baseDuration + impact.delay` (retraso meteorológico incluido);
- `weatherImpact = impact` (null si no hay servicio).

Nota: el retraso de SPEC 014 (`DelayEvent` de `EventEngine`) es adicional y se aplica después sobre `arrivalUtc` en `GameSession`.

### 3.6 Integración `GameSession`

- `WeatherCancellationException` si se intenta iniciar un leg con vehículo cancelado.
- La UI debe deshabilitar; el motor rechaza por seguridad.
- `arrivalUtc` = `departureUtc + vehicle.duration` (incluye retraso meteorológico) + retraso adicional de `EventEngine` (SPEC 014) si existe.
- Precio intacto.

### 3.7 UI

- `VehicleChoiceChip`: muestra icono clima + temp + viento; si `cancelled`, deshabilitado con `reason` (tooltip/badge).
- `DestinationCard`: resumen del destino (icono + temp + viento del peor tramo).
- `VehicleOption` gana `weatherImpact` opcional (compatibilidad).

---

## 4. Plan de implementación

1. **Amplía `WeatherSnapshot` — `lib/domain/models/weather_snapshot.dart`** — nuevos campos. Prueba: `flutter analyze`.
2. **Crea `WeatherImpact` — `lib/domain/models/weather_impact.dart`** — modelo + factory `forMode`. Prueba: `flutter analyze`.
3. **Crea `WeatherService` — `lib/services/weather_service.dart`** — fetch + caché + fallback. Prueba: `flutter analyze`.
4. **Crea `test/services/weather_impact_test.dart` (TDD)** — retraso lineal por viento en contra, cancelación por umbrales, peor de origen/destino. Ejecutar `flutter test test/services/weather_impact_test.dart`.
5. **Integra en `TransportSelector` — parámetro opcional `weatherService`/`now`** — añade `weatherImpact` y retraso a `VehicleOption`. Prueba: `flutter analyze`.
6. **Integra en `GameSession` — `WeatherCancellationException`** — rechaza cancelados. Prueba: `flutter test test/services/game_session_test.dart`.
7. **Actualiza UI — `DestinationCard` + `VehicleChoiceChip`** — muestra previsión y deshabilita cancelados. Prueba: `flutter test` widgets.
8. **Crea `test/services/weather_service_test.dart`** — parseo con JSON fake, fallback. Ejecutar `flutter test test/services/weather_service_test.dart`.
9. **Ejecuta `flutter analyze` y `flutter test`** — objetivo: 0 errores nuevos y todos los tests verdes.

---

## 5. Criterios de aceptación

- [ ] `WeatherSnapshot` incluye viento, dirección, ráfagas, visibilidad, precipitación, nieve, weather code.
- [ ] `WeatherService.fetch` parsea Open-Meteo o devuelve snapshot neutro si falla.
- [ ] `WeatherImpact` calcula retraso lineal por viento en contra.
- [ ] Cancelación por umbrales fijos por modo (barco/tren/coche/pie).
- [ ] Se usa el peor de origen/destino.
- [ ] `TransportSelector` con `weatherService == null` mantiene comportamiento actual (tests verdes).
- [ ] `VehicleOption.duration` incluye retraso cuando hay clima.
- [ ] `VehicleOption.price` no cambia por clima.
- [ ] Vehículos cancelados se muestran deshabilitados con motivo.
- [ ] `GameSession` rechaza iniciar leg cancelado.
- [ ] `flutter analyze` sin errores nuevos.
- [ ] `flutter test` pasa con todos los tests verdes.
- [ ] No se modifican `assets/data/*.json`, `tools/`, ni skills.

---

## 6. Decisiones tomadas y descartadas

- **Sí:** SPEC 015 separada de SPEC 014. Por qué: separa backend (EventEngine) de UX (previsión por vehículo).
- **Sí:** previsión por peor de origen/destino. Por qué: el jugador necesita el riesgo real del tramo.
- **Sí:** retraso lineal por viento en contra. Por qué: determinista y fácil de explicar.
- **Sí:** umbrales fijos por modo. Por qué: reglas claras y testeables.
- **No:** API marina (oleaje) en MVP. Por qué: añade dependencia/latencia; viento como proxy suficiente.
- **Sí:** precio intacto. Por qué: el clima afecta tiempo, no coste base.
- **No:** recalcular previsión durante el viaje. Por qué: fuera de alcance; se evalúa al elegir.

---

## 7. Riesgos

| Riesgo | Mitigación |
|---|---|
| Open-Meteo no disponible | Fallback neutro; sin impacto. |
| Caché desactualizada | Clave por hora; TTL implícito al cambiar hora. |
| Doble aplicación de retraso | El retraso se incluye en `duration` una sola vez al construir la opción. |
| UI compleja | Empezar con badge simple; mejorar en v1. |

---

## 8. Lo que **no** está en esta especificación

- API marina (swell/oleaje) en vivo.
- Persistencia de previsión.
- Notificaciones push.
- Recálculo en tiempo real.
- Ajuste de precio por clima.

---

## 9. Referencias

- `lib/domain/models/weather_snapshot.dart` — `WeatherSnapshot`.
- `lib/services/transport_selector.dart` — `TransportSelector`, `VehicleOption`.
- `lib/presentation/widgets/destination_card.dart` — UI de opciones.
- `lib/services/game_session.dart` — `startLeg`.
- `docs/specs/014-event-engine-mock.md` — EventEngine mock.
- Open-Meteo Forecast API — https://open-meteo.com/en/docs

---

## 10. Preguntas abiertas (resueltas)

- ¿Previsión por origen/destino y vehículo? → Sí, peor de origen/destino, por hora de salida/llegada.
- ¿Deshabilitados con motivo? → Sí.
- ¿Retraso proporcional? → Sí, lineal por viento en contra.
- ¿Afecta a terrestres? → Sí, todos los modos.
- ¿Precio? → No cambia.

**Número:** 015. **Slug:** weather-forecast-vehicle.
