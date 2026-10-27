import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pf/domain/entities/fogg_city.dart';
import 'package:pf/domain/entities/fogg_leg.dart';
import 'package:pf/domain/entities/fogg_status.dart';
import 'package:pf/domain/entities/transport_mode.dart';
import 'package:pf/presentation/providers/fogg_position_provider.dart';
import 'package:pf/presentation/providers/game_notifier.dart';
import 'package:pf/presentation/widgets/world_map_widget.dart';

const _from = FoggCity(name: 'Origen', lat: 0, lng: 0, order: 0, timezone: 'UTC');
const _to = FoggCity(name: 'Destino', lat: 4, lng: 10, order: 1, timezone: 'UTC');

const _fukuoka = FoggCity(
  name: 'Fukuoka',
  lat: 33.5904,
  lng: 130.4017,
  order: 0,
  timezone: 'UTC',
);
const _vancouver = FoggCity(
  name: 'Vancouver',
  lat: 49.2827,
  lng: -123.1207,
  order: 1,
  timezone: 'UTC',
);

/// Notificador con estado fijo — para estados que la sesión no produce sola.
class _FixedStatusNotifier extends GameNotifier {
  _FixedStatusNotifier(this.fixedStatus);
  final FoggStatus fixedStatus;

  @override
  FoggStatus build() => fixedStatus;
}

FoggLeg _leg(FoggCity from, FoggCity to) => FoggLeg(
      from: from,
      to: to,
      transport: TransportMode.ship,
      departureUtc: DateTime.utc(2026, 1, 1, 12),
      arrivalUtc: DateTime.utc(2026, 1, 1, 22),
      price: 100,
    );

ProviderContainer _container(FoggStatus status) {
  final container = ProviderContainer(
    overrides: [
      gameNotifierProvider.overrideWith(() => _FixedStatusNotifier(status)),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

Future<void> _pumpMap(WidgetTester tester, ProviderContainer container) async {
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
}

void main() {
  group('botón centrar con trayecto en curso', () {
    testWidgets('encuadra origen y destino con un tramo viable', (tester) async {
      final container = _container(
        FoggTraveling(leg: _leg(_from, _to)),
      );
      await _pumpMap(tester, container);

      expect(find.byTooltip('Encuadrar trayecto'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.my_location));
      await tester.pump();
      expect(
        find.text('Encuadrando trayecto: Origen → Destino'),
        findsOneWidget,
      );

      // Animación 600 ms — el zoom del fit (≈6.5) sustituye al inicial 3.0.
      await tester.pumpAndSettle();
      final zoom = container.read(mapZoomProvider);
      expect(zoom, greaterThan(3.0));
      expect(zoom, lessThanOrEqualTo(18.0));

      // Deja caducar el SnackBar para no dejar timers pendientes.
      await tester.pumpAndSettle(const Duration(seconds: 3));
    });

    testWidgets(
        'tramo que cruza antimeridiano en pantalla estrecha — '
        'fallback al origen sin cambiar el zoom', (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final container = _container(
        FoggTraveling(leg: _leg(_fukuoka, _vancouver)),
      );
      await _pumpMap(tester, container);

      expect(find.byTooltip('Encuadrar trayecto'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.my_location));
      await tester.pump();
      expect(
        find.text(
          'Trayecto no cabe en pantalla — centrando en el origen (Fukuoka)',
        ),
        findsOneWidget,
      );

      await tester.pumpAndSettle();
      expect(container.read(mapZoomProvider), 3.0);

      await tester.pumpAndSettle(const Duration(seconds: 3));
    });

    testWidgets('sin trayecto — comportamiento actual centrando en Phoebe',
        (tester) async {
      final container = _container(
        const FoggArrived(currentCity: _from, options: []),
      );
      await _pumpMap(tester, container);

      expect(find.byTooltip('Centrar en Phoebe'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.my_location));
      await tester.pump();
      expect(
        find.text(
          'Centrando en Phoebe — 0.00, 0.00 (la línea roja va hasta Tokio)',
        ),
        findsOneWidget,
      );

      await tester.pumpAndSettle();
      expect(container.read(mapZoomProvider), 3.0);

      await tester.pumpAndSettle(const Duration(seconds: 3));
    });

    testWidgets('sigue deshabilitado si foggPosition es null', (tester) async {
      final container = ProviderContainer(
        overrides: [
          gameNotifierProvider
              .overrideWith(() => _FixedStatusNotifier(FoggTraveling(
                    leg: _leg(_from, _to),
                  ))),
          foggPositionProvider.overrideWith((ref) => null),
        ],
      );
      addTearDown(container.dispose);
      await _pumpMap(tester, container);

      expect(find.byTooltip('Posición no disponible'), findsOneWidget);
    });
  });
}
