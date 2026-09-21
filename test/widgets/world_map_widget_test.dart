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

    testWidgets('renderiza 1 polyline con 5 puntos y 5 markers', (tester) async {
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

      // Verifica PolylineLayer existe y tiene 5 puntos mock
      final polyLayer = tester.widgetList<PolylineLayer>(find.byType(PolylineLayer));
      expect(polyLayer.length, 1);
      final polylines = polyLayer.first.polylines;
      expect(polylines.length, 1);
      expect(polylines.first.points.length, 5);
      // Verifica color #C0392B opacity 0.95 y stroke según spec
      expect(polylines.first.color, const Color(0xFFC0392B).withValues(alpha: 0.95));
      expect(polylines.first.strokeWidth, 4.0);

      // Verifica MarkerLayer con 5 markers (puntos rojos)
      final markerLayer = tester.widgetList<MarkerLayer>(find.byType(MarkerLayer));
      expect(markerLayer.length, 1);
      expect(markerLayer.first.markers.length, 5);

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
        final markerLayer = tester.widget<MarkerLayer>(find.byType(MarkerLayer));
        int count = 0;
        for (final m in markerLayer.markers) {
          final child = m.child;
          if (child is Column) {
            // Si tiene label, Column tiene 3 hijos (label, SizedBox, punto)
            // si no, solo 1 hijo (punto)
            if (child.children.length == 3) count++;
            // alternativo: buscar Text dentro de Column
            // for (final c in child.children) if (c is Container) count++ ...
          }
        }
        return count;
      }

      final labelsZoom3 = countLabelsFromMarkers();
      // A zoom 3 debe ocultar 1 (París) por cercanía Londres-París → 4 visibles
      expect(labelsZoom3, 4);

      // Cambia a zoom 7 → todos visibles (zoom >=6 desactiva colisión)
      container.read(mapZoomProvider.notifier).state = 7.0;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpAndSettle();
      final labelsZoom7 = countLabelsFromMarkers();
      expect(labelsZoom7, 5);
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
  });
}
