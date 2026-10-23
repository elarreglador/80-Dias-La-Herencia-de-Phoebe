# SPEC 016 — Ruta viva y movimiento de Phoebe

> **Estado:** Implementado
>
> **Depende de:** SPEC 012 (TimeEngine, BudgetService, GameSession), SPEC 013 (RouteCatalog, TransportSelector), SPEC 001 (WorldMapWidget, Epsg3857NoRepeat, AppColors)
>
> **Fecha:** 2026-10-22
>
> **Objetivo:** Dibujar en el mapa el trayecto real que Phoebe recorre, con su geometría auténtica, y mover su marcador a lo largo de esa ruta en tiempo de juego.

---

## 1. Por qué existe esta especificación

SPEC 012–015 construyeron el motor del juego (reloj, presupuesto, rutas reales, clima, eventos), pero la pantalla no lo refleja. `lib/presentation/pages/map_tab.dart:19` sigue dibujando `mockFoggRoute` —seis ciudades unidas por líneas rectas— y `lib/presentation/providers/fogg_position_provider.dart:6` es un `StateProvider` con Londres constante: el motor calcula el viaje, la pantalla enseña un itinerario de mentira. Peor aún, `GameSession.tick()` (`lib/services/game_session.dart:150`) no lo invoca nadie fuera de los tests, de modo que la partida nunca avanza sola hasta `FoggArrived`.

Hay además dos pérdidas de información en la cadena actual. `TransportSelector._buildOption` (`lib/services/transport_selector.dart:82`) descarta la `RouteEntry` tras leer `distanceKm` y `durationHours`, así que la geometría elegida nunca sale del selector. Y `DestinationOption.city` se fabrica con `timezone: 'UTC'` fijo, porque la ciudad se deriva del último vértice de la geometría en lugar de `assets/data/locations.json`, que ya está declarado en `pubspec.yaml` pero que ningún código Dart lee.

Esta especificación une motor y pantalla: la geometría real viaja desde el selector hasta el `PolylineLayer`, el reloj del juego mueve a Phoebe sobre esa geometría y el mapa deja de enseñar un plan fijo. El resultado es el primer punto en que el jugador puede *ver* el viaje que está haciendo.

---

## 2. Alcance

**En:**

- **Guarda la ruta elegida en la opción de vehículo — `lib/domain/entities/destination_option.dart` — `VehicleOption` gana `RouteEntry? route`** — el selector deja de tirar la geometría que ya tiene en memoria
  - Sub-bullet: la geometría viaja como `List<List<double>>` (`[lng, lat]` por vértice), sin recalcular distancias ni copiar strings
  - Sub-bullet: `null` en los vehículos mock (sin ruta real), para no romper los tests existentes
- **Guarda la geometría del tramo en curso — `lib/domain/entities/fogg_leg.dart` — `FoggLeg` gana `RoutePath? path`** — el tramo sabe qué línea está recorriendo Phoebe, y con ella su modo y su color
- **Interpola la posición sobre la geometría — `lib/domain/models/route_path.dart` — `RoutePath` con distancia Haversine acumulada** — `positionAt(progress)` devuelve el punto exacto sobre la ruta al `progress` del tramo
  - Sub-bullet: distancia Haversine entre vértices consecutivos, acumulada en `cumulativeKm`
  - Sub-bullet: longitudes desenrolladas (arco más corto, `Δlng` normalizado a ±180°) para que el cruce del antimeridiano no altere la distancia ni la interpolación
- **Parte la línea en el antimeridiano — `RoutePath.renderSegments()` — una polilínea por tramo continuo** — un salto `178.9 → −180` se convierte en dos segmentos, sin la línea horizontal parasite que cruzaría el mapa entero
  - Sub-bullet: si el vértice siguiente no cae exactamente en ±180, la latitud del corte se interpola en Y Mercator (misma técnica que `FoggRoute.polylineSegments`, `lib/domain/entities/fogg_route.dart:55`)
  - Sub-bullet: el CRS del mapa no se toca — se mantiene `Epsg3857NoRepeat` con `drawInSingleWorld: true`
