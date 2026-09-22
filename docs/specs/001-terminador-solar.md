# SPEC 001 — Capa visual día/noche (terminador solar)

> **Estado:** Aprobado — rama `spec-01-world-map-fogg`  
> **Autor:** OpenCode (Muse Spark) a petición del Señor  
> **Fecha:** 2026-09-22  
> **Relacionado:** `TODO.md:12` (overlay simplificado MVP) y `TODO.md:29` (overlay curvo preciso v1), `lib/presentation/widgets/world_map_widget.dart`, `pubspec.yaml`

---

## 1. Resumen

Implementar la capa visual del **terminador solar** (línea día/noche) sobre `flutter_map`, replicando el mapamundi físico del domicilio del Señor: hemisferio nocturno oscurecido (superior y laterales) y hemisferio diurno claro (centro e inferior).

Se usará `apsl_sun_calc` (sustituto mantenido de `suncalc` abandonado) como fuente de constantes solares, un servicio puro `SunTerminatorService` que genera el polígono del hemisferio nocturno, un `PolygonLayer` semi-transparente insertado entre `TileLayer` y `PolylineLayer`, y recálculo periódico cada **5 minutos**.

La spec cierra el hueco entre el MVP simplificado y el v1 curvo preciso sin romper invariantes (Regla del Este, Sin avión, `Epsg3857NoRepeat`, `foggPosition`).

---

## 2. Contexto y motivación

* **Referencia física:** imagen del domicilio con silueta noche/día curva — noche en polo norte y bordes este/oeste, día ecuatorial. El mapa actual `WorldMapWidget` muestra tiles OSM sin sombreado.
* **Oportunidad narrativa:** el Ciclo Fogg `06:00 carta → 07:00 elección → 08:00-22:00 avance → 22:00 descanso` depende de luz solar local (`localTime = utc + lng/15`). Visualizar el terminador comunica de un vistazo si Phoebe avanza de día o si `sleeper` (train/ship) le permite avanzar de noche.
* **Deuda técnica:** `TODO.md:12` pide overlay simplificado, `TODO.md:29` overlay curvo. Esta spec los unifica: entrega curva precisa desde el inicio con coste despreciable (≈181 vértices).

---

## 3. Objetivo / No-objetivo

### Objetivo
* Dependencia `apsl_sun_calc` en `pubspec.yaml`.
* `SunTerminatorService` puro con `DateTime.now().toUtc()` → `List<LatLng>` polígono noche en `[-180,180]`.
* `PolygonLayer` con `Color(0xFF000511).withOpacity(0.45)` entre `TileLayer` y `PolylineLayer`/`MarkerLayer`.
* Recálculo cada 5 minutos vía `ValueNotifier`/`StreamProvider` + `Timer`.

### No-objetivo (fuera de esta spec)
* Simulación lumínica por tile ni shaders.
* Toggle día/noche animado ni control de opacidad por usuario (se deja como *follow-up* en `MapControlsOverlay`).
* Integración con `TimeEngine` `TIME_SCALE` — se prevé compatibilidad pero no se implementa aún (el engine aún no existe en `spec-01-world-map-fogg`).
* Persistencia Hive ni `StoryGenerator`.

---

## 4. Requisitos

### 4.1 Funcionales
* RF1 — Dado `utc = DateTime.now().toUtc()`, el sistema calcula el **punto subsolar** `(subLat, subLng)`: `subLat = declinación solar`, `subLng = longitud donde el sol está en el cenit`.
* RF2 — El sistema genera el **polígono nocturno** como hemisferio opuesto al subsolar: todo punto con distancia angular >90° del subsolar es noche.
* RF3 — El polígono se renderiza como `PolygonLayer` semi-transparente `#000511`, `alpha 0.45` (tokens intercambiable), por debajo de ruta y marcadores para no ocluir la línea roja `#C0392B`.
* RF4 — El polígono se recalcula cada 5 minutos sin intervención del usuario y sin fuga de `Timer` al `dispose`.
* RF5 — En cualquier `zoom 2..18` y con `Epsg3857NoRepeat` el sombreado no se replica ni produce salto antimeridiano.

