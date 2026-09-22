# SPEC 002 — Scaffold principal con barra superior y botonera inferior (Mapa)

> **Estado:** Aprobado

> **Depende de:** SPEC 001 (terminador solar, WorldMapWidget, Epsg3857NoRepeat, SunTerminatorService)

> **Fecha:** 2026-09-22

> **Objetivo:** Proveer el chrome navegacional base de la app (barra superior fija + botonera inferior con pestaña Mapa que embebe el WorldMapWidget existente) sin acoplar lógica de dominio.

---

## 1. Por qué existe esta especificación

`lib/main.dart:38` hoy es un `Scaffold` sin `AppBar` y con `WorldMapWidget` a pantalla completa. Para escalar el MVP (Diario, Presupuesto, Ruta) se necesita un **scaffold raíz estable** que separe navegación de contenido, prepare el terreno para `TimeEngine`/`BudgetService`/`DiaryService` y respete `Package by Layer` y `eu.elarreglador.pf`. Sin este chrome, cada feature futura reinventaría navegación o acoplaría `MaterialApp.home` a un widget de mapa no reutilizable. Esta spec cierra el hueco entre el mapa aislado (001) y las features con estado (014+).

---

## 2. Alcance

**En:**

- **Muestra la barra superior con título y subtítulo — `lib/presentation/widgets/fogg_app_bar.dart` — AppBar M3 fija arriba con título y fecha** — `AppBar(title: "80 Días — La Herencia de Phoebe", bottom: subtítulo fecha local)` con `backgroundColor: AppColors.surface` y `foregroundColor: AppColors.labelColor`
  - **Estilo:** `height 64dp`, `elevation 0`, `centerTitle true`, `title Text 16sp w600`, `subtitle 12sp w400` con `DateFormat` local (derivado de `DateTime.now()` hasta que `TimeEngine` exista)
  - **Color:** `AppColors.foggRed #C0392B` como `seedColor` ya en `ThemeData`, `AppBar` usa `surface` claro, no oculta mapa al scrollear (`scrolledUnderElevation 0`)
  - **SafeArea:** respeta `top` notch, sin acciones en MVP (trailing reservado para `BudgetBadge` futuro)

- **Muestra la botonera inferior con 4 destinos — `lib/presentation/widgets/fogg_bottom_nav.dart` — NavigationBar M3 con Mapa/Diario/Presupuesto/Ruta** — `NavigationBar(selectedIndex, onDestinationSelected)` con 4 `NavigationDestination`
  - **Destinos:** `0 Mapa (Icons.map_outlined/filled)`, `1 Diario (Icons.menu_book_outlined/filled)`, `2 Presupuesto (Icons.account_balance_wallet_outlined/filled)`, `3 Ruta (Icons.route_outlined/filled)` — labels en castellano, iconos Material outline/filled según selección
  - **Estilo:** `NavigationBar height 80dp`, `indicatorColor AppColors.foggRed.withValues(alpha:0.12)`, `backgroundColor AppColors.surface`, `labelBehavior alwaysShow`, `elevation 3`
  - **SafeArea:** envuelto en `SafeArea(bottom:true)` + `padding bottom 0` para respetar gestos sistema (◻ ○ △)

- **Envuelve el contenido en scaffold raíz con IndexedStack — `lib/presentation/pages/main_scaffold.dart` — Scaffold con AppBar + IndexedStack + NavigationBar** — `Scaffold(appBar: FoggAppBar(), body: IndexedStack(index: selected, children: [MapTab, DiaryPlaceholder, BudgetPlaceholder, RoutePlaceholder]), bottomNavigationBar: FoggBottomNav())`
  - **Estado:** `ConsumerWidget` que lee `bottomNavIndexProvider` (Riverpod) — cambio de índice dispara `HapticFeedback.lightImpact()` y `setState` vía provider, sin `setState` local
  - **Preservación:** `IndexedStack` mantiene estado de `WorldMapWidget` (zoom, controller, terminador) al cambiar de pestaña — no se reconstruye el mapa ni se pierde `MapController`
  - **Integración mapa:** `MapTab` embebe `WorldMapWidget(initialZoom: 2.0)` existente sin duplicar `TileLayer`/`PolygonLayer`; `MapControlsOverlay` mantiene `right:16 bottom:16` pero ahora con `SafeArea` externo ya cubre botonera — se añade `padding bottom NavigationBar height +16` al overlay para no quedar bajo la barra

