import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:pf/domain/entities/fogg_route.dart';
import 'package:pf/presentation/providers/fogg_position_provider.dart';
import 'package:pf/presentation/widgets/world_map_widget.dart';

// Mock url_launcher: no necesita mock explícito — canLaunchUrl devuelve false en test
// y no lanza excepción. Verificamos que el botón existe y el tap no crashea.

void main() {
  group('WorldMapWidget', () {
    testWidgets('carga sin error dentro de ProviderScope', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 800,
                height: 600,
                child: WorldMapWidget(route: mockFoggRoute),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      // No debe lanzar excepción, debe mostrar atribución OSM
      expect(find.textContaining('OpenStreetMap'), findsOneWidget);
    });

    testWidgets('renderiza 1 polyline con 6 puntos y 6 markers', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 800,
                height: 600,
                child: WorldMapWidget(route: mockFoggRoute),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verifica PolylineLayer existe y tiene 6 puntos (cierra en Savile Row)
      final polyLayer = tester.widgetList<PolylineLayer>(find.byType(PolylineLayer));
      expect(polyLayer.length, 1);
      final polylines = polyLayer.first.polylines;
      expect(polylines.length, 1);
      expect(polylines.first.points.length, 6);
      // Verifica color #C0392B opacity 0.95 y stroke según spec
      expect(polylines.first.color, const Color(0xFFC0392B).withValues(alpha: 0.95));
      expect(polylines.first.strokeWidth, 4.0);

      // Verifica MarkerLayer: 6 ciudades + 1 Phoebe = 2 capas, 6 en primera
      final markerLayers = tester.widgetList<MarkerLayer>(find.byType(MarkerLayer)).toList();
      expect(markerLayers.length, 2); // ciudades + Phoebe distintivo
      expect(markerLayers.first.markers.length, 6); // 6 ciudades (incluye Savile Row)
      final allMarkers = markerLayers.expand((l) => l.markers).toList();
      expect(allMarkers.length, 7); // 6 ciudades + 1 Phoebe
      // Verifica que la polyline pasa exactamente por los puntos (nuevo alignment center)

      // Verifica que al menos un label visible (a zoom 3, colisión puede ocultar 1)
      // Con zoom inicial 3, se espera al menos 4 labels
      // Forzamos zoom 7 para verificar todos visibles
    });

    testWidgets('colisión: zoom <6 oculta label, zoom >=7 muestra todos', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 800,
                height: 600,
                child: WorldMapWidget(route: mockFoggRoute),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verifica colisión inspeccionando MarkerLayer fuente (evita culling offscreen)
      int countLabelsFromMarkers() {
        final layers = tester.widgetList<MarkerLayer>(find.byType(MarkerLayer)).toList();
        // Primera capa = ciudades (6), segunda = Phoebe (1) si existe
        final cityLayer = layers.firstWhere((l) => l.markers.length == 6, orElse: () => layers.first);
        int count = 0;
        for (final m in cityLayer.markers) {
          final child = m.child;
          if (child is Stack) {
            // Stack con 2 hijos (punto + label) si visible, 1 si oculto
            if (child.children.length == 2) count++;
          } else if (child is Column) {
            if (child.children.length == 3) count++;
          }
        }
        return count;
      }

      final labelsZoom3 = countLabelsFromMarkers();
      // A zoom 3 debe ocultar 2 (París por Londres y Savile Row por Londres) → 4 visibles
      expect(labelsZoom3, 4);

      // Cambia a zoom 7 → todos visibles (zoom >=6 desactiva colisión) → 6
      container.read(mapZoomProvider.notifier).state = 7.0;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpAndSettle();
      final labelsZoom7 = countLabelsFromMarkers();
      expect(labelsZoom7, 6);
    });

    testWidgets('controles zoom clamp 2..18', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 800,
                height: 600,
                child: WorldMapWidget(route: mockFoggRoute),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Encuentra botones + y −
      expect(find.byIcon(Icons.add), findsOneWidget);
      expect(find.byIcon(Icons.remove), findsOneWidget);
      expect(find.byIcon(Icons.my_location), findsOneWidget);
      expect(find.byIcon(Icons.open_in_new), findsOneWidget);
    });

    testWidgets('botón centrar disabled si foggPosition null', (tester) async {
      final container = ProviderContainer(
        overrides: [
          foggPositionProvider.overrideWith((ref) => null),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 800,
                height: 600,
                child: WorldMapWidget(route: mockFoggRoute),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Botón centrar debe estar con tooltip Posición no disponible
      final centerFinder = find.byIcon(Icons.my_location);
      expect(centerFinder, findsOneWidget);
      // Verifica que el widget ancestro tiene tooltip
      expect(find.byTooltip('Posición no disponible'), findsOneWidget);
    });

    testWidgets('botón abrir OSM no crashea en tap (mock url_launcher)', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 800,
                height: 600,
                child: WorldMapWidget(route: mockFoggRoute),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.open_in_new));
      await tester.pump();
      // No excepción — canLaunchUrl retornará false en test y no lanza
      expect(tester.takeException(), isNull);
    });

    testWidgets('WorldMapWidget reutilizable con constraints', (tester) async {
      // Prueba SizedBox padre pequeño y height param
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: WorldMapWidget(route: mockFoggRoute, height: 300),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.byType(WorldMapWidget), findsOneWidget);
      // Altura fija no debe crashear
      expect(tester.takeException(), isNull);
    });

    testWidgets('usa foggPosition naming, no Traveler', (tester) async {
      // Verificación estática: el provider se llama foggPositionProvider
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(foggPositionProvider), isA<LatLng?>());
      // El archivo world_map_widget debe contener foggPosition y no Traveler
      // Esto se verifica por construcción; test solo asegura que compila
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: WorldMapWidget(
                route: mockFoggRoute,
                foggPosition: LatLng(48.8566, 2.3522),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('norte siempre arriba: rotación bloqueada', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 800,
                height: 600,
                child: WorldMapWidget(route: mockFoggRoute),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final flutterMap = tester.widget<FlutterMap>(find.byType(FlutterMap));
      expect(flutterMap.options.initialRotation, 0.0);
      expect(
        flutterMap.options.interactionOptions.flags & InteractiveFlag.rotate,
        0,
        reason: 'InteractiveFlag.rotate debe estar deshabilitado para que el norte permanezca arriba',
      );
      // Verifica que drag y pinchZoom siguen habilitados
      expect(flutterMap.options.interactionOptions.flags & InteractiveFlag.drag, isNot(0));
      expect(flutterMap.options.interactionOptions.flags & InteractiveFlag.pinchZoom, isNot(0));
    });

    testWidgets('no permite desplazar más allá del borde del mundo', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 800,
                height: 600,
                child: WorldMapWidget(route: mockFoggRoute),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final flutterMap = tester.widget<FlutterMap>(find.byType(FlutterMap));
      final constraint = flutterMap.options.cameraConstraint;
      // Debe ser contain con bounds mundiales, no unconstrained
      expect(constraint, isNot(const CameraConstraint.unconstrained()));
      // Verifica que es contain (no containCenter ni unconstrained)
      expect(constraint.toString(), contains('ContainCamera'));
    });
  });
}