### 4.2 Técnicos
* RT1 — `pubspec.yaml:30` añade `apsl_sun_calc: ^2.1.0` (verificar última en pub.dev; `^1.0.0` si 1.x vigente). `flutter pub get` verde.
* RT2 — `lib/services/sun_terminator_service.dart` — clase sin `BuildContext`, testeable, con API:
  ```dart
  class SunTerminatorService {
    /// Punto subsolar para [utc] (utc.isUtc == true).
    static LatLng subsolarPoint(DateTime utc);

    /// Polígono cerrado del hemisferio nocturno.
    /// [stepLng] separación en longitud (recomendado 2.0°).
    /// [twilight] ángulo bajo horizonte: 0 geométrico, -0.833 refracción, -6 civil.
    static List<LatLng> nightPolygon(
      DateTime utc, {
      double stepLng = 2.0,
      double twilight = 0.0,
    });

    /// Helper interno: declinación y GMST — delega constantes a apsl_sun_calc si expone.
    static double _solarDeclination(DateTime utc);
  }
  ```
* RT3 — `lib/presentation/providers/sun_terminator_provider.dart` — Riverpod:
  ```dart
  final currentUtcProvider = StreamProvider<DateTime>((ref) {
    return Stream.periodic(const Duration(minutes: 5), (_) => DateTime.now().toUtc())
        .startWith(DateTime.now().toUtc());
  });
  final sunTerminatorProvider = Provider<List<LatLng>>((ref) {
    final utc = ref.watch(currentUtcProvider).value ?? DateTime.now().toUtc();
    return SunTerminatorService.nightPolygon(utc);
  });
  ```
  Alternativa válida: `StateProvider` + `Timer.periodic` en `WorldMapWidget.initState` si se prefiere evitar `StreamProvider`. La spec fija **Riverpod** por testeabilidad y futura migración a `TimeEngine`.
* RT4 — `lib/presentation/widgets/world_map_widget.dart:240` orden de capas:
  ```
  0 TileLayer
  1 PolygonLayer (noche)   ← nuevo
  2 PolylineLayer (ruta)
  3 MarkerLayer (ciudades)
  4 MarkerLayer (Phoebe)
  5 Attribution
  ```
* RT5 — Color desacoplado: `lib/utils/app_colors.dart` o `tokens.json → ThemeData` con `nightOverlay = Color(0xFF000511).withValues(alpha:0.45)`.
* RT6 — `Package by Layer` respetado: `domain/` no importa `services/`; `presentation/` consume `services/` vía provider (DIP).

---

## 5. Diseño detallado

### 5.1 Algoritmo subsolar (precisión NOAA, envuelto por `apsl_sun_calc`)

`apsl_sun_calc` expone `getSunPosition` pero no subsolar directo; se implementa fórmula NOAA y se usa la lib solo para constantes/validación cruzada.

```
n  = daysSinceJ2000(utc)          // J2000 = 2000-01-01 12:00 UTC
L  = (280.460 + 0.9856474*n) % 360
g  = (357.528 + 0.9856003*n) % 360  // anomalía media
lambda = L + 1.915*sin(g) + 0.020*sin(2*g)   // longitud eclíptica
epsilon = 23.439 - 0.0000004*n               // oblicuidad
alpha = atan2(cos(epsilon)*sin(lambda), cos(lambda)) // ascensión recta
decl  = asin(sin(epsilon)*sin(lambda))       // declinación → subLat
GMST  = (280.46061837 + 360.98564736629*n) % 360 // tiempo sidéreo Greenwich
subLng = - (GMST + alpha*180/pi)  → normalizar a [-180,180]
subLat = decl*180/pi
```

Referencia: NOAA Solar Calculator, validado contra `apsl_sun_calc` en tests (tolerancia <0.2°).

