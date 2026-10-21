import 'package:flutter_test/flutter_test.dart';

import 'package:pf/domain/entities/fogg_city.dart';
import 'package:pf/domain/entities/fogg_leg.dart';
import 'package:pf/domain/entities/transport_mode.dart';
import 'package:pf/domain/models/travel_event.dart';
import 'package:pf/domain/models/weather_snapshot.dart';
import 'package:pf/services/event_engine.dart';

void main() {
  const from = FoggCity(name: 'A', lat: 0, lng: 0, order: 0, timezone: 'UTC');
  const to = FoggCity(name: 'B', lat: 0, lng: 10, order: 1, timezone: 'UTC');

  FoggLeg leg() => FoggLeg(
        from: from,
        to: to,
        transport: TransportMode.train,
        departureUtc: DateTime.utc(2026, 1, 1, 12),
        arrivalUtc: DateTime.utc(2026, 1, 2, 12),
        price: 100,
      );

  test('sin condiciones adversas devuelve lista vacía', () {
    final engine = EventEngine();
    final weather = WeatherSnapshot(
      timestampUtc: DateTime.utc(2026, 1, 1, 12),
      condition: 'clear',
    );
    expect(engine.roll(leg: leg(), weather: weather), isEmpty);
  });

  test('viento fuerte devuelve DelayEvent', () {
    final engine = EventEngine();
    final weather = WeatherSnapshot(
      timestampUtc: DateTime.utc(2026, 1, 1, 12),
      condition: 'clear',
      windSpeedKmh: 60,
    );
    final events = engine.roll(leg: leg(), weather: weather);
    expect(events.length, 1);
    expect(events.first, isA<DelayEvent>());
    expect((events.first as DelayEvent).hours, 2);
  });

  test('condition windy devuelve DelayEvent', () {
    final engine = EventEngine();
    final weather = WeatherSnapshot(
      timestampUtc: DateTime.utc(2026, 1, 1, 12),
      condition: 'windy',
    );
    final events = engine.roll(leg: leg(), weather: weather);
    expect(events.any((e) => e is DelayEvent), isTrue);
  });

  test('storm condition devuelve StormEvent', () {
    final engine = EventEngine();
    final weather = WeatherSnapshot(
      timestampUtc: DateTime.utc(2026, 1, 1, 12),
      condition: 'storm',
    );
    final events = engine.roll(leg: leg(), weather: weather);
    expect(events.any((e) => e is StormEvent), isTrue);
  });

  test('precipitación alta devuelve StormEvent', () {
    final engine = EventEngine();
    final weather = WeatherSnapshot(
      timestampUtc: DateTime.utc(2026, 1, 1, 12),
      condition: 'clear',
      precipitationMm: 10,
    );
    final events = engine.roll(leg: leg(), weather: weather);
    expect(events.any((e) => e is StormEvent), isTrue);
  });

  test('ambas condiciones devuelve ambos eventos', () {
    final engine = EventEngine();
    final weather = WeatherSnapshot(
      timestampUtc: DateTime.utc(2026, 1, 1, 12),
      condition: 'storm',
      windSpeedKmh: 60,
      precipitationMm: 10,
    );
    final events = engine.roll(leg: leg(), weather: weather);
    expect(events.length, 2);
    expect(events.any((e) => e is DelayEvent), isTrue);
    expect(events.any((e) => e is StormEvent), isTrue);
  });

  test('DelayEvent.applyTo retrasa arrivalUtc', () {
    final l = leg();
    const e = DelayEvent(hours: 2);
    final nl = e.applyTo(l) as FoggLeg;
    expect(nl.arrivalUtc, l.arrivalUtc.add(const Duration(hours: 2)));
  });
}
