# SPEC 017 — Selección de destino y vehículo por tarjetas

> **Estado:** Implementado
>
> **Depende de:** SPEC 001 (AppColors, terminador solar), SPEC 012 (TimeEngine, GameSession, GameNotifier), SPEC 013 (TransportSelector, DestinationOption/VehicleOption), SPEC 016 (foggPositionProvider derivado, CityCatalog)
>
> **Fecha:** 2026-10-23
>
> **Objetivo:** Rediseñar la pantalla de selección de destino y vehículo (`FoggArrived`) para que muestre, en una tarjeta superior, la hora local y la ciudad actual; y para que los destinos se elijan por tarjetas que despliegan vehículos con precio, tiempo y botón «Iniciar trayecto». Retirar el botón de depuración «Simular salida/llegada».

---

## 1. Por qué existe esta especificación

La pantalla de llegada (`_ArrivedView`, `lib/presentation/pages/fogg_status_page.dart:138`) funciona pero no comunica el contexto de la partida: no enseña la **hora local** de la ciudad en la que está Phoebe ni una imagen que dé identidad al sitio, y presenta los vehículos como chips informativos (`VehicleChoiceChip`) sin un gesto claro de «empezar viaje». Además, la tarjeta de destino y los chips mezclan precio y etiquetas en el estado colapsado, lo que satura la lectura cuando hay varios destinos.

Por otro lado, la pantalla mantiene un botón de depuración (`_DebugToggle`) con «Simular salida» y «Simular llegada» que ya no aporta valor con el reloj de juego en marcha (SPEC 016) y deja código y estado huérfanos. Esta especificación limpia esa deuda.

El rediseño separa dos momentos: **elegir** (tarjetas compactas, solo icono) y **detallar** (al elegir destino, sus vehículos se despliegan con precio, duración, sleeper y un botón «Iniciar trayecto»). Tocar un vehículo lo selecciona y arranca la ruta en un solo gesto.

---

## 2. Alcance

**En:**

- **Añade tarjeta de contexto — `lib/presentation/widgets/city_info_card.dart` (nuevo) — `CityInfoCard`** — una única tarjeta con:
  - Sub-bullet: **hora local** de la ciudad actual, calculada como `timeEngineProvider.now()` (UTC del reloj de juego) + `TimezoneService.formatLocalTime(utc, currentCity.timezone)` (DST-correcto, IANA).
  - Sub-bullet: **pin** (`Icons.location_on`) que abre el mapa con zoom medio sobre la ciudad actual y cambia a la pestaña Mapa (mismo comportamiento que el `onPinTap` actual), más el **nombre** de la ciudad actual.
  - Sub-bullet: **imagen genérica** de ciudad (`Image.asset('assets/images/ciudad_generica.jpg')`, `BoxFit.cover` recortada en la tarjeta). Es un placeholder común; en una spec futura será una imagen por ciudad.
- **Rediseña la tarjeta de destino — `lib/presentation/widgets/destination_card.dart` — `DestinationCard`** — tarjeta de bordes redondos que en estado **colapsado** muestra **solo los iconos** de los vehículos disponibles para esa ruta (sin precio, sin etiqueta, sin duración).
  - Sub-bullet: se conserva el nombre de la ciudad como etiqueta sutil de identificación (la ciudad destino no desaparece de la tarjeta).
  - Sub-bullet: en estado **expandido** (destino seleccionado), la tarjeta muestra por cada vehículo: icono, **precio** (`price`€), **tiempo estimado** (`durationLabel`), chip **sleeper** cuando `sleeper == true`, y un botón **«Iniciar trayecto»** inicialmente **deshabilitado**.
- **Un botón por vehículo — `_ArrivedView`** — al tocar una tarjeta de vehículo se selecciona ese vehículo y **se inicia la ruta inmediatamente** (`gameNotifierProvider.startLeg(...)`), transición a `FoggTraveling`. No hay botón global de confirmación.
- **Muestra todas las opciones — `_ArrivedView`** — la lista de destinos recorre **todas** las `options` recibidas de `FoggArrived` (no se recorta a 3 en la vista), manteniendo el orden del motor.
- **Retira el botón de depuración — `_ArrivedView` — se elimina `_DebugToggle`** y su código asociado (alternar `simulateArrival`/`simulateDeparture`, reseteo de selección). Se elimina también `GameSession.simulateDeparture()` si queda sin llamantes, y sus usos de test si procede.
- **Declara el asset — `pubspec.yaml`** — `assets/images/ciudad_generica.jpg`.
- **Tests — `test/widgets/city_info_card_test.dart`, `test/widgets/destination_card_test.dart` (nuevos)** — hora local por zona IANA, expansión de tarjeta, botón deshabilitado/habilitado e inicio de ruta.