- **Carga el catálogo de ciudades — `lib/services/city_catalog.dart` — `assets/data/locations.json` → `Map<String, FoggCity>`** — resuelve por nombre las coordenadas y el `timezone` IANA reales (304 ciudades)
  - Sub-bullet: `CityCatalog.byName(nombre)` normaliza NFD y no distingue mayúsculas
  - Sub-bullet: `order` = índice en el array del fichero (el catálogo viene ordenado de Oeste a Este)
  - Sub-bullet: sustituye al `timezone: 'UTC'` fijo de `DestinationOption.city`
- **Arranca el reloj de la partida — `lib/presentation/providers/game_notifier.dart` — `GameNotifier` se suscribe a `TimeEngine.clock()`** — el `tick()` que hoy nadie llama pasa a emitirse cada segundo, y la partida llega sola a `FoggArrived`
  - Sub-bullet: `TimeEngine.clock()` (`lib/services/time_engine.dart`) ya corta el `Stream.periodic` en `flutter test` (guard `TestWidgetsFlutterBinding`), así que no queda `Timer` pendiente
  - Sub-bullet: en release `TimeEngine` clampa la escala a 1.0 (80 días reales); en debug sigue a 60 (1 s real = 1 min de juego)
- **Mueve el marcador de Phoebe — `lib/presentation/providers/fogg_position_provider.dart` — `foggPositionProvider` pasa a ser derivado** — se calcula desde el tramo activo y `timeEngine.now()`, en lugar de un valor fijo
  - Sub-bullet: en ruta = `leg.path.positionAt(leg.progressAt(now))`; en ciudad = lat/lng de la ciudad; sin tramo = `null`
- **Pinta el trayecto en el mapa — `lib/presentation/widgets/world_map_widget.dart` — el `PolylineLayer` dibuja la ruta real** — sólido lo recorrido, discontinuo lo pendiente, color por modo
  - Sub-bullet: barco `#1E88E5`, coche `#F9A825`, tren `#6A1B9A`, a pie `#9E9E9E`
  - Sub-bullet: el historial de tramos ya recorridos se conserva en su color de modo, 2 px
  - Sub-bullet: las rutas candidatas se pintan en gris `#9E9E9E` α 0.35 solo mientras Phoebe está en una ciudad y aún no ha elegido trayecto
- **Quita la ruta de mentira del mapa — `lib/presentation/pages/map_tab.dart` — `mockFoggRoute` deja de dibujarse** — el mapa muestra lo que Phoebe ha hecho, no un itinerario fijo
- **Añade la paleta de transporte a los tokens — `lib/utils/app_colors.dart` — `AppColors.routeShip/routeCar/routeTrain/routeFoot/routeCandidate`** — el widget deja de llevar colores privados duplicados
- **Tests — `test/domain/route_path_test.dart`, `test/services/city_catalog_test.dart`, `test/presentation/fogg_position_provider_test.dart`, `test/widgets/world_map_widget_test.dart`** — interpolación, antimeridiano, catálogo, posición y capas del mapa

**Compartido:** `FoggCity`, `FoggLeg`, `VehicleOption`, `DestinationOption`, `RouteEntry`, `RouteCatalog`, `TransportSelector`, `TimeEngine`, `GameSession`, `WorldMapWidget`, `AppColors`. Sin dependencias nuevas.

**Fuera del alcance (para futuras especificaciones):**

- Seguimiento automático de cámara (el botón «Centrar en Phoebe» ya cubre el caso).
- Persistencia de la partida: al recargar, la partida vuelve a empezar.
- Dibujar las rutas candidatas mientras Phoebe está en ruta (solo en ciudad, por decisión del Señor).
- Animación de la ruta (flechas, pulso, cabecera): la línea es estática, solo se mueve el marcador.
- Simplificación de la geometría en memoria: se dibuja la geometría completa tal cual viene.
- Diario de Phoebe y `StoryGenerator` (spec propia).
- `InMemoryBackend` y caché Hive (spec propia).

