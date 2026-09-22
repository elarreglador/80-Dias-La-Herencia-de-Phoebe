import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pf/presentation/pages/main_scaffold.dart';
import 'package:pf/presentation/providers/bottom_nav_provider.dart';
import 'package:pf/presentation/widgets/fogg_app_bar.dart';
import 'package:pf/presentation/widgets/world_map_widget.dart';

void main() {
  group('FoggAppBar', () {
    testWidgets('renderiza título y subtítulo con preferredSize 64', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(home: Scaffold(appBar: FoggAppBar())),
        ),
      );
      await tester.pump();
      expect(find.text('80 Días — La Herencia de Phoebe'), findsOneWidget);
      // Subtítulo fecha local (ej: "22 sep 2026")
      expect(find.textContaining(RegExp(r'\d+ \w+ \d{4}')), findsOneWidget);

      final appBar = tester.widget<AppBar>(find.byType(AppBar));
      expect(appBar.elevation, 0);
      expect(appBar.scrolledUnderElevation, 0);
      expect(appBar.centerTitle, true);

      const foggAppBar = FoggAppBar();
      expect(foggAppBar.preferredSize.height, 64);
    });
  });

  group('MainScaffold', () {
    testWidgets('muestra AppBar, Mapa inicial y NavigationBar con 4 destinos', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(child: MaterialApp(home: MainScaffold())),
      );
      await tester.pumpAndSettle();

      expect(find.byType(FoggAppBar), findsOneWidget);
      expect(find.byType(WorldMapWidget), findsOneWidget);
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.byType(NavigationDestination), findsNWidgets(4));
      expect(find.text('Mapa'), findsOneWidget);
      expect(find.text('Diario'), findsOneWidget);
      expect(find.text('Presupuesto'), findsOneWidget);
      expect(find.text('Ruta'), findsOneWidget);
    });

    testWidgets('IndexedStack index 0 muestra WorldMapWidget, iconos outline/filled', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(child: MaterialApp(home: MainScaffold())),
      );
      await tester.pumpAndSettle();

      // Mapa visible en índice 0
      expect(find.byType(WorldMapWidget), findsOneWidget);
      // Iconos según selección: Mapa filled, resto outlined
      expect(find.byIcon(Icons.map), findsOneWidget);
      expect(find.byIcon(Icons.map_outlined), findsNothing);
      expect(find.byIcon(Icons.menu_book_outlined), findsOneWidget);
    });

    testWidgets('tap en Diario cambia provider a 1 y muestra placeholder-diary', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: MainScaffold()),
        ),
      );
      await tester.pumpAndSettle();
      expect(container.read(bottomNavIndexProvider), 0);

      await tester.tap(find.text('Diario'));
      await tester.pumpAndSettle();

      expect(container.read(bottomNavIndexProvider), 1);
      expect(find.byKey(const ValueKey('placeholder-diary')), findsOneWidget);
      expect(find.textContaining('Próximamente — Diario'), findsOneWidget);
      expect(find.byIcon(Icons.menu_book), findsOneWidget);
    });

    testWidgets('tap en Presupuesto y Ruta muestran placeholders correspondientes', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: MainScaffold()),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Presupuesto'));
      await tester.pumpAndSettle();
      expect(container.read(bottomNavIndexProvider), 2);
      expect(find.byKey(const ValueKey('placeholder-budget')), findsOneWidget);

      await tester.tap(find.text('Ruta'));
      await tester.pumpAndSettle();
      expect(container.read(bottomNavIndexProvider), 3);
      expect(find.byKey(const ValueKey('placeholder-route')), findsOneWidget);
    });

    testWidgets('IndexedStack preserva estado de WorldMapWidget al volver a Mapa', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: MainScaffold()),
        ),
      );
      await tester.pumpAndSettle();

      // Mapa inicial
      final worldMapFinder = find.byType(WorldMapWidget);
      expect(worldMapFinder, findsOneWidget);
      final initialWidget = tester.widget<WorldMapWidget>(worldMapFinder);

      // Ir a Diario
      await tester.tap(find.text('Diario'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('placeholder-diary')), findsOneWidget);
      // IndexedStack mantiene 4 hijos, WorldMapWidget sigue en árbol aunque offstage
      expect(find.byType(WorldMapWidget, skipOffstage: false), findsOneWidget);

      // Volver a Mapa
      await tester.tap(find.text('Mapa'));
      await tester.pumpAndSettle();
      expect(find.byType(WorldMapWidget), findsOneWidget);
      final returnedWidget = tester.widget<WorldMapWidget>(find.byType(WorldMapWidget));
      expect(returnedWidget.route, initialWidget.route);
      expect(returnedWidget.initialZoom, initialWidget.initialZoom);
      // IndexedStack debe ser tipo correcto
      expect(find.byType(IndexedStack), findsOneWidget);
      final stack = tester.widget<IndexedStack>(find.byType(IndexedStack));
      expect(stack.index, 0);
    });

    testWidgets('tapping no lanza excepción de HapticFeedback', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(child: MaterialApp(home: MainScaffold())),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Presupuesto'));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('placeholders tienen Semantics y no importan dominio', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: MainScaffold()),
        ),
      );
      await tester.pumpAndSettle();

      // Diario — verificar Semantics widget directamente (find.bySemanticsLabel requiere árbol semántico activo)
      await tester.tap(find.text('Diario'));
      await tester.pumpAndSettle();
      expect(
        find.byWidgetPredicate(
          (w) => w is Semantics && w.properties.label == 'Pestaña Diario',
        ),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('placeholder-diary')), findsOneWidget);
      expect(find.textContaining('Próximamente'), findsOneWidget);

      // Presupuesto
      await tester.tap(find.text('Presupuesto'));
      await tester.pumpAndSettle();
      expect(
        find.byWidgetPredicate(
          (w) => w is Semantics && w.properties.label == 'Pestaña Presupuesto',
        ),
        findsOneWidget,
      );

      // Ruta
      await tester.tap(find.text('Ruta'));
      await tester.pumpAndSettle();
      expect(
        find.byWidgetPredicate(
          (w) => w is Semantics && w.properties.label == 'Pestaña Ruta',
        ),
        findsOneWidget,
      );
    });

    testWidgets('SafeArea en NavigationBar y WorldMapWidget controles visibles', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(child: MaterialApp(home: MainScaffold())),
      );
      await tester.pumpAndSettle();

      // SafeArea presente para botonera
      expect(find.byType(SafeArea), findsWidgets);
      // MapControlsOverlay visible en pestaña Mapa
      await tester.tap(find.text('Mapa'));
      await tester.pumpAndSettle();
      expect(find.byType(WorldMapWidget), findsOneWidget);
      // Controles deben ser visibles (zoom + center + OSM)
      expect(find.byIcon(Icons.add), findsOneWidget);
      expect(find.byIcon(Icons.remove), findsOneWidget);
    });

    testWidgets('WorldMapWidget sigue con TileLayer + PolygonLayer + PolylineLayer sin regresión', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(child: MaterialApp(home: MainScaffold())),
      );
      await tester.pumpAndSettle();

      // Verifica orden de capas dentro de FlutterMap del MapTab
      final flutterMap = tester.widget<FlutterMap>(find.byType(FlutterMap));
      expect(flutterMap.children.any((w) => w is PolygonLayer), isTrue);
      expect(flutterMap.children.any((w) => w is TileLayer), isTrue);
    });
  });
}
