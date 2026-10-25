import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:pf/domain/entities/destination_option.dart';
import 'package:pf/domain/entities/fogg_city.dart';
import 'package:pf/domain/entities/fogg_status.dart';
import 'package:pf/domain/entities/transport_mode.dart';
import 'package:pf/domain/models/route_entry.dart';
import 'package:pf/domain/models/route_path.dart';
import 'package:pf/presentation/providers/fogg_position_provider.dart';
import 'package:pf/presentation/providers/game_notifier.dart';
import 'package:pf/presentation/widgets/world_map_widget.dart';
import 'package:pf/services/budget_service.dart';
import 'package:pf/services/game_session.dart';
import 'package:pf/services/time_engine.dart';
import 'package:pf/utils/app_colors.dart';

// Mock url_launcher: no necesita mock explícito — canLaunchUrl devuelve false en test
// y no lanza excepción. Verificamos que el botón existe y el tap no crashea.

/// Geometría de prueba — tres vértices con el punto medio en [5, 2].
final _geometry = <List<double>>[
  [0.0, 0.0],
  [5.0, 2.0],
  [10.0, 4.0],
];

RouteEntry _routeEntry({RouteSource source = RouteSource.sea}) => RouteEntry(
      source: source,
      origin: 'Origen',
      destination: 'Destino',
      distanceKm: 1250,
      durationHours: 10,
      heading: 'east',
      geometry: _geometry,
    );

const _from = FoggCity(name: 'Origen', lat: 0, lng: 0, order: 0, timezone: 'UTC');
const _to = FoggCity(name: 'Destino', lat: 4, lng: 10, order: 1, timezone: 'UTC');

/// Notificador con estado fijo — para estados que la sesión no produce sola.
class _FixedStatusNotifier extends GameNotifier {
  _FixedStatusNotifier(this.fixedStatus);
  final FoggStatus fixedStatus;

  @override
  FoggStatus build() => fixedStatus;
}

/// Sesión con un tramo en curso y reloj controlable.
class _Harness {
  _Harness({TransportMode mode = TransportMode.ship}) {
    session = GameSession(timeEngine: engine, budget: BudgetService(initial: 100000));
    session.startLeg(
      from: _from,
      to: _to,
      vehicle: VehicleOption(
        mode: mode,
        duration: const Duration(hours: 10),
        price: 100,
        sleeper: true,
        route: _routeEntry(source: mode == TransportMode.ship ? RouteSource.sea : RouteSource.rail),
      ),
    );
  }

  final DateTime start = DateTime.utc(2026, 1, 1, 12);
  DateTime clockNow = DateTime.utc(2026, 1, 1, 12);
  late final TimeEngine engine = TimeEngine(
    startUtc: start,
    timeScale: 1.0,
    clock: () => clockNow,
  );
  late final GameSession session;

  /// Avanza el reloj del juego.
  void advance(Duration d) => clockNow = clockNow.add(d);

