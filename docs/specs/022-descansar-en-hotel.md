# SPEC 022 — Descansar en Hotel

> **Estado:** Implementado

> **Depende de:** SPEC 012 (GameSession, Fatigue, GameLoop), SPEC 017 (selección destino y vehículo por tarjetas), SPEC 019 (precios de coche reales, patrón GeoPricing/CarPricing), SPEC 021 (barra indicadora de cansancio)

> **Fecha:** 2026-10-29

> **Objetivo:** Integrar en la pantalla de selección de destino y vehículo una tarjeta «Descansar en Hotel» con el importe del hotel, y aplicar las tasas de cansancio de Phoebe: ciudad 3%/h, sleeper 10%/h, hotel 12.5%/h, coche 8%/h.

---

## 1. Por qué existe esta especificación

Hoy la fatiga de Phoebe se drena con una única tasa (`5.0` puntos por hora) mientras viaja en `FoggTraveling` y no se drena mientras espera en `FoggArrived`.

El descanso existe solo indirectamente: `VehicleOption.sleeper` influye en `TimeEngine.nextDeparture` y en una recuperación genérica de `GameSession.sleep`. No existe el descanso en hotel ni la acción «Descansar en Hotel» con importe asociado.

La SPEC 021 añadió la visualización de la fatiga en la `FoggAppBar`. Falta la acción de descansar y las tasas contextuales por estado. Esta especificación las introduce y las conecta con la pantalla de destino y vehículo.

---

## 2. Alcance

**En:**

- **Integra la tarjeta 'Descansar en Hotel' con el importe en la pantalla de destino y vehículo — `_ArrivedView` y `DestinationCard` — `lib/presentation/pages/fogg_status_page.dart`, `lib/presentation/widgets/destination_card.dart`** — añade una tarjeta de descanso con icono de hotel, label «Ir al Hotel a descansar», sin iconos de vehículo y mensaje de estado al expandir.
- **Aplica la tasa de cansancio por contexto — `Fatigue`, `TimeEngine`, `GameSession` — `lib/domain/models/fatigue.dart`, `lib/services/time_engine.dart`, `lib/services/game_session.dart`** — drena 3%/h en ciudad, recupera 10%/h en sleeper, recupera 12.5%/h en descanso en hotel, drena 8%/h en coche.
- **Calcula y descuenta el importe del hotel — nuevo `HotelPricing`, `GameSession`, `BudgetService` — `lib/services/hotel_pricing.dart`, `lib/services/game_session.dart`, `lib/services/budget_service.dart`** — importe = tarifa por noche por zona geográfica × multiplicador del país; redondeo a entero en €.

**Compartido:** `Fatigue`, `FoggStatus`, `GameSession`, `GameNotifier`, `BudgetService`, `HotelPricing`, `GeoPricing`.

**Fuera del alcance (para futuras especificaciones):**

- Estancia de hotel por noches o tarifas dinámicas.
- Desglose del importe del hotel en componentes (noche + servicios).
- Diary / StoryGenerator (carta antes de dormir).

---

## 3. Modelo y diseño

### 3.1 Tasas de cansancio

| Contexto | Comportamiento | Tasa |
|---|---|---|
| Ciudad (`FoggArrived`, sin descanso) | Drena | 3.0%/h |
| Tramo con `VehicleOption.sleeper == true` | Recupera | 10.0%/h |
| Descanso en hotel | Recupera | 12.5%/h |
| Coche (`sleeper == false`) | Drena | 8.0%/h |
| Otros modos sin sleeper (mocks) | Drena (genérico) | 5.0%/h |

- Dren: `fatigue.drain(elapsedHours * rate)`.
- Recup: `fatigue.recover(elapsedHours * rate)`.
- `TimeEngine.sleepNeeded`: horas = `(missing / rate).ceil().clamp(1, 8)`.

### 3.2 Descanso en hotel

- Flag interno en `GameSession`: `_restingAtHotel` (falso por defecto).
- Activo mientras la tarjeta «Ir al Hotel a descansar» está en curso.
- `tick()` mientras `FoggArrived` y descanso activo: recupera a 12.5%/h.
- Al iniciar la ruta (`startLeg`): descanso se interrumpe y arranca el viaje (con `SleepRequiredException` si `mustSleep` y el vehículo no es sleeper; con `InsufficientBudgetException` si el importe no se cubre).

### 3.3 Precio del hotel

- Nuevo `HotelPricing` (`lib/services/hotel_pricing.dart`).
- Tarifa por noche por `GeoZone`, × multiplicador del país.
- Importe: entero en €, redondeado una sola vez.

---

## 4. Plan de implementación