---

## 3. Modelo de datos

### 3.1 `RoutePath` (`lib/domain/models/route_path.dart`)

Objeto de valor inmutable que encapsula la geometría de un trayecto: puntos, distancia acumulada e interpolación.

```dart
class RoutePath {
  const RoutePath._({required this.points, required this.cumulativeKm});

  /// Puntos en coordenadas reales tal como vienen del catálogo (`lng` en [-180, 180]).
  final List<LatLng> points;

  /// Distancia Haversine acumulada en km. `cumulativeKm.last` es el total.
  final List<double> cumulativeKm;

  double get totalKm => cumulativeKm.isEmpty ? 0 : cumulativeKm.last;

  /// Desde la geometría del catálogo: lista de `[lng, lat]`.
  factory RoutePath.fromGeometry(List<List<double>> geometry);

  /// Tramos sin ruta real (a pie, mocks): recta de origen a destino.
  factory RoutePath.straight(LatLng from, LatLng to);

  /// Punto sobre la ruta al progreso dado (0..1), por distancia acumulada.
  LatLng positionAt(double progress);

  /// Segmentos listos para dibujar, cortados en el antimeridiano.
  List<List<LatLng>> renderSegments();
}
```

Reglas de `fromGeometry`:

- Descarta vértices no numéricos, con `|lat| > 90` o `|lng| > 180`.
- Si quedan menos de 2 puntos válidos, devuelve `null` (la fábrica es `RoutePath?`).
- Mantiene las coordenadas **reales** en `points` (para dibujar) y calcula internamente un array **desenrollado** (para medir e interpolar).

Reglas de `positionAt(progress)`:

- `progress` se recorta a `[0, 1]`.
- Convierte `progress` a distancia objetivo (`progress * totalKm`) y localiza por búsqueda binaria el segmento `i` donde `cumulativeKm[i] <= objetivo <= cumulativeKm[i+1]`.
- Interpola latitud y longitud **en el espacio desenrollado**; la longitud devuelta se normaliza a `[-180, 180)`.
- Con `totalKm == 0` devuelve el primer punto.

Reglas de `renderSegments()`:

- Recorre los puntos reales y detecta el corte del antimeridiano allí donde `|Δlng| > 180` entre vértices consecutivos (en `sea_routes.json` hay 41 de estos saltos, p. ej. `Perth → Apia`: `178.90051 → −180.0`).
- Al cortar: el segmento anterior se cierra en el meridiano y el siguiente se abre en el meridiano opuesto (`+180` / `−180`), de forma que ninguna polilínea contenga ambos valores.
- Si el vértice siguiente ya está exactamente en ±180, se usa tal cual y no se añade un punto duplicado.
- Si el corte no cae en un vértice, la latitud del corte se interpola en Y Mercator (interpolación en `ln(tan(π/4 + lat/2))`), para que ambos segmentos tengan la misma pendiente en pantalla.

### 3.2 `VehicleOption` y `FoggLeg`

```dart
class VehicleOption {
  const VehicleOption({..., this.route});      // RouteEntry? route
  final RouteEntry? route;                     // ruta real elegida; null en mocks
}

class FoggLeg {
  const FoggLeg({..., this.path});             // RoutePath? path
  final RoutePath? path;                       // geometría del tramo en curso
}
```

Ambos campos son opcionales y con valor por defecto `null`: los constructores `const` actuales siguen siendo válidos y ningún test existente se rompe.

### 3.3 `CityCatalog` (`lib/services/city_catalog.dart`)

```dart
class CityCatalog {
  static Future<CityCatalog> load(AssetBundle bundle);

  /// Ciudad por nombre (normalización NFD, sin distinguir mayúsculas).
  FoggCity? byName(String name);

  int get length;
}
```

