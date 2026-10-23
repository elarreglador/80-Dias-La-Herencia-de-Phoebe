import 'package:flutter_test/flutter_test.dart';
import 'package:pf/domain/entities/destination_option.dart';
import 'package:pf/domain/entities/fogg_city.dart';
import 'package:pf/domain/entities/transport_mode.dart';
import 'package:pf/domain/models/route_entry.dart';
import 'package:pf/presentation/providers/fogg_position_provider.dart';
import 'package:pf/presentation/providers/game_notifier.dart';
import 'package:pf/services/budget_service.dart';
import 'package:pf/services/game_session.dart';
import 'package:pf/services/time_engine.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const _from = FoggCity(name: 'Origen', lat: 0, lng: 0, order: 0, timezone: 'UTC');
const _to = FoggCity(name: 'Destino', lat: 4, lng: 10, order: 1, timezone: 'UTC');

/// Sesión con reloj controlable — el progreso del tramo depende de él.
class _Harness {
  _Harness({bool arrive = false}) {
    session = GameSession(timeEngine: engine, budget: BudgetService(initial: 100000));
    session.startLeg(
      from: _from,
      to: _to,
      vehicle: const VehicleOption(
        mode: TransportMode.ship,
        duration: Duration(hours: 10),
        price: 100,
        sleeper: true,
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
    );
    if (arrive) session.simulateArrival();
  }

  final DateTime start = DateTime.utc(2026, 1, 1, 12);
  DateTime clockNow = DateTime.utc(2026, 1, 1, 12);
  late final TimeEngine engine = TimeEngine(
    startUtc: start,
    timeScale: 1.0,
    clock: () => clockNow,
  );
  late final GameSession session;

  void advance(Duration d) => clockNow = clockNow.add(d);

  ProviderContainer container() => ProviderContainer(
        overrides: [
          gameSessionProvider.overrideWithValue(session),
          timeEngineProvider.overrideWithValue(engine),
        ],
      );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('foggPositionProvider interpola sobre la geometría mientras viaja', () {
    final harness = _Harness();
    final container = harness.container();
    addTearDown(container.dispose);
    // Mitad del trayecto: departure = start+5h, arrival = start+15h.
    harness.advance(const Duration(hours: 10));

    final pos = container.read(foggPositionProvider);
    expect(pos, isNotNull);
    expect(pos!.longitude, closeTo(5, 0.01));
    expect(pos.latitude, closeTo(2, 0.01));
  });

  test('foggPositionProvider devuelve la ciudad al llegar', () {
    final harness = _Harness(arrive: true);
    final container = harness.container();
    addTearDown(container.dispose);

    final pos = container.read(foggPositionProvider);
    expect(pos, isNotNull);
    expect(pos!.latitude, closeTo(_to.lat, 1e-9));
    expect(pos.longitude, closeTo(_to.lng, 1e-9));
  });

  test('foggPositionProvider es derivado — nadie lo escribe a mano', () async {
    final harness = _Harness();
    final container = harness.container();
    addTearDown(container.dispose);

    final first = container.read(foggPositionProvider);
    // El reloj de la partida publica el avance.
    await Future<void>.delayed(const Duration(milliseconds: 10));
    harness.advance(const Duration(hours: 10));
    final second = container.read(foggPositionProvider);
    expect(first, isNotNull);
    expect(second, isNotNull);
    // Al avanzar el reloj, la posición avanza sobre la geometría.
    expect(second!.longitude, greaterThan(first!.longitude));
  });

  test('mapZoomProvider inicia en 3.0', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(container.read(mapZoomProvider), 3.0);
  });
}