- **Gestiona el índice seleccionado con Riverpod — `lib/presentation/providers/bottom_nav_provider.dart` — StateProvider int con índice 0 por defecto** — `final bottomNavIndexProvider = StateProvider<int>((ref) => 0);` + `final bottomNavDestinationsProvider` constante lista 4 items
  - **Validación:** `assert(index 0..3)` en setter, test que índice fuera de rango no rompe build (clamp o throw)
  - **Persistencia:** no persiste en MVP (reset a 0 al recargar) — documentado como fuera de alcance, preparado para `Hive` futuro sin cambiar API

- **Crea páginas placeholder para Diario/Presupuesto/Ruta — `lib/presentation/pages/placeholder_pages.dart` — 3 StatelessWidgets con icono + texto centrado** — `DiaryPlaceholder`, `BudgetPlaceholder`, `RoutePlaceholder` con `Center(Column(Icon, Text("Próximamente — Diario de Phoebe")))`
  - **Contenido:** `Icon size 48 color AppColors.foggRed.withValues(alpha:0.6)`, `Text 16sp w600`, `Text 13sp w400` descriptivo + `SizedBox 12` — sin lógica, sin llamadas a `DiaryService`/`BudgetService` aún
  - **Accesibilidad:** `Semantics(label: "Pestaña Diario")` por destino, `key: ValueKey("placeholder-diary")` para tests

- **Actualiza el punto de entrada para usar el scaffold — `lib/main.dart:38` — MyApp.home pasa de WorldMapWidget a MainScaffold** — `home: const MainScaffold()` reemplaza `FoggHomePage`; `FoggHomePage` se depreca o se reutiliza como `MapTab` interno (mantener compatibilidad tests widget existentes con alias)
  - **Tema:** `ThemeData` existente se mantiene (`seedColor #C0392B`, `useMaterial3 true`) — se extrae a `lib/utils/app_theme.dart` si supera 15 líneas, o se deja inline

- **Compartido:** tipografía y tokens (`lib/utils/app_colors.dart:17` `foggRed`, `labelColor`, `offlineBg`), `ThemeData` M3, `flutter_riverpod` ya en `pubspec.yaml`, sin nuevas dependencias, `Package by Layer` respetado (`presentation/` consume `domain/` futuro pero no al revés), prefijo `eu.elarreglador.pf` intacto

**Fuera del alcance (para futuras especificaciones):**

- Contenido real de Diario (DiaryService + StoryGenerator plantillas), Presupuesto (BudgetService + Ledger + gráfica) y Ruta (lista ciudades FoggRoute con selección) — solo placeholders aquí
- Persistencia del índice entre sesiones (Hive/shared_preferences) — reset a Mapa al recargar en MVP
- Navegación con `go_router` / `ShellRoute` / deep-linking `/map`, `/diary` — se deja `IndexedStack` simple; migración a router será spec dedicada sin romper API provider
- `NavigationRail` lateral para web ancho >600dp — siempre `NavigationBar` inferior en MVP (PWA `display:standalone`)
- Animaciones de transición entre pestañas (fade/slide) — cambio instantáneo + haptic en MVP
- Badge de presupuesto en `AppBar` o contador de cartas — reservado para BudgetService
- Toggle de tema victoriano/steampunk — Design Tokens intercambiables pero no implementado aquí

---

## 3. Modelo de datos

Esta especificación **no introduce entidades de dominio**. Reutiliza `FoggRoute`/`FoggCity` de SPEC 001 solo como lectura en placeholder Ruta. El único estado nuevo es de presentación (índice seleccionado).