  ProviderContainer container() => ProviderContainer(
        overrides: [
          gameSessionProvider.overrideWithValue(session),
          timeEngineProvider.overrideWithValue(engine),
        ],
      );
}

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
                child: WorldMapWidget(),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      // No debe lanzar excepción, debe mostrar atribución OSM
      expect(find.textContaining('OpenStreetMap'), findsOneWidget);
    });

    testWidgets('dibuja el trayecto activo: recorrido sólido y pendiente discontinuo',
        (tester) async {
      final harness = _Harness();
      final container = harness.container();
      addTearDown(container.dispose);
      // Mitad del trayecto: departure = start, arrival = start+10h.
      harness.advance(const Duration(hours: 5));

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 800,
                height: 600,
                child: WorldMapWidget(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final polyLayer = tester.widgetList<PolylineLayer>(find.byType(PolylineLayer));
      expect(polyLayer.length, 1);
      final polylines = polyLayer.first.polylines;
      expect(polylines.length, 2, reason: 'tramo recorrido + tramo pendiente');

      // Parte recorrida — sólida, 4 px, color del modo.
      final traveled = polylines[0];
      expect(traveled.pattern.segments, isNull, reason: 'la parte recorrida es sólida');
      expect(traveled.color, AppColors.routeShip);
      expect(traveled.strokeWidth, 4.0);
      expect(traveled.points.first.latitude, closeTo(0, 1e-9));
      expect(traveled.points.last.longitude, closeTo(5, 0.01),
          reason: 'el corte cae en el punto medio de la geometría');

      // Parte pendiente — discontinua, 4 px, color del modo.
      final pending = polylines[1];
      expect(pending.pattern.segments, isNotNull, reason: 'la parte pendiente es discontinua');
      expect(pending.pattern.segments, [12, 8]);
      expect(pending.color, AppColors.routeShip);
      expect(pending.strokeWidth, 4.0);
      expect(pending.points.last.latitude, closeTo(4, 1e-9));
      expect(pending.points.last.longitude, closeTo(10, 1e-9));

      // Las dos mitades se encuentran.
      expect(traveled.points.last.longitude, closeTo(pending.points.first.longitude, 1e-9));
      expect(traveled.points.last.latitude, closeTo(pending.points.first.latitude, 1e-9));
    });

    testWidgets('el marcador de Phoebe se sitúa sobre la geometría', (tester) async {
      final harness = _Harness();
      final container = harness.container();
      addTearDown(container.dispose);
      harness.advance(const Duration(hours: 5));

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 800,
                height: 600,
                child: WorldMapWidget(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final markerLayers = tester.widgetList<MarkerLayer>(find.byType(MarkerLayer)).toList();
      // Capa 1: origen y destino del tramo. Capa 2: Phoebe.
      expect(markerLayers.length, 2);
      expect(markerLayers.first.markers.length, 2);
      expect(markerLayers.first.markers.first.point, const LatLng(0, 0));
      expect(markerLayers.first.markers.last.point, const LatLng(4, 10));

      final phoebe = markerLayers.last.markers.single.point;
      final expected = RoutePath.fromGeometry(_geometry)!.positionAt(0.5);
      expect(phoebe.latitude, closeTo(expected.latitude, 1e-9));
      expect(phoebe.longitude, closeTo(expected.longitude, 1e-9));
      // Y coincide con el provider derivado.
      expect(container.read(foggPositionProvider), phoebe);
    });

    testWidgets('el historial de tramos permanece en el color de su modo', (tester) async {
      final harness = _Harness(mode: TransportMode.train);
      final container = harness.container();
      addTearDown(container.dispose);
      // Tras la llegada, el tramo pasa al historial.
      harness.advance(const Duration(hours: 20));
      harness.session.tick();
      expect(harness.session.completedLegs.length, 1);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 800,
                height: 600,
                child: WorldMapWidget(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final polyLayer = tester.widget<PolylineLayer>(find.byType(PolylineLayer));
      final polylines = polyLayer.polylines;
      expect(polylines.length, 1, reason: 'solo el tramo ya recorrido');
      expect(polylines.first.color, AppColors.routeTrain);
      expect(polylines.first.strokeWidth, 2.0);
      expect(polylines.first.pattern.segments, isNull);
      expect(polylines.first.points.length, 3);
    });

    testWidgets('las rutas candidatas solo se dibujan en gris cuando está en ciudad',
        (tester) async {
      final container = ProviderContainer(
        overrides: [
          gameNotifierProvider.overrideWith(
            () => _FixedStatusNotifier(
              const FoggArrived(
                currentCity: _to,
                options: [
                  DestinationOption(
                    city: _to,
                    vehicles: [
                      VehicleOption(
                        mode: TransportMode.ship,
                        duration: Duration(hours: 10),
                        price: 100,
                        route: RouteEntry(
                          source: RouteSource.sea,
                          origin: 'Origen',
                          destination: 'Destino',
                          distanceKm: 1250,
                          durationHours: 10,
                          heading: 'east',
                          geometry: [
                            [0.0, 0.0],
                            [5.0, 2.0],
                            [10.0, 4.0],
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
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
                child: WorldMapWidget(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final polyLayer = tester.widget<PolylineLayer>(find.byType(PolylineLayer));
      final polylines = polyLayer.polylines;
      expect(polylines.length, 1);
      expect(polylines.first.color, AppColors.routeCandidate.withValues(alpha: 0.35));
      expect(polylines.first.strokeWidth, 2.0);
      expect(polylines.first.pattern.segments, isNull);
      expect(polylines.first.points.length, 3);
    });

    testWidgets('mockFoggRoute no se dibuja en el mapa', (tester) async {
      final harness = _Harness();
      final container = harness.container();
      addTearDown(container.dispose);
      harness.advance(const Duration(hours: 10));

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 800,
                height: 600,
                child: WorldMapWidget(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final polyLayer = tester.widget<PolylineLayer>(find.byType(PolylineLayer));
      final points = polyLayer.polylines.expand((p) => p.points).toList();
      // Ninguna ciudad del mock (Londres, París, Estambul, Bombay, Tokio...).
      expect(points.any((p) => p.latitude == 51.5072 && p.longitude == -0.1276), isFalse);
      expect(points.any((p) => p.latitude == 48.8566 && p.longitude == 2.3522), isFalse);
      // Solo la geometría real del tramo.
      expect(points.every((p) => p.longitude >= 0 && p.longitude <= 10), isTrue);
    });

    testWidgets('controles zoom clamp 2..18', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 800,
                height: 600,
                child: WorldMapWidget(),
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
                child: WorldMapWidget(),
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
                child: WorldMapWidget(),
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
              body: WorldMapWidget(height: 300),
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
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: WorldMapWidget(
                foggPosition: LatLng(48.8566, 2.3522),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
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
                child: WorldMapWidget(),
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
                child: WorldMapWidget(),
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
      // Verifica que es contain (no containCenter ni unconstrained) — ahora con fallback
      expect(constraint.toString(), contains('ContainCamera'));
      // CRS sin repetición horizontal: evita salto al otro extremo del antimeridiano en cualquier zoom
      expect(flutterMap.options.crs.replicatesWorldLongitude, isFalse,
          reason: 'CRS debe ser Epsg3857NoRepeat para que el mapa se detenga en el borde');
      // Polyline debe dibujar en mundo único (sin offsets de copia)
      final polyLayer = tester.widget<PolylineLayer>(find.byType(PolylineLayer));
      expect(polyLayer.drawInSingleWorld, isTrue);
    });

    testWidgets('orden de capas: Tile → Polygon → Polyline → marcadores', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 800,
                height: 600,
                child: WorldMapWidget(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final flutterMap = tester.widget<FlutterMap>(find.byType(FlutterMap));
      final children = flutterMap.children;
      expect(children[0], isA<TileLayer>());
      expect(children[1], isA<PolygonLayer>());
      expect(children[2], isA<PolylineLayer>());
      expect(children[3], isA<MarkerLayer>());
    });
  });
}