### 5.2 Curva terminador

Para cada `lng ∈ [-180,180]` paso `stepLng=2°` (181 pts):

```
hourAngle H = lng - subLng  (rad)
latTerm = atan( -cos(H) / tan(subLatRad) )   // con twilight: atan((sin(twilight)-sin subLat sin lat)/cos subLat cos lat) iterativo simplificado a +twilight
clamp latTerm a [-90,90]
si |subLat| < 0.5° → terminador vertical en subLng ±90° (equinoccio)
```

*Justificación:* en la esfera, el terminador es el círculo máximo a 90° del subsolar. La fórmula anterior es la intersección del meridiano `lng` con ese círculo máximo. Coste O(181), despreciable.

### 5.3 Cierre del polígono nocturno

El terminador solo es una línea; para sombrear el hemisferio nocturno se cierra por el polo nocturno:

```
poleLat = subLat > 0 ? -90 : 90   // verano boreal → polo sur de noche
nightPolygon = terminatorPoints (ordenados -180→180)
               + [LatLng(poleLat, 180), LatLng(poleLat, -180)]
```
*Invariante:* `distance(subsolar, poleLat) > 90°` siempre. Test incluye `subsolar` fuera del polígono y polo nocturno dentro. Con `Epsg3857NoRepeat` un solo polígono basta; no partir en dos segmentos como `FoggRoute.polylineSegments` (aunque se documenta alternativa de dos polígonos si `flutter_map` cull detecta cruce).

### 5.4 Integración `flutter_map` 8.x

```dart
// lib/presentation/widgets/world_map_widget.dart
final nightPoints = ref.watch(sunTerminatorProvider);

FlutterMap(
  options: MapOptions(
    crs: const Epsg3857NoRepeat(), // lib/presentation/widgets/world_map_widget.dart:61
    cameraConstraint: _ContainWithFallback(_worldBounds),
    backgroundColor: _offlineBg,
  ),
  children: [
    TileLayer(urlTemplate: _mapTileUrl, ...),
    PolygonLayer(
      polygons: [
        Polygon(
          points: nightPoints,
          color: const Color(0xFF000511).withValues(alpha: 0.45),
          borderColor: Colors.transparent,
          borderStrokeWidth: 0,
          isDotted: false,
          label: 'night',
        ),
      ],
    ),
    PolylineLayer(polylines: widget.route.polylineSegments.map(...).toList(), drawInSingleWorld: true),
    MarkerLayer(markers: cityMarkers),
    if (effectiveFoggPos != null) MarkerLayer(markers: phoebeMarker),
    RichAttributionWidget(...),
  ],
)
```

*Nota:* `drawInSingleWorld` no aplica a `PolygonLayer`; con `replicatesWorldLongitude==false` el polígono no se replica.

### 5.5 Actualización 5 minutos

* `StreamProvider` emite `nowUtc` cada 5 min; `sunTerminatorProvider` deriva `nightPolygon`. `WorldMapWidget` es `ConsumerStatefulWidget` — `ref.watch(sunTerminatorProvider)` dispara rebuild solo del `PolygonLayer` (optimizable con `Consumer` parcial).
* `Timer` cancelado en `ref.onDispose` / `dispose`. No usar `ValueNotifier<DateTime>` global hasta que `TimeEngine` exista; dejar puerta abierta: `currentUtcProvider` será reemplazado por `timeEngineProvider` cuando `TIME_SCALE` esté disponible.

---

## 6. Estructura de archivos

```
pubspec.yaml                          // + apsl_sun_calc
lib/
  services/
    sun_terminator_service.dart       // nuevo — puro Dart
  presentation/
    providers/
      sun_terminator_provider.dart    // nuevo — Riverpod
    widgets/
      world_map_widget.dart           // modificado — inserta PolygonLayer
      map_controls.dart               // opcional: toggle noche/día futuro
  utils/
    app_colors.dart                   // nuevo o tokens.json — nightOverlay
test/
  services/
    sun_terminator_service_test.dart  // nuevo — subsolar + polígono
  widgets/
    world_map_terminator_test.dart    // nuevo — widget + orden capas
  presentation/
    fogg_position_provider_test.dart  // existente, sin tocar
```