```dart
// lib/presentation/providers/bottom_nav_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart';

/// Índice seleccionado de la botonera inferior. 0 = Mapa.
final bottomNavIndexProvider = StateProvider<int>((ref) => 0);

/// Destinos constantes — orden fijo, usado por FoggBottomNav y MainScaffold.
/// No se expone fuera de presentation.
const bottomNavDestinations = [
  (label: 'Mapa', iconOutlined: Icons.map_outlined, iconFilled: Icons.map),
  (label: 'Diario', iconOutlined: Icons.menu_book_outlined, iconFilled: Icons.menu_book),
  (label: 'Presupuesto', iconOutlined: Icons.account_balance_wallet_outlined, iconFilled: Icons.account_balance_wallet),
  (label: 'Ruta', iconOutlined: Icons.route_outlined, iconFilled: Icons.route),
];

// Ejemplo de consumo en MainScaffold:
// final selectedIndex = ref.watch(bottomNavIndexProvider);
// ref.read(bottomNavIndexProvider.notifier).state = 2; // al pulsar Presupuesto
```

Convenciones:

- Índice `0..3` inclusive. Setter valida `assert(index >=0 && index < bottomNavDestinations.length)`.
- Sin serialización en MVP. Cuando se añada `Hive`, se migrará a `StateNotifierProvider` o `AsyncNotifier` sin cambiar `bottomNavIndexProvider` externo (wrapper).
- `MainScaffold` es `ConsumerWidget` — no `StatefulWidget` con `setState` local, para testeabilidad y futura migración a `TimeEngine`/`BudgetService` vía `ref.watch`.
- `WorldMapWidget` no cambia su API (`route`, `foggPosition`, `initialZoom`); solo se embebe. `MapController` sigue `late final` en `_WorldMapWidgetState`.

Si en el futuro se necesita persistencia:

```dart
// Futuro — no implementar ahora:
// final bottomNavIndexProvider = StateNotifierProvider<BottomNavNotifier, int>(...);
// class BottomNavNotifier extends StateNotifier<int> { /* Hive read/write */ }
```

---

## 4. Plan de implementación

Cada paso deja `flutter analyze` y `flutter test` en verde y la app ejecutable en Chrome.

1. **Crea el provider de navegación** — `lib/presentation/providers/bottom_nav_provider.dart` con `bottomNavIndexProvider = StateProvider<int>((ref)=>0)` y `bottomNavDestinations` constante. Prueba manual: `flutter analyze` verde, `ref.read` en test unitario cambia 0→2.

2. **Crea la barra superior** — `lib/presentation/widgets/fogg_app_bar.dart` con `class FoggAppBar extends StatelessWidget implements PreferredSizeWidget` que retorna `AppBar(title: Text("80 Días — La Herencia de Phoebe"), ...)` M3 minimalista. Prueba: `flutter test` widget que `find.text("80 Días")` existe y `preferredSize.height == 64`.

3. **Crea la botonera inferior** — `lib/presentation/widgets/fogg_bottom_nav.dart` con `class FoggBottomNav extends ConsumerWidget` que usa `NavigationBar` M3, 4 `NavigationDestination` con iconos outline/filled, `selectedIndex: ref.watch(bottomNavIndexProvider)`, `onDestinationSelected: (i){ ref.read(...notifier).state=i; HapticFeedback.lightImpact(); }`. Prueba: tap en destino 2 cambia provider a 2.

4. **Crea placeholders** — `lib/presentation/pages/placeholder_pages.dart` con `DiaryPlaceholder`, `BudgetPlaceholder`, `RoutePlaceholder` (cada uno `Scaffold` interno sin AppBar o `Center` con `Icon+Text` y `key`). Prueba: `find.byKey(ValueKey("placeholder-diary"))` tras seleccionar índice 1.