- Lee `assets/data/locations.json`: `{meta, cities: [{name, asciiname, lat, lng, timezone}]}`.
- Construye `FoggCity(name, lat, lng, order, timezone)` con `order` = índice en el array.
- Si dos ciudades comparten nombre normalizado, gana la primera (el catálogo no debe tener duplicados; si los tuviera, se registra el aviso).
- El proveedor es un `FutureProvider` que usa `rootBundle`, igual que `routeCatalogProvider` (`lib/presentation/providers/route_catalog_provider.dart:8`).

### 3.4 `GameSession` — tramo activo e historial

```dart
FoggLeg? get currentLeg;          // ya existe
List<FoggLeg> get completedLegs;   // nuevo — historial de tramos recorridos
```

- `startLeg` calcula la `RoutePath`: si `vehicle.route` trae geometría, `RoutePath.fromGeometry(vehicle.route!.geometry)`; si no (a pie, mocks), `RoutePath.straight(desde, hasta)`.
- `tick()` ya existente: al llegar, `_currentCity = leg.to` y el tramo se añade a `completedLegs`.
- El historial se reinicia con la partida (no hay persistencia en esta spec).

### 3.5 `GameNotifier` — el reloj de la partida

```dart
class GameNotifier extends Notifier<FoggStatus> {
  @override
  FoggStatus build() {
    final session = ref.watch(gameSessionProvider);
    session.statusStream.listen((s) => state = s);
    final sub = session.timeEngine.clock().listen((_) {
      session.tick();
      state = session.status;
    });
    ref.onDispose(sub.cancel);
    return session.status;
  }
}
```

- `TimeEngine.clock()` (`lib/services/time_engine.dart`) emite el primer valor de inmediato y luego uno por segundo; en `flutter test` emite **solo el primero** y termina, de modo que no queda `Timer.periodic` pendiente (mismo guardarraíl que usa `currentUtcProvider`).
- El `Notifier` ya está registrado como `gameNotifierProvider` y es observado por la pestaña Fogg, de modo que el reloj arranca con la app.

### 3.6 `foggPositionProvider` — derivado

```dart
final foggPositionProvider = Provider<LatLng?>((ref) {
  final status = ref.watch(gameNotifierProvider);
  final now = ref.watch(timeEngineProvider).now();
  return switch (status) {
    FoggTraveling(leg: final leg) =>
      leg.path?.positionAt(leg.progressAt(now)) ?? LatLng(leg.from.lat, leg.from.lng),
    FoggArrived(currentCity: final city) => LatLng(city.lat, city.lng),
  };
});
```

- Deja de ser `StateProvider`: nadie debe escribir la posición a mano, se deriva del estado de la partida.
- `timeEngineProvider` (`lib/presentation/providers/game_notifier.dart:12`) usa `timeScale: 60.0` en debug y el `TimeEngine` clampa a 1.0 en release.

### 3.7 Paleta (`lib/utils/app_colors.dart`)

```dart
static const routeShip      = Color(0xFF1E88E5);  // barco   — mismo que el visor dev
static const routeCar       = Color(0xFFF9A825);  // coche   — mismo que el visor dev
static const routeTrain     = Color(0xFF6A1B9A);  // tren    — mismo que el visor dev
static const routeFoot      = Color(0xFF9E9E9E);  // a pie   — sin ruta real
static const routeCandidate = Color(0xFF9E9E9E);  // candidatas (se usa con α 0.35)
```

### 3.8 Capas del mapa (`lib/presentation/widgets/world_map_widget.dart`)

El orden de las capas **no cambia** (lo aserta el test actual): `children[0]` `TileLayer`, `children[1]` `PolygonLayer` (overlay nocturno), `children[2]` `PolylineLayer`, y las capas de marcadores después.

| Contenido | Estilo | Ancho |
|---|---|---|
| Historial (tramos ya recorridos) | sólido, color de su modo | 2.0 |
| Tramo activo, parte recorrida | sólido, color de su modo | 4.0 |
| Tramo activo, parte pendiente | `StrokePattern.dashed(segments: [12, 8])`, color de su modo | 4.0 |
| Rutas candidatas (solo en ciudad y sin trayecto elegido) | sólido, gris α 0.35 | 2.0 |

