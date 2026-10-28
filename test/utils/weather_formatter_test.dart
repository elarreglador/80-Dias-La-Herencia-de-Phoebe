import 'package:flutter_test/flutter_test.dart';
import 'package:pf/domain/models/weather_snapshot.dart';
import 'package:pf/utils/weather_formatter.dart';

void main() {
  group('formatWeatherSummary', () {
    test('devuelve null si no hay datos relevantes', () {
      final snap = WeatherSnapshot(
        timestampUtc: DateTime.utc(2026, 1, 1),
        windSpeedKmh: 10,
        precipitationMm: 0,
        snowfallCm: 0,
        snowDepthM: 0,
      );
      expect(formatWeatherSummary(snap), isNull);
    });

    test('formatea temperatura y condición clear traducida', () {
      final snap = WeatherSnapshot(
        timestampUtc: DateTime.utc(2026, 1, 1),
        temperatureC: 18.5,
        condition: 'clear',
      );
      expect(formatWeatherSummary(snap), '19°C · Despejado');
    });

    test('incluye viento si supera 30 km/h', () {
      final snap = WeatherSnapshot(
        timestampUtc: DateTime.utc(2026, 1, 1),
        temperatureC: 20.0,
        condition: 'windy',
        windSpeedKmh: 45.0,
      );
      expect(formatWeatherSummary(snap), '20°C · Ventoso · 💨 45 km/h');
    });

    test('omite viento si <= 30 km/h', () {
      final snap = WeatherSnapshot(
        timestampUtc: DateTime.utc(2026, 1, 1),
        temperatureC: 15.0,
        condition: 'windy',
        windSpeedKmh: 25.0,
      );
      expect(formatWeatherSummary(snap), '15°C · Ventoso');
    });

    test('incluye lluvia y nieve cuando > 0', () {
      final snap = WeatherSnapshot(
        timestampUtc: DateTime.utc(2026, 1, 1),
        temperatureC: 2.0,
        condition: 'storm',
        precipitationMm: 5.0,
        snowfallCm: 2.0,
      );
      expect(formatWeatherSummary(snap), '2°C · Tormenta · 🌧️ · ❄️');
    });
  });
}
