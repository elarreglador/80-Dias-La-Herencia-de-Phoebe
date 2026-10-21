import 'package:flutter_test/flutter_test.dart';

import 'package:pf/domain/entities/transport_mode.dart';
import 'package:pf/domain/models/weather_impact.dart';
import 'package:pf/domain/models/weather_snapshot.dart';

void main() {
  WeatherSnapshot snap({
    double wind = 0,
    double gusts = 0,
    double visibility = 10000,
    double precip = 0,
    double snowDepth = 0,
    double temp = 20,
    int code = 0,
  }) {
    return WeatherSnapshot(
      timestampUtc: DateTime.utc(2026, 1, 1, 12),
      temperatureC: temp,
      windSpeedKmh: wind,
      windGustsKmh: gusts,
      visibilityM: visibility,
      precipitationMm: precip,
      snowDepthM: snowDepth,
      weatherCode: code,
    );
  }

  test('sin viento no hay retraso', () {
    final impact = WeatherImpact.forMode(
      TransportMode.ship,
      snap(),
      snap(),
      DateTime.utc(2026, 1, 1, 12),
      DateTime.utc(2026, 1, 2, 12),
    );
    expect(impact.cancelled, isFalse);
    expect(impact.delay, Duration.zero);
  });

  test('retraso lineal barco', () {
    final impact = WeatherImpact.forMode(
      TransportMode.ship,
      snap(wind: 10),
      snap(),
      DateTime.utc(2026, 1, 1, 12),
      DateTime.utc(2026, 1, 2, 12),
    );
    expect(impact.delay, Duration(minutes: 36));
  });

  test('tope 2h coche', () {
    final impact = WeatherImpact.forMode(
      TransportMode.car,
      snap(wind: 119),
      snap(),
      DateTime.utc(2026, 1, 1, 12),
      DateTime.utc(2026, 1, 2, 12),
    );
    expect(impact.delay, const Duration(hours: 2));
  });

  test('cancelacion barco por viento', () {
    final impact = WeatherImpact.forMode(
      TransportMode.ship,
      snap(wind: 63),
      snap(),
      DateTime.utc(2026, 1, 1, 12),
      DateTime.utc(2026, 1, 2, 12),
    );
    expect(impact.cancelled, isTrue);
  });

  test('peor de origen/destino', () {
    final impact = WeatherImpact.forMode(
      TransportMode.ship,
      snap(wind: 10),
      snap(wind: 50),
      DateTime.utc(2026, 1, 1, 12),
      DateTime.utc(2026, 1, 2, 12),
    );
    expect(impact.delay, Duration(minutes: 180));
  });
}