Marcadores: el de Phoebe (el actual) más el origen y el destino del tramo activo. Desaparecen los marcadores de las seis ciudades de `mockFoggRoute`.

---

## 4. Plan de implementación

1. **Crea `RoutePath` — `lib/domain/models/route_path.dart`** — geometría, distancia acumulada, `positionAt` y `renderSegments`. Prueba: `flutter analyze`.
2. **Crea `test/domain/route_path_test.dart` (TDD)** — interpolación en los extremos y en el punto medio, monotonía, ruta de 2 vértices, ruta con salto del antimeridiano (dos segmentos, ninguno con `+180` y `−180` a la vez), longitud normalizada a `[-180, 180)`. Ejecutar `flutter test test/domain/route_path_test.dart`.
3. **Crea `CityCatalog` — `lib/services/city_catalog.dart`** — carga `locations.json` y resuelve por nombre. Prueba: `flutter analyze`.
4. **Crea `test/services/city_catalog_test.dart`** — carga el asset real con `rootBundle` (en `flutter test` los assets declarados en `pubspec.yaml` están disponibles; si el binding no los expone, se usa un `AssetBundle` fake con el JSON embebido), nombre con y sin acentos, nombre inexistente → `null`. Ejecutar `flutter test test/services/city_catalog_test.dart`.
5. **Añade `route` a `VehicleOption` y `path` a `FoggLeg`** — campos opcionales, constructores `const` intactos. Prueba: `flutter analyze`.
6. **Integra en `TransportSelector` — `lib/services/transport_selector.dart`** — el vehículo conserva su `RouteEntry` (`bestByMode[mode]`), y el destino se resuelve con `CityCatalog` (coordenadas y `timezone` IANA reales) en lugar del vértice final y `'UTC'`. Prueba: `flutter test test/services/transport_selector_test.dart`.
7. **Integra en `GameSession` — `lib/services/game_session.dart`** — `startLeg` construye la `RoutePath` del tramo, `tick()` añade el tramo a `completedLegs` y actualiza `_currentCity`. Prueba: `flutter test test/services/game_session_test.dart`.
8. **Crea `cityCatalogProvider` — `lib/presentation/providers/route_catalog_provider.dart`** — `FutureProvider<CityCatalog>` con `rootBundle`; `transportSelectorProvider` lo inyecta en el `TransportSelector`. Prueba: `flutter analyze`.
9. **Convierte `foggPositionProvider` en derivado — `lib/presentation/providers/fogg_position_provider.dart`** — `Provider<LatLng?>` según §3.6. Actualiza `test/presentation/fogg_position_provider_test.dart` (dejó de ser un `StateProvider` escribible). Ejecutar `flutter test test/presentation/fogg_position_provider_test.dart`.
10. **Arranca el reloj — `lib/presentation/providers/game_notifier.dart`** — suscripción a `TimeEngine.clock()` con `ref.onDispose`. Añade un test que verifique que la partida llega sola a `FoggArrived` sin pulsar nada. Ejecutar `flutter test test/services/game_session_test.dart test/presentation/`.
11. **Añade la paleta — `lib/utils/app_colors.dart`** — tokens de ruta. Prueba: `flutter analyze`.
12. **Redibuja el mapa — `lib/presentation/widgets/world_map_widget.dart`** — `PolylineLayer` con historial + tramo activo (sólido y discontinuo) + candidatas; `MarkerLayer` con Phoebe, origen y destino. Consume `gameNotifierProvider`, `foggPositionProvider` y `cityCatalogProvider`. Prueba: `flutter analyze`.
13. **Quita la ruta fija — `lib/presentation/pages/map_tab.dart`** — `WorldMapWidget` sin `route: mockFoggRoute`. Prueba: `flutter analyze`.
14. **Reescribe `test/widgets/world_map_widget_test.dart`** — los asserts actuales cuentan las polylines y marcadores de `mockFoggRoute`; se sustituyen por los del trayecto activo (con un `GameSession` fake) y se conservan las aserciones de invariantes: orden de capas, `replicatesWorldLongitude == false`, `drawInSingleWorld == true` y la constraint `ContainCamera`. Ejecutar `flutter test test/widgets/world_map_widget_test.dart`.
15. **Ejecuta `flutter analyze` y `flutter test`** — objetivo: 0 errores nuevos y todos los tests verdes (el lint `info` preexistente de `test/services/sun_terminator_service_test.dart:291` se mantiene).