5. **Crea el scaffold raíz con IndexedStack** — `lib/presentation/pages/main_scaffold.dart` con `class MainScaffold extends ConsumerWidget` que compone `Scaffold(appBar: FoggAppBar(), body: IndexedStack(index: selected, children: [MapTab, DiaryPlaceholder, BudgetPlaceholder, RoutePlaceholder]), bottomNavigationBar: FoggBottomNav())`. `MapTab` es wrapper que retorna `WorldMapWidget(route: mockFoggRoute, initialZoom: 2.0)` con `Padding` inferior para no quedar bajo `NavigationBar`. Prueba: `IndexedStack` index 0 muestra `WorldMapWidget`, index 1 muestra `DiaryPlaceholder`.

6. **Integra en el punto de entrada** — `lib/main.dart:38` cambia `home: const FoggHomePage()` a `home: const MainScaffold()`; mantiene `ProviderScope` y `MaterialApp` con `ThemeData` existente. Opcional: conserva `FoggHomePage` como alias `MapTab` para no romper `test/widgets/world_map_widget_test.dart` que importa `WorldMapWidget` directo. Prueba: `flutter run -d chrome` muestra AppBar arriba, mapa en pestaña 0, botonera abajo con 4 iconos; al pulsar Diario se ve placeholder.

7. **Ajusta overlay del mapa para botonera** — `lib/presentation/widgets/world_map_widget.dart:412` modifica `Positioned(right:16, bottom:16)` de `MapControlsOverlay` para que `bottom` sea `16 + kBottomNavigationBarHeight` (o `SafeArea` externo ya lo resuelve) — verifica `SafeArea(bottom:true)` en `MainScaffold` evita solape. Prueba visual: controles no quedan ocultos tras `NavigationBar` en móvil y Chrome.

8. **Añade tests y verifica** — `test/presentation/main_scaffold_test.dart` + `test/presentation/bottom_nav_provider_test.dart` + actualiza `test/widget_test.dart` si hace `find.byType(WorldMapWidget)` tras scaffold. Ejecuta `flutter analyze && flutter test` verde. Documenta en `README.md:Configuración` si `AppColors` nuevos afectan contraste (añade `surface`, `surfaceVariant` si necesario).

---

## 5. Criterios de aceptación

- [ ] `flutter analyze` y `flutter test` en verde con la nueva estructura (`bottom_nav_provider_test`, `main_scaffold_test`, `world_map_widget_test` existentes siguen pasando).
- [ ] `lib/presentation/providers/bottom_nav_provider.dart` existe y `StateProvider<int>` inicia en `0` (Mapa).
- [ ] `lib/presentation/widgets/fogg_app_bar.dart` renderiza `AppBar` con `find.text("80 Días — La Herencia de Phoebe")` y `preferredSize.height == 64`, sin `elevation`, centrado.
- [ ] `lib/presentation/widgets/fogg_bottom_nav.dart` es `NavigationBar` M3 con 4 `NavigationDestination` (Mapa, Diario, Presupuesto, Ruta) con iconos `map/menu_book/account_balance_wallet/route` (outline vs filled según selección).
- [ ] Al pulsar cada destino de la botonera, `bottomNavIndexProvider` cambia a `0..3` correspondiente y `IndexedStack` muestra el hijo correcto (Mapa muestra `WorldMapWidget`, otros muestran placeholder con `key` específica).
- [ ] Tapping produce `HapticFeedback.lightImpact()` (verificable vía mock o al menos no lanza excepción).
- [ ] `lib/presentation/pages/main_scaffold.dart` usa `IndexedStack` — al cambiar de pestaña y volver a Mapa, el estado del mapa (zoom, `MapController`, `nightPolygons`) se preserva (no se reconstruye `WorldMapWidget` desde cero).
- [ ] `WorldMapWidget` sigue mostrando `TileLayer` OSM + `PolygonLayer` noche (`AppColors.nightOverlay`) + `PolylineLayer` roja `#C0392B` por encima del overlay, sin regresión visual (test `world_map_terminator_test.dart` sigue verde).
- [ ] `MapControlsOverlay` no queda oculto tras `NavigationBar`: en `MediaQuery` con `SafeArea(bottom:true)` los controles son visibles y clicables (verificación manual Chrome + test `find.byType(MapControlsOverlay)`).
- [ ] `lib/main.dart` tiene `home: MainScaffold` y `FoggHomePage` no es `home` directo (si se conserva, alias funciona y no duplica `Scaffold` anidado con doble `AppBar`).
- [ ] Placeholders `DiaryPlaceholder`/`BudgetPlaceholder`/`RoutePlaceholder` muestran `Icon` + texto "Próximamente" y tienen `Semantics`/`key` para tests; no importan `domain/` ni `services/` (Package by Layer intacto).
- [ ] `SafeArea` respeta notch y gestos sistema (◻ ○ △) tanto en `AppBar` top como `NavigationBar` bottom — verificación visual en Chrome móvil (DevTools 412x915) sin solape.
- [ ] No se añaden nuevas dependencias en `pubspec.yaml`; se reutiliza `flutter_riverpod` existente; `eu.elarreglador.pf` y `AppColors` desacoplados.
- [ ] `TODO.md` no se modifica en esta spec salvo que se decida marcar scaffold como `[x]` en spec-impl — sin secretos en repo, diff limpio.

