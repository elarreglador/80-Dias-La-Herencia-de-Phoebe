import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pf/domain/entities/fogg_route.dart';
import 'package:pf/presentation/providers/sun_terminator_provider.dart';
import 'package:pf/presentation/widgets/world_map_widget.dart';
import 'package:pf/services/sun_terminator_service.dart';
import 'package:pf/utils/app_colors.dart';

void main() {
  group('WorldMap terminador solar — PolygonLayer', () {
    // Helper para obtener UTC determinista solsticio (curvo 183)
    final solsticeUtc = DateTime.utc(2026, 6, 21, 12, 0, 0);
    final equinoxUtc = DateTime.utc(2026, 9, 22, 12, 0, 0);

    testWidgets('PolygonLayer existe y es segundo children tras TileLayer (solsticio)',
        (tester) async {
      final polys = SunTerminatorService.nightPolygons(solsticeUtc);
      expect(polys.length, 2, reason: 'Solsticio partido en 2 para evitar diagonal');
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentUtcProvider.overrideWith((ref) => Stream.value(solsticeUtc)),
            sunTerminatorProvider.overrideWithValue(polys),
          ],
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

      final flutterMap = tester.widget<FlutterMap>(find.byType(FlutterMap));
      final children = flutterMap.children;
      expect(children.length, greaterThanOrEqualTo(5));
      expect(children[0], isA<TileLayer>());
      expect(children[1], isA<PolygonLayer>());
      expect(children[2], isA<PolylineLayer>());
      final polyLayer = children[1] as PolygonLayer;
      expect(polyLayer.polygons.length, 2);
      for (final p in polyLayer.polygons) {
        expect(p.points.length, greaterThanOrEqualTo(100));
        expect(p.label, isNull, reason: 'rótulo night retirado');
      }
    });

    testWidgets('equinoccio genera 2 polígonos rectángulos split antimeridiano',
        (tester) async {
      final polys = SunTerminatorService.nightPolygons(equinoxUtc);
      expect(polys.length, 2);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentUtcProvider.overrideWith((ref) => Stream.value(equinoxUtc)),
            sunTerminatorProvider.overrideWithValue(polys),
          ],
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

      final flutterMap = tester.widget<FlutterMap>(find.byType(FlutterMap));
      final polyLayer = flutterMap.children[1] as PolygonLayer;
      expect(polyLayer.polygons.length, 2);
      for (final p in polyLayer.polygons) {
        expect(p.points.length, 4);
        expect(p.color, AppColors.nightOverlay);
      }
    });

    testWidgets('color == #000511 alpha 0.45 y borderStrokeWidth==0 (solsticio)',
        (tester) async {
      final polys = SunTerminatorService.nightPolygons(solsticeUtc);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentUtcProvider.overrideWith((ref) => Stream.value(solsticeUtc)),
            sunTerminatorProvider.overrideWithValue(polys),
          ],
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

      final flutterMap = tester.widget<FlutterMap>(find.byType(FlutterMap));
      final polyLayer = flutterMap.children[1] as PolygonLayer;
      final poly = polyLayer.polygons.first;
      expect(poly.color, AppColors.nightOverlay);
      expect(poly.color, const Color(0xFF000511).withValues(alpha: 0.45));
      expect(poly.borderStrokeWidth, 0);
      expect(poly.borderColor, Colors.transparent);
    });

    testWidgets('orden: Tile < Polygon < Polyline < Marker', (tester) async {
      final polys = SunTerminatorService.nightPolygons(solsticeUtc);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentUtcProvider.overrideWith((ref) => Stream.value(solsticeUtc)),
            sunTerminatorProvider.overrideWithValue(polys),
          ],
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

      final flutterMap = tester.widget<FlutterMap>(find.byType(FlutterMap));
      final types = flutterMap.children.map((w) => w.runtimeType).toList();
      final tileIdx = types.indexWhere((t) => t == TileLayer);
      final polyIdx = types.indexWhere((t) => t == PolygonLayer);
      final lineIdx = types.indexWhere((t) => t == PolylineLayer);
      final markerIdx = types.indexWhere((t) => t == MarkerLayer);
      expect(tileIdx, 0);
      expect(polyIdx, greaterThan(tileIdx));
      expect(lineIdx, greaterThan(polyIdx));
      expect(markerIdx, greaterThan(lineIdx));
      final polyLayer = tester.widget<PolylineLayer>(find.byType(PolylineLayer));
      expect(polyLayer.polylines.first.color,
          const Color(0xFFC0392B).withValues(alpha: 0.95));
    });

    testWidgets('ruta roja y marcadores por encima del sombreado nocturno',
        (tester) async {
      final polys = SunTerminatorService.nightPolygons(solsticeUtc);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentUtcProvider.overrideWith((ref) => Stream.value(solsticeUtc)),
            sunTerminatorProvider.overrideWithValue(polys),
          ],
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

      final flutterMap = tester.widget<FlutterMap>(find.byType(FlutterMap));
      final children = flutterMap.children;
      final polygonPos = children.indexWhere((w) => w is PolygonLayer);
      final polylinePos = children.indexWhere((w) => w is PolylineLayer);
      final markerPos = children.indexWhere((w) => w is MarkerLayer);
      expect(polygonPos, lessThan(polylinePos));
      expect(polylinePos, lessThan(markerPos));
    });

    testWidgets('con replicatesWorldLongitude==false el polígono no se duplica',
        (tester) async {
      final polys = SunTerminatorService.nightPolygons(solsticeUtc);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentUtcProvider.overrideWith((ref) => Stream.value(solsticeUtc)),
            sunTerminatorProvider.overrideWithValue(polys),
          ],
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

      final flutterMap = tester.widget<FlutterMap>(find.byType(FlutterMap));
      expect(flutterMap.options.crs.replicatesWorldLongitude, isFalse);
      final polyLayers = tester.widgetList<PolygonLayer>(find.byType(PolygonLayer));
      expect(polyLayers.length, 1);
    });

    testWidgets('WorldMapWidget consume sunTerminatorProvider sin crashear (equinoccio)',
        (tester) async {
      final polys = SunTerminatorService.nightPolygons(equinoxUtc);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentUtcProvider.overrideWith(
              (ref) => Stream.value(equinoxUtc),
            ),
            sunTerminatorProvider.overrideWithValue(polys),
          ],
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
      final flutterMap = tester.widget<FlutterMap>(find.byType(FlutterMap));
      final polyLayer = flutterMap.children[1] as PolygonLayer;
      expect(polyLayer.polygons.length, 2);
      expect(polyLayer.polygons.first.points.length, 4);
      expect(tester.takeException(), isNull);
    });

    test('sunTerminatorProvider deriva de currentUtcProvider (solsticio)', () async {
      final container = ProviderContainer(
        overrides: [
          currentUtcProvider.overrideWith((ref) => Stream.value(solsticeUtc)),
        ],
      );
      addTearDown(container.dispose);
      await container.read(currentUtcProvider.future);
      final polys = container.read(sunTerminatorProvider);
      expect(polys.length, 2);
      for (final poly in polys) {
        expect(poly.length, greaterThan(100));
        for (final p in poly) {
          expect(p.latitude, greaterThanOrEqualTo(-85.05112878 - 1e-9));
          expect(p.latitude, lessThanOrEqualTo(85.05112878 + 1e-9));
        }
      }
      expect(polys.first.first.longitude, closeTo(-180, 1e-9));
      expect(polys.last.first.longitude, closeTo(0, 1e-9));
    });

    test('sunTerminatorProvider equinoccio devuelve 2 rectángulos', () async {
      final container = ProviderContainer(
        overrides: [
          currentUtcProvider.overrideWith((ref) => Stream.value(equinoxUtc)),
        ],
      );
      addTearDown(container.dispose);
      await container.read(currentUtcProvider.future);
      final polys = container.read(sunTerminatorProvider);
      expect(polys.length, 2);
      expect(polys.first.length, 4);
      expect(polys.last.length, 4);
    });

    test('currentUtcProvider emite DateTime UTC', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final first = await container.read(currentUtcProvider.future);
      expect(first.isUtc, isTrue);
      expect(first, isA<DateTime>());
    });

    test('no fuga Timer al dispose — ProviderContainer dispose limpio', () {
      final container = ProviderContainer();
      final sub = container.listen(currentUtcProvider, (_, __) {});
      expect(sub, isNotNull);
      expect(() => container.dispose(), returnsNormally);
    });

    testWidgets('zoom 2 y 18 sin artefactos ni replicación (solsticio)', (tester) async {
      final polys = SunTerminatorService.nightPolygons(solsticeUtc);
      expect(polys.length, 2);
      for (final zoom in [2.0, 18.0]) {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              currentUtcProvider.overrideWith((ref) => Stream.value(solsticeUtc)),
              sunTerminatorProvider.overrideWithValue(polys),
            ],
            child: MaterialApp(
              home: Scaffold(
                body: SizedBox(
                  width: 800,
                  height: 600,
                  child: WorldMapWidget(
                    route: mockFoggRoute,
                    initialZoom: zoom,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final flutterMap = tester.widget<FlutterMap>(find.byType(FlutterMap));
        expect(flutterMap.options.minZoom, 2.0);
        expect(flutterMap.options.maxZoom, 18.0);
        expect(flutterMap.options.crs.replicatesWorldLongitude, isFalse);
        final polyLayer = tester.widget<PolygonLayer>(find.byType(PolygonLayer));
        expect(polyLayer.polygons.length, 2);
        for (final p in polyLayer.polygons) {
          expect(p.points.length, greaterThan(100));
        }
      }
    });

    testWidgets('clamp Mercator 85.05 en polígono nocturno', (tester) async {
      final polys = SunTerminatorService.nightPolygons(solsticeUtc);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentUtcProvider.overrideWith((ref) => Stream.value(solsticeUtc)),
            sunTerminatorProvider.overrideWithValue(polys),
          ],
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
      final flutterMap = tester.widget<FlutterMap>(find.byType(FlutterMap));
      final polyLayer = flutterMap.children[1] as PolygonLayer;
      for (final poly in polyLayer.polygons) {
        for (final p in poly.points) {
          expect(p.latitude, lessThanOrEqualTo(85.05112878 + 1e-9));
          expect(p.latitude, greaterThanOrEqualTo(-85.05112878 - 1e-9));
        }
      }
    });
  });
}