---

## 5. Criterios de aceptación

- [ ] `VehicleOption` conserva la `RouteEntry` de la ruta elegida y `FoggLeg` conserva su `RoutePath`.
- [ ] `RoutePath.positionAt(0)` es el origen y `positionAt(1)` es el destino del tramo.
- [ ] La posición interpolada es monótona: avanzar el `progress` nunca retrocede sobre la geometría.
- [ ] La longitud devuelta por `positionAt` está normalizada al intervalo `[-180, 180)`.
- [ ] `RoutePath.renderSegments()` devuelve más de un segmento cuando la geometría cruza el antimeridiano.
- [ ] Ninguna polilínea individual contiene a la vez `+180` y `−180`.
- [ ] Ninguna polilínea individual contiene un salto de longitud mayor de 180° entre vértices consecutivos.
- [ ] `CityCatalog.byName` resuelve las 304 ciudades de `locations.json` con su `timezone` IANA.
- [ ] `DestinationOption.city.timezone` es el IANA real de la ciudad, no `'UTC'`.
- [ ] La partida llega sola a `FoggArrived` sin intervención manual (el reloj llama a `tick()`).
- [ ] `foggPositionProvider` devuelve la posición interpolada mientras se viaja y la ciudad al llegar.
- [ ] El mapa dibuja el trayecto activo con la geometría real del catálogo, no una recta entre ciudades.
- [ ] La parte recorrida del trayecto se dibuja sólida y la pendiente discontinua, ambas en el color del modo.
- [ ] El historial de tramos recorridos permanece visible en el mapa con el color de su modo.
- [ ] Las rutas candidatas solo se dibujan en gris cuando Phoebe está en una ciudad y no ha elegido trayecto.
- [ ] `mockFoggRoute` no se dibuja en el mapa.
- [ ] El marcador de Phoebe se sitúa sobre la geometría del trayecto y se mueve al avanzar el reloj.
- [ ] Se conservan los invariantes del mapa: `replicatesWorldLongitude == false`, `drawInSingleWorld == true` y constraint `ContainCamera`.
- [ ] Se conserva el orden de capas asertado: `TileLayer` → `PolygonLayer` → `PolylineLayer` → marcadores.
- [ ] El overlay nocturno sigue entre los tiles y las rutas.
- [ ] `flutter analyze` sin errores nuevos.
- [ ] `flutter test` pasa con todos los tests verdes.
- [ ] No se modifican `assets/data/*.json`, `tools/` ni las skills.

---

## 6. Decisiones tomadas y descartadas