**Compartido:** `FoggStatus` (`FoggArrived`), `DestinationOption`, `VehicleOption`, `TransportMode`, `TimezoneService`, `TimeEngine`, `GameNotifier`, `mapFocusProvider`, `bottomNavIndexProvider`, `AppColors`. Sin dependencias nuevas.

**Fuera del alcance (para futuras especificaciones):**

- Imagen distinta por ciudad (esta spec usa una sola imagen genérica).
- Persistencia de la selección o de la partida.
- Cambios en el motor de rutas, precios, duraciones o clima.
- Cambios en el mapa, en el terminador solar o en `WorldMapWidget`.
- Cambios de diseño del estado «viajando» (`_TravelingView`).
- Un botón global de confirmación (se descarta por decisión del Señor).
- Nuevos modos de transporte.

---

## 3. Modelo y diseño de UI

### 3.1 `CityInfoCard` (`lib/presentation/widgets/city_info_card.dart`)

Widget `ConsumerWidget` que recibe la ciudad actual (`FoggCity`) y dibuja una tarjeta de bordes redondos con:

| Elemento | Fuente |
|---|---|
| Imagen genérica | `Image.asset('assets/images/ciudad_generica.jpg', fit: BoxFit.cover)` |
| Hora local | `TimezoneService.formatLocalTime(ref.watch(timeEngineProvider).now(), city.timezone)` |
| Pin | `Icon(Icons.location_on)`; `onTap` → `mapFocusProvider.request(city)` + `bottomNavIndexProvider = 0` |
| Nombre | `city.name` |

Disposición propuesta (contenida en una sola tarjeta):

```
┌─────────────────────────────────────────┐
│ [imagen genérica de ciudad — BoxFit.cover]│
│                                          │
│  🕒 14:32           📍 Londres           │
│  hora local         ciudad actual        │
└─────────────────────────────────────────┘
```

- La hora se recalcula cuando `timeEngineProvider.now()` avanza (el widget observa el provider y se repinta en cada rebuild de la pantalla; no introduce un `Timer` propio).
- El pin y la fila de ciudad son interactivos: abren el mapa (`request(city, zoom: 7.0)`), igual que el `onPinTap` actual de `DestinationCard`.

### 3.2 `DestinationCard` (`lib/presentation/widgets/destination_card.dart`)

Se reescribe la tarjeta. Parámetros:

```dart
class DestinationCard extends StatelessWidget {
  const DestinationCard({
    super.key,
    required this.option,
    required this.selected,          // destino elegido → expandido
    required this.onTap,             // selecciona/expande el destino
    required this.onVehicleTap,      // selecciona vehículo e inicia ruta
    required this.selectedVehicle,   // VehicleOption? — para marcar selección
    this.onPinTap,                   // pin opcional (mismo comportamiento)
  });
  ...
}
```

Estados:

- **Colapsado** (`selected == false`): tarjeta de bordes redondos con el **nombre de la ciudad** y **solo los iconos** de `option.vehicles`. Sin precios, sin duraciones, sin etiquetas de modo.
- **Expandido** (`selected == true`): además de la cabecera, por cada vehículo una fila con icono, `price`€, `durationLabel`, chip «sleeper» si `sleeper`, y botón **«Iniciar trayecto»**:
  - `FilledButton` deshabilitado (`onPressed: null`) mientras ese vehículo no esté seleccionado.
  - Al tocar la fila del vehículo (`onVehicleTap`) se marca `selectedVehicle` y se habilita el botón de ese vehículo.
  - El botón habilitado ejecuta `onVehicleTap` (inicia la ruta).

Reglas:

- Un vehículo con `weatherImpact?.cancelled == true` no se puede seleccionar (fila atenuada, `onTap` inerte) y su botón permanece deshabilitado; se muestra el `reason` si existe. (Comportamiento ya presente en el motor; la tarjeta lo refleja.)
- El chip «sleeper» solo aparece cuando `vehicle.sleeper`.
- Se elimina `VehicleChoiceChip` si deja de tener consumidores (código muerto).