1. Añadir constantes de tasa en el modelo de fatiga y actualizar `TimeEngine.sleepNeeded`.
2. Actualizar `GameSession.tick()` con las tasas por contexto y el flag de descanso.
3. Crear `HotelPricing` (nuevo servicio).
4. Descontar el importe del hotel vía `BudgetService`.
5. Extender `DestinationCard` para la tarjeta de descanso (label y mensaje al expandir).
6. Conectar la tarjeta en `_ArrivedView`.
7. Añadir/actualizar tests y verificar con `flutter analyze` y `flutter test`.

---

## 5. Criterios de aceptación

- [ ] Mientras Phoebe espera en ciudad sin descanso, la fatiga drena 3%/h.
- [ ] Mientras viaja en sleeper, la fatiga recupera 10%/h.
- [ ] Mientras descansa en hotel, la fatiga recupera 12.5%/h.
- [ ] Mientras viaja en coche, la fatiga drena 8%/h.
- [ ] La pantalla de destino y vehículo muestra la tarjeta «Ir al Hotel a descansar» con icono de hotel, precio, sin iconos de vehículo y mensaje al expandir.
- [ ] Al iniciar la ruta con descanso en curso, el descanso se interrumpe y arranca el viaje.
- [ ] El importe del hotel se calcula por zona geográfica y país y se descuenta del presupuesto.
- [ ] `flutter analyze` sin errores nuevos y `flutter test` verde.

---

## 6. Decisiones tomadas y descartadas

- **Sí:** flag de descanso en `GameSession`. Justificación: menor invasión al `sealed class FoggStatus`; el descanso es transitorio, no un estado de llegada.
- **No:** flag dentro de `FoggArrived`. Justificación: descanso y llegada son conceptos distintos.
- **Sí:** el descanso se resuelve con recuperación continua y termina al iniciar la ruta. Justificación: el jugador descansa mientras elige destino/vehículo; la interrupción es la acción de partir.
- **No:** descanso de noche fija. Justificación: la recuperación por tasa ya cubre el caso y evita duplicar reglas.
- **Sí:** importe = tarifa por noche por zona × multiplicador país. **No:** desglose por componentes.
- **Sí:** el barco es sleeper. Justificación: `TariffTable.defaults[TransportMode.ship].sleeper == true` (`lib/services/transport_selector.dart:23`); el tramo en barco entra en la recuperación de 10%/h, igual que el tren. **No:** tratar al barco como no sleeper en el cálculo de descanso.

---

## 7. Riesgos identificados

| Riesgo | Mitigación |
|---|---|
| El test existente de fatiga en viaje (sleeper) debe reescribirse, porque ahora recupera | Actualizar expectativas a la nueva tasa. |
| Coherencia entre `TimeEngine.sleepNeeded`, `nextDeparture` y las tasas | Unificar el cálculo de horas desde la tasa. |

---

## 8. Lo que **no** está en esta especificación

- Estancia por noches o tarifas dinámicas.
- Desglose del importe del hotel.
- Diary / StoryGenerator.

---

## 9. Referencias

- `lib/domain/models/fatigue.dart` — modelo de fatiga.
- `lib/services/time_engine.dart` — reloj, descanso, `sleepNeeded`.
- `lib/services/game_session.dart` — tick, descanso, inicio de ruta.
- `lib/services/hotel_pricing.dart` — nuevo servicio de precios de hotel.
- `lib/presentation/pages/fogg_status_page.dart` — `_ArrivedView`.
- `lib/presentation/widgets/destination_card.dart` — tarjeta de destino/descanso.
- `lib/services/geo_pricing.dart`, `lib/services/car_pricing.dart` — patrón de precios por zona.

---

## 10. Preguntas abiertas (resueltas)

1. ¿Dónde vive el botón «Descansar en Hotel»? → En la pantalla de destino y vehículo, como tarjeta tipo destino.
2. ¿Cuándo termina el descanso? → Al seleccionar destino y vehículo e iniciar la ruta.
3. ¿Cómo se modela el descanso? → Flag en `GameSession`.
4. ¿Cómo se calcula el importe? → Tarifa por noche por zona × multiplicador país.

---

## Addenda — Tarjeta independiente (2026-10-29)

- Tras la implementación de la SPEC 022, el diseño se revisó: la tarjeta «Ir al Hotel a descansar» **no** debe vivir dentro de cada `DestinationCard` como si fuera una opción o vehículo del destino; sino que debe ser **una tarjeta independiente similar a un destino, y la primera opción** de la lista.
- El montaje se movió a `_ArrivedView` (`lib/presentation/pages/fogg_status_page.dart`) con el nuevo widget `HotelRestCard` (`lib/presentation/widgets/hotel_rest_card.dart`), renderizado como primera opción antes de los destinos candidatos.

**Número:** 022. **Slug:** descansar-en-hotel.