- **Sí:** llevar la geometría en `VehicleOption` y en `FoggLeg`. Por qué: sin el `RouteEntry` en el vehículo, el tramo no sabe qué línea recorre; y sin la `RoutePath` en el tramo, el mapa no puede interpolar.
- **No:** un repositorio global de rutas activas. Por qué: el tramo en curso es el único contexto necesario; un registro global introduce estado compartido sin consumidor.
- **Sí:** interpolar por distancia Haversine acumulada, no por índice de vértice. Por qué: la densidad de vértices es irregular (una ruta de 574 vértices concentra media en los curvature); el reparto por índice daría saltos de velocidad.
- **No:** repartir el tiempo entre vértices por índice. Por qué: mismo motivo.
- **Sí:** desenrollar con arco más corto (`Δlng` normalizado a ±180°) para las geometrías del catálogo. Por qué: son trayectorias continuas, no la Regla del Este de `FoggRoute`; el arco más corto es el recorrido real.
- **No:** reutilizar `FoggRoute.polylineSegments` (`lib/domain/entities/fogg_route.dart:55`). Por qué: su desenrollado es *hacia el Este* (obligatorio por la Regla del Este: Tokio → Savile Row son 220° al este, no 140° al oeste) y su semántica es distinta. Se implementa aparte en `RoutePath` para no tocar un archivo con asserts de dominio.
- **Sí:** mantener `Epsg3857NoRepeat` y `drawInSingleWorld: true`. Por qué: son invariantes vigilados por test; volver al CRS por defecto reintroduce el bug de envoltura infinita del antimeridiano.
- **Sí:** cortar la polilínea en el meridiano en vez de normalizar el CRS. Por qué: el corte es local y reversible; cambiar el CRS afecta a tiles, cámara y terminador solar.
- **Sí:** dibujar la geometría completa, sin decimar. Por qué: ya viene simplificada con Douglas-Peucker en la generación de las skills; decimar en memoria obligaría a mantener dos representaciones distintas (una para dibujar, otra para interpolar).
- **Sí:** el reloj en `GameNotifier`, reutilizando `TimeEngine.clock()`. Por qué: ese `Stream` ya tiene el guardarraíl de `flutter test`; escribir un `Timer.periodic` propio rompería la suite.
- **Sí:** en release la escala se clampa a 1.0 (80 días reales) y en debug sigue a 60. Por qué: es el comportamiento ya implementado en `TimeEngine._clampScale`; la spec no lo cambia.
- **Sí:** sin seguimiento automático de cámara. Por qué: en Mercator, un auto-follow roba el control y produce tirones; el botón «Centrar en Phoebe» ya existe y resuelve el caso.
- **Sí:** color de la ruta = color del modo, con lo recorrido sólido y lo pendiente discontinuo. Por qué: distingue visualmente el progreso sin inventar un cuarto color y reutiliza la paleta del visor dev.
- **No:** tramo recorrido en rojo Fogg (`#C0392B`). Por qué: el color del modo ya identifica el medio de transporte; el rojo queda reservado al marcador de Phoebe.
- **Sí:** el historial permanece en el mapa, en el color de su modo y a 2 px. Por qué: el viaje acumulado es parte de la lectura del mapa, no ruido.
- **Sí:** las candidatas en gris, solo en ciudad y sin trayecto elegido. Por qué: sirven para elegir; una vez en ruta, son ruido.
- **Sí:** el tren usa `#6A1B9A`. Por qué: es el valor real del visor dev (`tools/locations-map/app.js:98`); el `#8E24AA` anotado en la conversación era aproximado.
- **Sí:** cargar `locations.json` en esta spec. Por qué: sin el `timezone` IANA real, las salidas por hora local son incorrectas y el punto de partida del tramo puede no ser la ciudad que cree el jugador.
- **No:** persistir la partida, el historial ni la posición. Por qué: la persistencia es spec propia (`InMemoryBackend` + Hive) y esta entrega es ya grande.
- **No:** animación de la ruta (cabeza, pulso, flechas). Por qué: es adorno; el valor está en ver el trazado real y el marcador encima.

---

## 7. Riesgos

| Riesgo | Mitigación |
|---|---|
| La geometría del catálogo cruza el antimeridiano y se dibuja una línea horizontal parasite | `renderSegments()` corta en el meridiano; test que verifica que ninguna polilínea contiene `+180` y `−180` a la vez, ni saltos >180° |
| El mapa queda en blanco al llegar a una ciudad sin ruta real | `RoutePath.straight` garantiza un tramo dibujable; `positionAt` cae al vértice de origen si la ruta es degenerada |
| `Timer.periodic` pendiente en `flutter test` | Se reutiliza `TimeEngine.clock()`, que ya corta el `Stream.periodic` bajo `TestWidgetsFlutterBinding` |
| Regresión en el terminador solar al reordenar capas | El orden `TileLayer → PolygonLayer → PolylineLayer → marcadores` se mantiene y sigue asertado en el test del widget |
| El polilínea activa tiene cientos de vértices y ralentiza el repintado | La geometría ya viene simplificada; `PolylineLayer` no reproyecta por vértice en cada frame. Si el FPS cae, la decimación queda para una spec posterior |
| El reloj del juego consume batería en segundo plano | El `Notifier` se suscribe al reloj mientras está observado; `ref.onDispose` cancela la suscripción |
| `locations.json` y las rutas se desincronizan (una ciudad que no está en el catálogo) | `CityCatalog.byName` devuelve `null` y el selector cae a la ciudad derivada de la geometría, como hoy |