### 3.3 `_ArrivedView` (`lib/presentation/pages/fogg_status_page.dart`)

Nueva composición, de arriba abajo:

1. `CityInfoCard(currentCity: <ciudad actual>)`.
2. Sección «Destinos disponibles» con un `DestinationCard` por cada `option` de `options` (sin recorte).
3. Al seleccionar un destino (`selectedDestinationProvider`), solo esa tarjeta se expande; las demás permanecen colapsadas.
4. Al tocar un vehículo: se asigna `selectedVehicleProvider`, se habilita su botón y se llama a `startLeg(from: <ciudad actual>, to: <destino>, vehicle: <vehículo>)`. Tras iniciar, se limpian `selectedDestinationProvider` y `selectedVehicleProvider`.
5. Se mantiene `_DebugToggle` eliminado y se retira el `FilledButton` global «Confirmar viaje».

> Nota: la ciudad de origen para `startLeg` debe ser la ciudad actual del estado (`FoggArrived.currentCity`), no `options.first`. Hoy `_ArrivedView` recibe `currentCityName` y reconstruye la ciudad desde `options`, lo que es frágil; esta spec pasa el `FoggCity` completo.

### 3.4 Provider y estado

- Se mantienen `selectedDestinationProvider` (`DestinationOption?`) y `selectedVehicleProvider` (`VehicleOption?`) en `lib/presentation/providers/fogg_status_provider.dart`.
- No se añaden providers nuevos. Si tras retirar el debug toggle algún provider/estado queda sin consumidor, se elimina.

### 3.5 Asset

- Fichero: `assets/images/ciudad_generica.jpg`.
- Origen: Pixnio, obra «Ciudad, Cityscape, arquitectura, aéreo, urbano, céntrico, metrópoli, calle», 3283×2188, JPEG, licencia **CC0** (dominio público, sin atribución obligatoria).
  - URL directa: `https://pixnio.com/free-images/2017/08/30/2017-08-30-07-00-08.jpg`
  - Página: `https://pixnio.com/es/arquitectura/centro-ciudad/ciudad-cityscape-arquitectura-aereo-urbano-centrico-metropoli-calle`
- Se descargará el original y se declarará en `pubspec.yaml`:

```yaml
flutter:
  assets:
    - assets/data/locations.json
    - assets/images/ciudad_generica.jpg
```

---

## 4. Plan de implementación

1. **Descarga la imagen** — `curl -L https://pixnio.com/free-images/2017/08/30/2017-08-30-07-00-08.jpg -o assets/images/ciudad_generica.jpg` — y declara el asset en `pubspec.yaml`. Prueba: `flutter pub get`.
2. **Crea `CityInfoCard` — `lib/presentation/widgets/city_info_card.dart`** — tarjeta con imagen, hora local (`timeEngineProvider.now()` + `TimezoneService.formatLocalTime`), pin y nombre. Prueba: `flutter analyze`.
3. **Crea `test/widgets/city_info_card_test.dart` (TDD)** — con `TimezoneService.init()` y un `TimeEngine` de reloj fijo: verifica que la hora mostrada corresponde a la zona IANA de la ciudad (p. ej. Tokio `UTC+9` frente a UTC), que se renderiza el nombre y que el pin dispara el foco del mapa. Ejecutar `flutter test test/widgets/city_info_card_test.dart`.
4. **Reescribe `DestinationCard` — `lib/presentation/widgets/destination_card.dart`** — estado colapsado (solo iconos + nombre) y expandido (precio, duración, sleeper, botón «Iniciar trayecto»). Elimina `VehicleChoiceChip` si ya no se usa. Prueba: `flutter analyze`.
5. **Crea `test/widgets/destination_card_test.dart`** — colapsado no muestra precio/duración; `selected == true` muestra precio, duración y botón deshabilitado; tocar vehículo habilita su botón; vehículo cancelado no es seleccionable. Ejecutar `flutter test test/widgets/destination_card_test.dart`.
6. **Rehace `_ArrivedView` — `lib/presentation/pages/fogg_status_page.dart`** — integra `CityInfoCard`, recorre todas las `options`, expande la seleccionada, inicia ruta al tocar vehículo y usa `FoggArrived.currentCity` como origen. Prueba: `flutter analyze`.
7. **Retira el debug toggle — `lib/presentation/pages/fogg_status_page.dart`** — elimina `_DebugToggle` y su estado asociado. Revisa `GameSession.simulateDeparture()`/`GameNotifier.simulateDeparture()` y elimínalos si quedan sin llamantes (ajusta sus tests). Prueba: `flutter analyze`.
8. **Actualiza tests afectados** — `test/presentation/game_notifier_test.dart` y los que usen `simulateDeparture`, si cambian. Ejecutar `flutter test`.
9. **Verifica** — `flutter analyze` (sin lints nuevos; se mantiene el `info` preexistente de `test/services/sun_terminator_service_test.dart:291`) y `flutter test` (todos verdes).
10. **Prueba manual en dispositivo** — `flutter run -d 5lcqy54d4l4ltspz`; comprobar en la pestaña Fogg el flujo: tarjeta superior → destino → vehículo → viaje.