---

## 7. Alternativas consideradas

| Alternativa | Descartada por |
|---|---|
| `suncalc` / `suncalc2` | Sin mantenimiento, `apsl_sun_calc` es fork activo y null-safe |
| Fórmula manual sin lib | Válida pero pierde validación cruzada; se mantiene como fallback envuelto |
| Paso 5° / 1° | 5° ahorra 60% vértices pero curva visiblemente quebrada en zoom alto; 1° duplica vértices sin ganancia perceptible. 2° es compromiso |
| `ValueNotifier<DateTime>` global manual | Más imperativo, menos testeable que `StreamProvider`; se documenta como alternativa si `TimeEngine` exige `ValueNotifier` |
| Dos polígonos partidos en antimeridiano | Innecesario con `Epsg3857NoRepeat`; se deja como plan B si culling falla |
| Twilight -6° (civil) por defecto | Más estético difuso pero no coincide con imagen física del Señor (borde duro). Se parametriza |

---

## 8. Plan de implementación (paso a paso)

1. `pubspec.yaml:30` añadir `apsl_sun_calc: ^2.1.0` (verificar `flutter pub outdated`), `flutter pub get`.
2. Crear `lib/utils/app_colors.dart` con `nightOverlay`.
3. Crear `lib/services/sun_terminator_service.dart` con `subsolarPoint` + `nightPolygon` + tests en TDD.
4. Crear `lib/presentation/providers/sun_terminator_provider.dart`.
5. Modificar `lib/presentation/widgets/world_map_widget.dart` para consumir provider e insertar `PolygonLayer`.
6. Añadir tests unitarios y widget (ver §9).
7. `flutter analyze` + `flutter test` verde; `flutter run -d chrome` verificación visual a 2026-09-22 y solsticios.
8. Actualizar `TODO.md:12` y `TODO.md:29` a `[x]` parcial y documentar en `README.md:Configuración` si `MAP_TILE_URL` afecta contraste.

---

## 9. Testing

### 9.1 Unit `sun_terminator_service_test.dart`
* `subsolarPoint` — equinoccio 2026-03-20 12:00 UTC → `subLat ≈ 0 ±0.5°`, `subLng ≈ 0 ±1°` (Greenwich al mediodía); solsticio verano 2026-06-21 → `subLat ≈ +23.44 ±0.3°`; invierno 2026-12-21 → `subLat ≈ -23.44`.
* `nightPolygon` — longitud 181 pts +2 cierre =183; `first.lng==-180`, `last.lng==-180` cierre polo; `contains(subsolar)==false`, `contains(poleNocturno)==true`, `contains(poleDiurno)==false`.
* Antimeridiano — ningún segmento interno contiene `180→-180` (mismo criterio que `FoggRoute:91`).
* Twilight — con `twilight=0` vs `-6` el polígono con `-6` es ligeramente menor (noche más pequeña).

### 9.2 Widget `world_map_terminator_test.dart`
* `PolygonLayer` existe y es segundo `children` tras `TileLayer`.
* `color == Color(0xFF000511).withValues(alpha:0.45)` y `borderStrokeWidth==0`.
* Orden: `Tile < Polygon < Polyline < Marker`.
* `sunTerminatorProvider` emite en 5 min (usar `fakeAsync`).
* No fuga `Timer` al `dispose` (verificar `ref.onDispose`).
* Con `replicatesWorldLongitude==false` el polígono no se duplica.

### 9.3 Visual manual
* 2026-09-22 12:00 UTC → noche arriba/laterales, día centro/abajo como foto domicilio.
* Zoom 2 y 18 sin artefactos ni replicación.

---