---

## 8. Lo que **no** está en esta especificación

- Seguimiento automático de cámara.
- Persistencia de la partida, del historial y de la posición.
- Animación de la ruta (cabeza, pulso, flechas).
- Decimación de la geometría en memoria.
- Rutas candidatas visibles mientras Phoebe está en ruta.
- Diario de Phoebe y `StoryGenerator`.
- `InMemoryBackend`, caché Hive y sincronización.
- PWA instalable y design tokens del resto de la interfaz.

Cada uno de ellos, si aterriza, irá en su propia especificación.

---

## 9. Referencias

- `lib/presentation/pages/map_tab.dart:19` — `route: mockFoggRoute` (la ruta que se elimina del mapa).
- `lib/presentation/widgets/world_map_widget.dart:222` — lectura de `foggPositionProvider`.
- `lib/presentation/widgets/world_map_widget.dart:301` — `PolylineLayer` con `widget.route.polylineSegments` (la línea que se sustituye).
- `lib/presentation/providers/fogg_position_provider.dart:6` — `StateProvider` con Londres constante (la que se hace derivada).
- `lib/presentation/providers/game_notifier.dart:33` — `GameNotifier.build`, donde se engancha el reloj.
- `lib/services/game_session.dart:150` — `GameSession.tick()`, hasta ahora sin llamante en la app.
- `lib/services/transport_selector.dart:82` — `_buildOption`, donde hoy se descarta la `RouteEntry`.
- `lib/domain/entities/fogg_route.dart:55` — `polylineSegments`, referencia técnica del corte en el meridiano.
- `lib/domain/models/route_entry.dart` — `RouteEntry.geometry` (`[lng, lat]`).
- `lib/services/route_catalog.dart:52` — lectura de la geometría del catálogo.
- `lib/services/time_engine.dart` — `clock()` con el guardarraíl de tests.
- `assets/data/locations.json` — 304 ciudades con `timezone` IANA (GeoNames, CC-BY 4.0).
- `tools/locations-map/app.js:68,78,98` — paleta del visor dev: coche `#F9A825`, barco `#1E88E5`, tren `#6A1B9A`.
- `flutter_map` 8.3.2 — `Polyline.pattern` / `StrokePattern.dashed(segments: [...])`.

---

## 10. Preguntas abiertas (resueltas)

- ¿El reloj del juego entra en esta spec? → Sí: sin `tick()` la partida no avanza y el marcador no se mueve.
- ¿Dónde vive la geometría? → En `VehicleOption.route` y en `FoggLeg.path`.
- ¿Se carga `locations.json`? → Sí, para resolver la ciudad real con su `timezone` IANA.
- ¿Qué pasa con `mockFoggRoute`? → Se elimina del mapa.
- ¿Cómo se interpola? → Por distancia Haversine acumulada.
- ¿Cómo se dibuja el trayecto? → Color del modo; recorrido sólido, pendiente discontinuo.
- ¿Qué marcadores quedan? → Phoebe, origen y destino del tramo activo.
- ¿Se simplifica la geometría? → No, se dibuja completa.
- ¿Y el antimeridiano? → Se corta la polilínea y se mantiene `Epsg3857NoRepeat`.
- ¿Y las candidatas? → En gris, solo en ciudad y sin trayecto elegido.
- ¿Y el historial? → Permanece en el mapa, en el color de su modo.
- ¿La cámara sigue a Phoebe? → No; botón «Centrar en Phoebe».
- ¿Qué cadencia? → `timeScale` 60 en debug, 1.0 en release.

---

**Número:** 016. **Slug:** ruta-viva-movimiento-phoebe.