---

## 5. Criterios de aceptación

- [ ] La pantalla de llegada muestra una única tarjeta superior con hora local, pin, nombre de la ciudad actual e imagen genérica.
- [ ] La hora local se deriva de `timeEngineProvider.now()` y de la zona IANA de la ciudad actual (DST-correcta), no de la hora del dispositivo ni de `'UTC'`.
- [ ] El pin abre la pestaña Mapa con zoom medio sobre la ciudad actual.
- [ ] Se muestran **todas** las opciones de destino devueltas por `FoggArrived`, no solo 3.
- [ ] La tarjeta de destino colapsada muestra solo los iconos de los vehículos (y el nombre de la ciudad), sin precio ni duración.
- [ ] Al seleccionar un destino, su tarjeta se expande y muestra precio, tiempo estimado, chip sleeper cuando aplica y el botón «Iniciar trayecto» deshabilitado.
- [ ] Al tocar una tarjeta de vehículo se selecciona ese vehículo y su botón «Iniciar trayecto» se habilita.
- [ ] Tocar el botón habilitado inicia la ruta (`FoggTraveling`) con el vehículo y el destino correctos.
- [ ] Los vehículos cancelados por clima no son seleccionables y su botón permanece deshabilitado.
- [ ] No existe ya el botón «Simular salida/llegada» ni código muerto asociado.
- [ ] `assets/images/ciudad_generica.jpg` está versionado y declarado en `pubspec.yaml`.
- [ ] `flutter analyze` sin errores ni lints nuevos.
- [ ] `flutter test` pasa con todos los tests verdes.
- [ ] No se modifican `assets/data/*.json`, `tools/` ni las skills.

---

## 6. Decisiones tomadas y descartadas

- **Sí:** hora local con `timeEngineProvider.now()` + zona IANA. Por qué: es el reloj de la partida (acelerado en debug); usar la hora del dispositivo descontextualiza la ciudad y rompe la coherencia con el mapa y el terminador solar.
- **Sí:** imagen CC0 de Pixnio. Por qué: dominio público sin atribución obligatoria, a diferencia de Unsplash (licencia propia con crédito). Una sola imagen genérica evita multiplicar assets antes de tener arte por ciudad.
- **Sí:** mantener la tarjeta de destino casi igual, con la diferencia de que los vehículos contenidos muestran solo el icono. Por qué: conserva la lectura actual de la pantalla y reduce el cambio visual al mínimo pedido por el Señor.
- **Sí:** un botón «Iniciar trayecto» por vehículo, que se habilita al seleccionar ese vehículo y arranca la ruta. Por qué: un solo gesto para elegir y partir; elimina el paso intermedio del botón global.
- **No:** botón global de confirmación. Por qué: el Señor pidió un botón por vehículo; había dos formas de leer el requisito y se descartó la global.
- **Sí:** mantener el pin del destino con navegación al mapa. Por qué: comportamiento ya existente y útil; se traslada también a la tarjeta superior.
- **Sí:** pasar el `FoggCity` completo (origen) a `_ArrivedView`. Por qué: reconstruir la ciudad origen desde `options.firstWhere(...)` es frágil y puede elegir un destino como origen.
- **Sí:** eliminar el botón debug «Simular salida/llegada» y su código. Por qué: con el reloj de juego (SPEC 016) el estado avanza solo; el botón es deuda y código muerto.
- **No:** imagen por ciudad en esta spec. Por qué: requiere un mapa ciudad→asset; se hará cuando exista el arte.
- **No:** tocar el motor de rutas, precios, duraciones o clima. Por qué: esta spec es de presentación e interacción; el motor ya provee los datos.

