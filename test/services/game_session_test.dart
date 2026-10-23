import 'package:flutter_test/flutter_test.dart';

import 'package:pf/domain/entities/destination_option.dart';
import 'package:pf/domain/entities/fogg_city.dart';
import 'package:pf/domain/entities/fogg_status.dart';
import 'package:pf/domain/entities/transport_mode.dart';
import 'package:pf/domain/models/route_entry.dart';
import 'package:pf/services/budget_service.dart';
import 'package:pf/services/game_session.dart';
import 'package:pf/services/time_engine.dart';

void main() {
  test('GameSession arranca en Londres a la espera del primer trayecto', () {
    final te = TimeEngine(
      startUtc: DateTime.utc(2026, 1, 1, 12),
      timeScale: 1.0,
      clock: () => DateTime.utc(2026, 1, 1, 12),
    );
    final session = GameSession(
      timeEngine: te,
      budget: BudgetService(initial: 100000),
    );

    expect(session.status, isA<FoggArrived>());
    expect(session.currentCity.name, 'Londres');
    expect(session.currentLeg, isNull);
    expect(session.completedLegs, isEmpty);
    expect(session.options, isNotEmpty);
  });

  test('GameSession inicia leg, gasta y llega', () {
    var now = DateTime.utc(2026, 1, 1, 12);
    final te = TimeEngine(startUtc: now, timeScale: 1.0, clock: () => now);
    final bs = BudgetService(initial: 100000);
    const from = FoggCity(name: 'Londres', lat: 51.5, lng: -0.1, order: 0, timezone: 'Europe/London');
    const to = FoggCity(name: 'París', lat: 48.8, lng: 2.3, order: 1, timezone: 'Europe/Paris');
    final session = GameSession(timeEngine: te, budget: bs, cities: [from, to]);

    session.startLeg(
      from: from,
      to: to,
      vehicle: const VehicleOption(
        mode: TransportMode.train,
        duration: Duration(hours: 2),
        price: 1000,
      ),
    );

    expect(session.status, isA<FoggTraveling>());
    expect(bs.balance, 99000);

    now = now.add(const Duration(hours: 12));
    session.tick();
    expect(session.status, isA<FoggArrived>());
    expect(session.currentCity.name, 'París');
  });

  test('GameSession genera 3 candidatos hacia el este', () {
    var now = DateTime.utc(2026, 1, 1, 12);
    final te = TimeEngine(startUtc: now, timeScale: 1.0, clock: () => now);
    final bs = BudgetService();
    final cities = [
      const FoggCity(name: 'A', lat: 0, lng: 0, order: 0, timezone: 'UTC'),
      const FoggCity(name: 'B', lat: 0, lng: 10, order: 1, timezone: 'UTC'),
      const FoggCity(name: 'C', lat: 0, lng: 20, order: 2, timezone: 'UTC'),
      const FoggCity(name: 'D', lat: 0, lng: 30, order: 3, timezone: 'UTC'),
      const FoggCity(name: 'E', lat: 0, lng: 40, order: 4, timezone: 'UTC'),
    ];
    final session = GameSession(timeEngine: te, budget: bs, cities: cities);
    // fuerza arrived
    session.simulateArrival();
    // currentCity por defecto es cities[0] solo si no se viajó; simulateArrival usa currentCity default (cities[0])
    expect(session.options.length, 3);
  });

  test('GameSession drena fatiga mientras viaja', () {
    var now = DateTime.utc(2026, 1, 1, 12);
    final te = TimeEngine(startUtc: now, timeScale: 1.0, clock: () => now);
    final bs = BudgetService(initial: 100000);
    const from = FoggCity(name: 'Londres', lat: 51.5, lng: -0.1, order: 0, timezone: 'Europe/London');
    const to = FoggCity(name: 'París', lat: 48.8, lng: 2.3, order: 1, timezone: 'Europe/Paris');
    final session = GameSession(timeEngine: te, budget: bs, cities: [from, to]);

    session.startLeg(
      from: from,
      to: to,
      vehicle: const VehicleOption(
        mode: TransportMode.train,
        duration: Duration(hours: 10),
        price: 1000,
        sleeper: true,
      ),
    );

    now = now.add(const Duration(hours: 7));
    session.tick();
    expect(session.fatigue.value, lessThan(100.0));
    expect(session.status, isA<FoggTraveling>());
  });

  test('GameSession sleep recupera fatiga a 100', () {
    var now = DateTime.utc(2026, 1, 1, 12);
    final te = TimeEngine(startUtc: now, timeScale: 1.0, clock: () => now);
    final bs = BudgetService(initial: 100000);
    const from = FoggCity(name: 'Londres', lat: 51.5, lng: -0.1, order: 0, timezone: 'Europe/London');
    const to = FoggCity(name: 'París', lat: 48.8, lng: 2.3, order: 1, timezone: 'Europe/Paris');
    final session = GameSession(timeEngine: te, budget: bs, cities: [from, to]);
    session.startLeg(
      from: from,
      to: to,
      vehicle: const VehicleOption(
        mode: TransportMode.train,
        duration: Duration(hours: 40),
        price: 1000,
        sleeper: false,
      ),
    );
    now = now.add(const Duration(hours: 30));
    session.tick();
    expect(session.fatigue.value, 0.0);
    session.sleep();
    expect(session.fatigue.value, 100.0);
  });

  test('GameSession startLeg lanza SleepRequiredException si mustSleep', () {
    var now = DateTime.utc(2026, 1, 1, 12);
    final te = TimeEngine(startUtc: now, timeScale: 1.0, clock: () => now);
    final bs = BudgetService(initial: 100000);
    const from = FoggCity(name: 'Londres', lat: 51.5, lng: -0.1, order: 0, timezone: 'Europe/London');
    const to = FoggCity(name: 'París', lat: 48.8, lng: 2.3, order: 1, timezone: 'Europe/Paris');
    const to2 = FoggCity(name: 'Estambul', lat: 41.0, lng: 29.0, order: 2, timezone: 'Europe/Istanbul');
    final session = GameSession(timeEngine: te, budget: bs, cities: [from, to, to2]);
    session.startLeg(
      from: from,
      to: to,
      vehicle: const VehicleOption(
        mode: TransportMode.train,
        duration: Duration(hours: 40),
        price: 1000,
        sleeper: false,
      ),
    );
    now = now.add(const Duration(hours: 30));
    session.tick();
    expect(session.fatigue.value, 0.0);
    expect(
      () => session.startLeg(
        from: to,
        to: to2,
        vehicle: const VehicleOption(
          mode: TransportMode.train,
          duration: Duration(hours: 2),
          price: 100,
          sleeper: false,
        ),
      ),
      throwsA(isA<SleepRequiredException>()),
    );
    expect(bs.balance, 99000);
  });

  test('startLeg guarda la geometría real en el tramo', () {
    var now = DateTime.utc(2026, 1, 1, 12);
    final te = TimeEngine(startUtc: now, timeScale: 1.0, clock: () => now);
    final bs = BudgetService(initial: 100000);
    const from = FoggCity(name: 'Origen', lat: 0, lng: 0, order: 0, timezone: 'UTC');
    const to = FoggCity(name: 'Destino', lat: 4, lng: 10, order: 1, timezone: 'UTC');
    final session = GameSession(timeEngine: te, budget: bs, cities: [from, to]);

    session.startLeg(
      from: from,
      to: to,
      vehicle: const VehicleOption(
        mode: TransportMode.ship,
        duration: Duration(hours: 2),
        price: 1000,
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

    final path = session.currentLeg!.path;
    expect(path, isNotNull);
    expect(path!.points.length, 3);
    expect(path.positionAt(0).longitude, closeTo(0, 1e-9));
    expect(path.positionAt(1).longitude, closeTo(10, 1e-9));
  });

  test('sin ruta real el tramo dibuja una recta de origen a destino', () {
    var now = DateTime.utc(2026, 1, 1, 12);
    final te = TimeEngine(startUtc: now, timeScale: 1.0, clock: () => now);
    final bs = BudgetService(initial: 100000);
    const from = FoggCity(name: 'Origen', lat: 0, lng: 0, order: 0, timezone: 'UTC');
    const to = FoggCity(name: 'Destino', lat: 4, lng: 10, order: 1, timezone: 'UTC');
    final session = GameSession(timeEngine: te, budget: bs, cities: [from, to]);

    session.startLeg(
      from: from,
      to: to,
      vehicle: const VehicleOption(
        mode: TransportMode.foot,
        duration: Duration(hours: 2),
        price: 1000,
      ),
    );

    final path = session.currentLeg!.path;
    expect(path, isNotNull);
    expect(path!.points.length, 2);
    expect(path.positionAt(0).longitude, closeTo(0, 1e-9));
    expect(path.positionAt(1).longitude, closeTo(10, 1e-9));
  });

  test('el tramo recorrido pasa al historial', () {
    var now = DateTime.utc(2026, 1, 1, 12);
    final te = TimeEngine(startUtc: now, timeScale: 1.0, clock: () => now);
    final bs = BudgetService(initial: 100000);
    const from = FoggCity(name: 'Origen', lat: 0, lng: 0, order: 0, timezone: 'UTC');
    const to = FoggCity(name: 'Destino', lat: 4, lng: 10, order: 1, timezone: 'UTC');
    final session = GameSession(timeEngine: te, budget: bs, cities: [from, to]);

    expect(session.completedLegs, isEmpty);

    session.startLeg(
      from: from,
      to: to,
      vehicle: const VehicleOption(
        mode: TransportMode.train,
        duration: Duration(hours: 2),
        price: 1000,
      ),
    );
    now = now.add(const Duration(hours: 12));
    session.tick();

    expect(session.completedLegs.length, 1);
    expect(session.completedLegs.first.to.name, 'Destino');
    expect(session.currentLeg, isNull);
  });
}
