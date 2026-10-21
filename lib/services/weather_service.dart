import 'dart:convert';
import 'dart:io';

import '../domain/models/weather_snapshot.dart';

class WeatherService {
  WeatherService({HttpClient? client}) : _client = client ?? HttpClient();

  final HttpClient _client;
  final Map<String, WeatherSnapshot> _cache = <String, WeatherSnapshot>{};

  Future<WeatherSnapshot> fetch(double lat, double lng, DateTime atUtc) async {
    final utc = atUtc.toUtc();
    final key = '$lat|$lng|${utc.toIso8601String().substring(0, 13)}';
    final cached = _cache[key];
    if (cached != null) return cached;

    try {
      final uri = Uri.parse(
        'https://api.open-meteo.com/v1/forecast'
        '?latitude=$lat&longitude=$lng'
        '&hourly=temperature_2m,wind_speed_10m,precipitation,weather_code'
        '&timezone=UTC',
      );
      final request = await _client.getUrl(uri);
      final response = await request.close();
      if (response.statusCode != 200) {
        return _neutral(utc);
      }
      final body = await response.transform(utf8.decoder).join();
      final json = jsonDecode(body) as Map<String, dynamic>;
      final hourly = json['hourly'] as Map<String, dynamic>?;
      if (hourly == null) return _neutral(utc);
      final times = (hourly['time'] as List?)?.cast<String>() ?? const [];
      final temps = (hourly['temperature_2m'] as List?) ?? const [];
      final winds = (hourly['wind_speed_10m'] as List?) ?? const [];
      final precips = (hourly['precipitation'] as List?) ?? const [];
      final codes = (hourly['weather_code'] as List?) ?? const [];

      if (times.isEmpty) return _neutral(utc);

      var bestIndex = 0;
      var bestDiff = double.infinity;
      for (var i = 0; i < times.length; i++) {
        DateTime parsed;
        try {
          parsed = DateTime.parse(times[i]).toUtc();
        } catch (_) {
          continue;
        }
        final diff = (parsed.difference(utc).inMinutes).abs().toDouble();
        if (diff < bestDiff) {
          bestDiff = diff;
          bestIndex = i;
        }
      }

      double? temp;
      final rawTemp = bestIndex < temps.length ? temps[bestIndex] : null;
      if (rawTemp is num) temp = rawTemp.toDouble();

      double wind = 0;
      final rawWind = bestIndex < winds.length ? winds[bestIndex] : null;
      if (rawWind is num) wind = rawWind.toDouble();

      double precip = 0;
      final rawPrecip = bestIndex < precips.length ? precips[bestIndex] : null;
      if (rawPrecip is num) precip = rawPrecip.toDouble();

      int code = 0;
      final rawCode = bestIndex < codes.length ? codes[bestIndex] : null;
      if (rawCode is num) code = rawCode.toInt();

      String? condition;
      if (code >= 95) {
        condition = 'storm';
      } else if (precip >= 5) {
        condition = 'storm';
      } else if (wind >= 40) {
        condition = 'windy';
      } else {
        condition = 'clear';
      }

      final snapshot = WeatherSnapshot(
        timestampUtc: utc,
        temperatureC: temp,
        condition: condition,
        windSpeedKmh: wind,
        precipitationMm: precip,
        weatherCode: code,
      );
      _cache[key] = snapshot;
      return snapshot;
    } catch (_) {
      return _neutral(utc);
    }
  }

  WeatherSnapshot _neutral(DateTime utc) {
    return WeatherSnapshot(timestampUtc: utc);
  }
}