## 10. Riesgos y mitigaciones

* **R1 — `apsl_sun_calc` API cambia** → adapter `SunTerminatorService` desacopla; fallback NOAA puro.
* **R2 — Polos circumpolares** (`|subLat|≈23.44`) → terminador no llega a 90°, cierre por polo sigue válido; clamp y test de inclusión.
* **R3 — `PolygonLayer` opacidad sobre tiles OSM** → coste fill mínimo; si `flutter_map` 8.x rasteriza lento, reducir paso a 3° o cachear `nightPolygon` 5 min (ya previsto).
* **R4 — Conflicto con overlay offline ` _tileError:103`** → `PolygonLayer` debajo de `Container` offline no visible, correcto.
* **R5 — `TIME_SCALE` futuro** → `currentUtcProvider` reemplazable por `timeEngineProvider` sin tocar `WorldMapWidget`.

---

## 11. Criterios DONE

* [ ] `flutter pub get` sin conflictos, `apsl_sun_calc` en `pubspec.lock`.
* [ ] `SunTerminatorService` con cobertura ≥90% y tests verdes.
* [ ] `WorldMapWidget` muestra sombreado nocturno curvo, `flutter test` y `flutter analyze` verdes.
* [ ] Verificación visual en Chrome: equinoccio/solsticios correctos, sin salto antimeridiano, ruta roja y marcadores por encima del sombreado.
* [ ] `TODO.md` actualizado, sin secretos en repo, diff limpio.

---

## 12. Referencias

* `lib/presentation/widgets/world_map_widget.dart:61` `Epsg3857NoRepeat`
* `lib/presentation/widgets/world_map_widget.dart:240` orden `children`
* `lib/domain/entities/fogg_route.dart:13` manejo antimeridiano
* `TODO.md:12,29` overlay día/noche
* `AGENTS.md` — `Package by Layer`, `eu.elarreglador.pf`, invariantes Regla del Este y Sin avión
* NOAA Solar Calculator — fórmula declinación y GMST
* pub.dev `apsl_sun_calc` — fork mantenido de `suncalc`

---

## 13. Preguntas abiertas (resueltas por esta spec)

* Color `#000511` 45% ✅ — token `nightOverlay`
* Paso 2° ✅
* Twilight 0° geométrico ✅ (parametrizable)
* Riverpod `StreamProvider` 5 min ✅
* Rama `spec-01-world-map-fogg` existente ✅ — no crear nueva

> Siguiente paso tras aprobar esta spec: ejecutar `spec-impl` sobre esta rama (pasos §8) con TDD.

---

## 14. Fix completo 2026-09-22 (post-spec)

**Motivo:** visualización incorrecta en equinoccio (22-sep) — `|subLat|<0.5°` generaba polígono degenerado auto-intersectante y `lat ±90°` excedía Mercator (`y=∞`).

**Cambios:**

* `lib/services/sun_terminator_service.dart:63` ` _maxMercatorLat=85.05112878` + `_clampLat`; polo y terminador clamped a `85.05°`.
* `nightPolygons()` nuevo API `List<List<LatLng>>` — 1 polígono sinusoidal 183 pts (solsticio) o 2 rectángulos 4 pts split antimeridiano (equinoccio) sin salto `180→-180`. `nightPolygon()` legacy delega a `nightPolygons().first`.
* `lib/presentation/providers/sun_terminator_provider.dart:62` `sunTerminatorProvider` ahora `Provider.autoDispose<List<List<LatLng>>>` + alias `sunTerminatorLegacyProvider`.
* `lib/presentation/widgets/world_map_widget.dart:205-268` `PolygonLayer` itera `nightPolygons.map(Polygon)`.

**Verificación:** `flutter test` 62 tests verdes; `SunTerminatorService` cubre subsolar, solsticio 183 pts, equinoccio 2 rectángulos, PIP día/noche (London día, Tokyo noche, antipoda 179.9 noche), clamp 85.05.
