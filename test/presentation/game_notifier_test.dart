import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pf/domain/entities/destination_option.dart';
import 'package:pf/domain/entities/fogg_city.dart';
import 'package:pf/domain/entities/fogg_status.dart';
import 'package:pf/domain/entities/transport_mode.dart';
import 'package:pf/presentation/providers/game_notifier.dart';
import 'package:pf/services/budget_service.dart';
import 'package:pf/services/game_session.dart';
import 'package:pf/services/time_engine.dart';

const _from = FoggCity(name: 'Origen', lat: 0, lng: 0, order: 0, timezone: 'UTC');
const _to = FoggCity(name: 'Destino', lat: 4, lng: 10, order: 1, timezone: 'UTC');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('la partida llega sola a FoggArrived — el reloj llama a tick()', () async {
    var clockNow = DateTime.utc(2026, 1, 1, 12);
    final engine = TimeEngine(
      startUtc: clockNow,
      timeScale: 1.0,
      clock: () => clockNow,
    );
    final session = GameSession(
      timeEngine: engine,
      budget: BudgetService(initial: 100000),
    );
    session.startLeg(
      from: _from,
      to: _to,
      vehicle: const VehicleOption(
        mode: TransportMode.train,
        duration: Duration(hours: 2),
        price: 1000,
      ),
    );
    expect(session.status, isA<FoggTraveling>());

    // El reloj del juego avanza más allá de la llegada.
    clockNow = clockNow.add(const Duration(hours: 24));

    final container = ProviderContainer(
      overrides: [
        gameSessionProvider.overrideWithValue(session),
        timeEngineProvider.overrideWithValue(engine),
      ],
    );
    addTearDown(container.dispose);
    final sub = container.listen(gameNotifierProvider, (_, __) {});
    addTearDown(sub.close);

    // Deja que el reloj emita su primer valor (y el tick lo consuma).
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(container.read(gameNotifierProvider), isA<FoggArrived>());
    expect(session.currentCity.name, 'Destino');
    expect(session.completedLegs.length, 1);
  });

  test('el reloj mantiene el estado mientras se viaja', () async {
    var clockNow = DateTime.utc(2026, 1, 1, 12);
    final engine = TimeEngine(
      startUtc: clockNow,
      timeScale: 1.0,
      clock: () => clockNow,
    );
    final session = GameSession(
      timeEngine: engine,
      budget: BudgetService(initial: 100000),
    );
    session.startLeg(
      from: _from,
      to: _to,
      vehicle: const VehicleOption(
        mode: TransportMode.train,
        duration: Duration(hours: 40),
        price: 1000,
      ),
    );

    final container = ProviderContainer(
      overrides: [
        gameSessionProvider.overrideWithValue(session),
        timeEngineProvider.overrideWithValue(engine),
      ],
    );
    addTearDown(container.dispose);
    final sub = container.listen(gameNotifierProvider, (_, __) {});
    addTearDown(sub.close);

    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(container.read(gameNotifierProvider), isA<FoggTraveling>());
    expect(session.completedLegs, isEmpty);
  });
}