---

## 6. Decisiones tomadas y descartadas

- **Sí:** `NavigationBar` M3 (Material 3) con 4 destinos. Por qué: M3 es el estándar actual de Flutter, `NavigationBar` reemplaza `BottomNavigationBar` legacy, respeta `ThemeData(useMaterial3:true)` ya activo y permite `indicatorColor` con `foggRed` 12% alpha. No: `BottomNavigationBar` legacy — descartado por deprecación visual y no usar `indicator`.
- **Sí:** 4 destinos (Mapa, Diario, Presupuesto, Ruta). Por qué: cubre MVP futuro (Diario/Presupuesto son TODOs explícitos, Ruta expone `FoggRoute` 6 ciudades) sin llegar al límite 5 que recarga cognitiva. No: 3 destinos (Mapa+Diario+Presupuesto) — descartado porque Ruta es valor inmediato y sin ella el placeholder "Ajustes" sería genérico sin dominio. No: 5 destinos — descartado por espacio y por introducir "Perfil" sin spec de auth.
- **Sí:** `IndexedStack` + `StateProvider<int>` (Riverpod). Por qué: preserva estado del mapa, testeable, sin router; migración a `go_router`/`ShellRoute` será spec dedicada. No: `GoRouter`/`ShellRoute` ahora — sobrediseño para MVP sin deep-linking, añade dependencia y complejidad de `BuildContext` innecesaria. No: `setState` local en `MainScaffold` — descartado por no ser testeable vía `ProviderContainer` y acoplar estado a widget.
- **Sí:** `FoggAppBar` como `PreferredSizeWidget` separado (`lib/presentation/widgets/fogg_app_bar.dart`). Por qué: Single Responsibility, testeable aislado, intercambiable a victoriano sin tocar `MainScaffold`. No: `AppBar` inline en `MainScaffold` — descartado por mezclar responsabilidades y dificultar test de barra sola.
- **Sí:** Placeholders `StatelessWidget` sin lógica (solo `Icon+Text`). Por qué: KISS/YAGNI — no anticipar `DiaryService`/`BudgetService` antes de sus specs; placeholders con `key` permiten tests de navegación sin mock. No: implementar `DiaryPage` real con `DiaryService` mock — descartado porque pertenece a spec 00X de Diario, no a scaffold.
- **Sí:** Reset a índice 0 al recargar (sin persistencia Hive). Por qué: MVP simple, evita migrar a `StateNotifier` + `Hive` box solo para índice; se documenta y se deja puerta abierta. No: persistir con `Hive`/`SharedPreferences` ahora — descartado por añadir I/O asíncrono y `AsyncValue` al provider sin beneficio inmediato.
- **Sí:** `SafeArea(bottom:true)` + `NavigationBar` siempre inferior (no `NavigationRail`). Por qué: PWA `display:standalone` en móvil prioriza gesto inferior; `NavigationRail` lateral complicaría responsive sin spec de breakpoint. No: `LayoutBuilder` con `NavigationRail` >600dp — descartado para MVP, se añadirá si usuario pide web desktop dedicada.
- **Sí:** `HapticFeedback.lightImpact()` al cambiar pestaña. Por qué: feedback táctil coherente con `map_controls.dart:197` y `WorldMapWidget:197`. No: sin haptic — descartado por inconsistencia con controles de mapa existentes.
- **Sí:** Definición rápida sin aclaración detallada exhaustiva (usuario dijo "adelante"). Registrado aquí como decisión: se aceptaron recomendaciones de Fase 2 para no bloquear entrega MVP. Alternativa de preguntas adicionales queda pospuesta.

