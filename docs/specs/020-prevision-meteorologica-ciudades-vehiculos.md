# SPEC 020 — Previsión meteorológica en ciudades (actual y destinos) y bloqueo de vehículos cancelados

> **Estado:** Implementada
>
> **Depende de:** SPEC 015 (previsión meteorológica por vehículo), SPEC 017 (selección de destino y vehículo por tarjetas)
>
> **Fecha:** 2026-10-28
>
> **Objetivo:** Mostrar bajo el nombre de la ciudad actual (`CityInfoCard`) y bajo cada ciudad destino (`DestinationCard`) la información meteorológica relevante (condición simplificada, temperatura, viento si supera el umbral significativo, lluvia y nieve), y asegurar que los vehículos cancelados por meteorología indiquen su motivo específico y tengan su botón deshabilitado.

---

## 1. Por qué existe esta especificación

SPEC 015 introdujo el modelo meteorológico y su impacto en los vehículos, y SPEC 017 rediseñó la pantalla de selección con tarjetas para las ciudades destino y la ciudad actual. Sin embargo, la información meteorológica actual solo se refleja de forma parcial en los chips de vehículos. El usuario (Phoebe) necesita visualizar de un vistazo el clima tanto en su ubicación actual como en los destinos candidatos antes de decidir su ruta, así como identificar claramente qué vehículos están cancelados y por qué motivo exacto.

---

## 2. Alcance

**En:**
- **Ampliación de `CityInfoCard` (`lib/presentation/widgets/city_info_card.dart`)**:
  - Añade bajo el nombre de la ciudad actual un resumen meteorológico (condición simplificada, temperatura, viento si > umbral, lluvia si > 0, nieve si > 0) consultando `WeatherService.fetchSync(...)` con las coordenadas de la ciudad y el tiempo de juego actual.
- **Ampliación de `DestinationCard` (`lib/presentation/widgets/destination_card.dart`)**:
  - Añade bajo el nombre de cada ciudad destino el mismo resumen meteorológico (condición simplificada, temperatura, viento > umbral, lluvia, nieve) derivado del snapshot meteorológico de la ciudad destino.
- **Vehículos cancelados e interfaz**:
  - Asegura que cualquier vehículo cancelado por meteorología (`weatherImpact?.cancelled == true`) muestre su motivo específico de cancelación (ej. *"Viento >=63 km/h"*, *"Nieve >0.10 m"*, etc.) y tenga el botón de inicio de trayecto estrictamente deshabilitado (`onPressed: null`).
- **Tests unitarios y de widgets**:
  - Pruebas para validar la correcta representación del clima en `CityInfoCard` y `DestinationCard`, así como el bloqueo de vehículos cancelados.

**Fuera del alcance:**
- Nuevas APIs meteorológicas o proveedores externos distintos de Open-Meteo.
- Cambios en el motor de simulación de tiempo o físicas de transporte.

---

## 3. Modelo y diseño de UI

### 3.1 Resumen meteorológico compacto
Bajo el nombre de la ciudad (tanto en la tarjeta de ciudad actual como en las tarjetas de destino), se renderiza una línea de estado meteorológico cuando hay datos disponibles:
- **Temperatura:** p. ej. `18°C`
- **Condición:** etiqueta traducida o simplificada (`clear`, `windy`, `storm`)
- **Viento:** si `windSpeedKmh > 30` (umbral significativo), se muestra la velocidad (p. ej. `💨 45 km/h`)
- **Lluvia:** si `precipitationMm > 0`, se indica (p. ej. `🌧️`)
- **Nieve:** si `snowfallCm > 0` o `snowDepthM > 0`, se indica (p. ej. `❄️`)

### 3.2 Bloqueo de vehículos cancelados
En la vista expandida de `DestinationCard`, las opciones de vehículos que devuelven `weatherImpact?.cancelled == true` muestran:
- Fila atenuada (`opacity: 0.55`).
- El texto exacto de `reason` suministrado por el impacto meteorológico.
- El botón de inicio de trayecto deshabilitado (`onPressed: null`).

---

## 4. Plan de implementación

1. **Añadir helper de formato meteorológico** (o integrar lógica en widgets) para mostrar temperatura, condición, viento (> 30 km/h), lluvia y nieve.
2. **Actualizar `CityInfoCard`** para obtener y mostrar el snapshot meteorológico de la ciudad actual.
3. **Actualizar `DestinationCard`** para mostrar el snapshot meteorológico bajo el nombre del destino.
4. **Verificar el bloqueo de vehículos cancelados** y su motivo en las filas de vehículos.
5. **Ejecutar tests y análisis estático** (`flutter analyze` y `flutter test`).

---

## 5. Criterios de aceptación

- [x] `CityInfoCard` muestra temperatura, condición y alertas meteorológicas (viento > umbral, lluvia, nieve) bajo el nombre de la ciudad actual.
- [x] `DestinationCard` muestra temperatura, condición y alertas meteorológicas bajo el nombre de cada ciudad destino.
- [x] El viento se muestra solo si supera el umbral establecido (30 km/h).
- [x] La lluvia y la nieve se muestran cuando los valores de precipitación o nieve son mayores que cero.
- [x] Los vehículos cancelados por meteorología tienen su botón deshabilitado y muestran el motivo específico de la cancelación.
- [x] `flutter analyze` pasa sin errores nuevos.
- [x] `flutter test` pasa con todos los tests verdes.

---

**Número:** 020. **Slug:** prevision-meteorologica-ciudades-vehiculos.
