import 'package:flutter_test/flutter_test.dart';

import 'package:pf/services/time_engine.dart';
import 'package:pf/domain/models/fatigue.dart';

void main() {
  test('TimeEngine escala el tiempo real', () {
    var now = DateTime.utc(2026, 1, 1, 12, 0, 0);
    final start = now;
    final engine = TimeEngine(
      startUtc: start,
      timeScale: 60.0,
      clock: () => now,
    );
    expect(engine.now(), start);
    now = start.add(const Duration(minutes: 1));
    expect(engine.now(), start.add(const Duration(hours: 1)));
  });

  test('TimeEngine nextDeparture aplica descanso', () {
    final engine = TimeEngine(startUtc: DateTime.utc(2026, 1, 1));
    final arrival = DateTime.utc(2026, 1, 1, 10);
    expect(
      engine.nextDeparture(arrival),
      arrival.add(const Duration(hours: 8)),
    );
    expect(
      engine.nextDeparture(arrival, sleeper: true),
      arrival.add(const Duration(hours: 5)),
    );
  });

  test('TimeEngine nextScheduledDeparture convierte hora local', () {
    final engine = TimeEngine(startUtc: DateTime.utc(2026, 1, 1));
    final arrival = DateTime.utc(2026, 1, 1, 10);
    final dep = engine.nextScheduledDeparture(
      arrival,
      originTimezone: 'Europe/Paris',
      departureHour: 8,
      departureMinute: 0,
    );
    expect(dep.isUtc, isTrue);
    expect(dep.isAfter(arrival), isTrue);
  });

  test('TimeEngine sleepNeeded calcula horas desde la tasa de recuperacion', () {
    final engine = TimeEngine(startUtc: DateTime.utc(2026, 1, 1));
    expect(
      engine.sleepNeeded(const Fatigue(value: 100), rate: Fatigue.hotelRecoverRate),
      Duration.zero,
    );
    expect(engine.sleepNeeded(const Fatigue(value: 0), rate: Fatigue.hotelRecoverRate).inHours, 8);
    expect(engine.sleepNeeded(const Fatigue(value: 50), rate: Fatigue.sleeperRecoverRate).inHours, 5);
  });
}