---

## 7. Riesgos identificados

| Riesgo | Mitigación |
| --- | --- |
| `IndexedStack` mantiene 4 subtrees en memoria — `WorldMapWidget` con `TileLayer` + `PolygonLayer` (183 vértices) podría retener tiles innecesarios en pestañas no visibles | `IndexedStack` es coste despreciable para 4 hijos; `WorldMapWidget` ya usa `Epsg3857NoRepeat` y tiles OSM con cache http; si `flutter_map` retiene memoria, se puede envolver placeholders en `Visibility(maintainState:false)` futuro sin cambiar API |
| `MapControlsOverlay` queda oculto tras `NavigationBar` en pantallas pequeñas | `MainScaffold` envuelve `NavigationBar` en `SafeArea(bottom:true)` y `WorldMapWidget` ajusta `bottom: 16 + NavigationBar.height` (80dp) + `SafeArea`; test visual en Chrome 412x915 y `MediaQuery.padding.bottom` verificado |
| Doble `Scaffold` si `WorldMapWidget` interno ya tiene `Scaffold` o si `Placeholder` usa `Scaffold` anidado | `WorldMapWidget` nunca tuvo `Scaffold` (solo `FlutterMap` + `Stack`) — se mantiene así; `Placeholder` usa `Center` sin `Scaffold` anidado; `MainScaffold` es único `Scaffold` raíz |
| `bottomNavIndexProvider` fuera de rango (p.ej. 4 tras añadir destino) rompe `IndexedStack` | Setter con `assert(index < bottomNavDestinations.length)` + test unitario `expect(() => notifier.state=99, throwsAssertionError)`; en release clamp `index.clamp(0,3)` como fallback |
| Regresión `world_map_widget_test.dart` que espera `WorldMapWidget` como `home` directo | Actualizar `test/widget_test.dart` para buscar `MainScaffold` → `WorldMapWidget` vía `find.descendant`; mantener `WorldMapWidget` testeable aislado sin `MainScaffold` (no acoplar tests de mapa a scaffold) |
| `AppBar` tapa parte del mapa en zoom 2 (menos terreno visible) | `AppBar` es 64dp fijo, no `SliverAppBar`; mapa usa `LayoutBuilder` con `constraints.maxHeight` — altura disponible se recalcula automáticamente; verificación visual que ruta 6 ciudades sigue visible en zoom 2 |

---

## 8. Lo que **no** está en esta especificación

- Contenido funcional de Diario, Presupuesto con `Ledger` y gráfica, y Ruta con lista `FoggRoute` interactiva — solo placeholders centrados.
- Persistencia del índice seleccionado entre sesiones (Hive/SharedPreferences).
- Navegación con `go_router`, `ShellRoute`, rutas nombradas `/map`, `/diary`, deep-linking o `Navigator 2.0`.
- `NavigationRail` lateral para web ancho, animaciones entre pestañas, badges, contadores o indicadores de progreso.
- Tema victoriano/steampunk intercambiable — se preparan tokens pero no se implementa.
- Lógica de dominio (`TimeEngine`, `BudgetService`, `EventEngine`, `StoryGenerator`, Open-Meteo) — el scaffold no importa `domain/` más allá de `mockFoggRoute` para placeholder Ruta.

> Cada uno de ellos, si aterriza, irá en su propia spec.