---

## 7. Riesgos

| Riesgo | Mitigación |
|---|---|
| La hora local no se actualiza si el widget no observa el reloj | `CityInfoCard` es `ConsumerWidget` y lee `timeEngineProvider.now()` en `build`; sin `Timer` propio, respeta el guardarraíl de tests de `TimeEngine.clock()` |
| Zona IANA inválida o ciudad mock con `timezone: 'UTC'` | `TimezoneService._locationFor` cae a `UTC`; el peor caso es mostrar hora UTC sin romper |
| La imagen ocupa demasiado y ralentiza el primer frame | Se renderiza recortada (`BoxFit.cover`) en una tarjeta de altura fija; el asset es local, sin red |
| Eliminar `simulateDeparture` rompe tests existentes | Se localizan sus llamantes (`grep`) y se ajustan o eliminan en el mismo paso; `flutter test` al final lo confirma |
| Estado de selección huérfano tras iniciar la ruta | Al iniciar se limpian `selectedDestinationProvider` y `selectedVehicleProvider`, igual que hoy |
| El botón por vehículo se habilita y no arranca por doble estado | Un único `onVehicleTap` marca selección y llama a `startLeg`; el botón habilitado reutiliza la misma llamada |

---

## 8. Lo que **no** está en esta especificación

- Imagen específica por ciudad.
- Persistencia de selección o de partida.
- Cambios en el mapa, terminador solar o `WorldMapWidget`.
- Cambios al estado «viajando».
- Cambios al motor de rutas, precios, duraciones o clima.
- Botón global de confirmación.
- Nuevos modos de transporte o rutas.

Cada uno de ellos, si aterriza, irá en su propia especificación.

---

## 9. Referencias

- `lib/presentation/pages/fogg_status_page.dart:138` — `_ArrivedView` (pantalla que se rediseña).
- `lib/presentation/pages/fogg_status_page.dart:287` — `_DebugToggle` (se elimina).
- `lib/presentation/widgets/destination_card.dart:13` — `DestinationCard` (se reescribe).
- `lib/presentation/widgets/destination_card.dart:164` — `VehicleChoiceChip` (candidato a eliminación).
- `lib/domain/entities/destination_option.dart` — `DestinationOption` y `VehicleOption` (`price`, `duration`, `sleeper`, `weatherImpact`).
- `lib/domain/entities/fogg_status.dart:23` — `FoggArrived` (estado que alimenta la pantalla).
- `lib/presentation/providers/fogg_status_provider.dart:12` — `selectedDestinationProvider` / `selectedVehicleProvider`.
- `lib/presentation/providers/game_notifier.dart:45` — `startLeg`.
- `lib/presentation/providers/time_engine_provider.dart` — reloj de juego.
- `lib/services/timezone_service.dart:70` — `formatLocalTime` (hora civil DST-correcta).
- `lib/presentation/providers/map_focus_provider.dart:40` — `request(city, zoom)`.
- `lib/presentation/providers/bottom_nav_provider.dart` — índice de pestaña Mapa (0).
- `lib/utils/app_colors.dart` — tokens de color (`foggRed`, `surface`, `surfaceVariant`, `labelColor`).
- Pixnio, imagen CC0 — `https://pixnio.com/free-images/2017/08/30/2017-08-30-07-00-08.jpg`.

---

## 10. Preguntas abiertas (resueltas)

- ¿De dónde sale la hora local? → `timeEngineProvider.now()` + zona IANA de la ciudad actual.
- ¿Qué imagen genérica? → Pixnio CC0, `2017-08-30-07-00-08.jpg`.
- ¿Cambian las tarjetas de destino? → Casi iguales; los vehículos contenidos pasan a mostrar solo el icono.
- ¿Botón global o por vehículo? → Uno por vehículo; al pulsarlo se selecciona e inicia la ruta.
- ¿Se mantiene el pin? → Sí, navega al mapa con zoom medio y cambia de pestaña.
- ¿Se retira el botón de simulación? → Sí, junto con su código muerto.
- ¿Cuántos destinos se muestran? → Todos los que devuelve `FoggArrived.option`.

---

**Número:** 017. **Slug:** seleccion-destino-vehiculo-tarjetas.
