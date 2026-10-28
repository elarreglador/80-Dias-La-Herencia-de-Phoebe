import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';

import '../domain/models/weather_snapshot.dart';

class WeatherService {
  WeatherService({HttpClient? client}) : _client = client ?? HttpClient();

  final HttpClient _client;
  final Map<String, WeatherSnapshot> _cache = <String, WeatherSnapshot>{};

  Future<void> _delay(int attempt) async {
    final binding = WidgetsBinding.instance;
    final isTest = binding.runtimeType.toString().contains('Test');
    if (!isTest) {
      await Future.delayed(Duration(milliseconds: 400 * attempt));
    }
  }

  Future<WeatherSnapshot> fetch(double lat, double lng, DateTime atUtc) async {
    final utc = atUtc.toUtc();
    final key = '$lat|$lng|${utc.toIso8601String().substring(0, 13)}';
    final cached = _cache[key];
    if (cached != null) return cached;

    const maxAttempts = 3;
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        final uri = Uri.parse(
          'https://api.open-meteo.com/v1/forecast'
          '?latitude=$lat&longitude=$lng'
          '&hourly=temperature_2m,wind_speed_10m,wind_direction_10m,wind_gusts_10m,visibility,precipitation,snowfall,snow_depth,weather_code'
          '&timezone=UTC',
        );
        final request = await _client.getUrl(uri).timeout(const Duration(seconds: 8));
        final response = await request.close().timeout(const Duration(seconds: 8));
        if (response.statusCode != 200) {
          if (attempt == maxAttempts) return _neutral(utc);
          await _delay(attempt);
          continue;
        }
        final body = await response.transform(utf8.decoder).join();
        final json = jsonDecode(body) as Map<String, dynamic>;
        final hourly = json['hourly'] as Map<String, dynamic>?;
        if (hourly == null) {
          if (attempt == maxAttempts) return _neutral(utc);
          await _delay(attempt);
          continue;
        }
        final times = (hourly['time'] as List?)?.cast<String>() ?? const [];
        final temps = (hourly['temperature_2m'] as List?) ?? const [];
        final winds = (hourly['wind_speed_10m'] as List?) ?? const [];
        final windDirs = (hourly['wind_direction_10m'] as List?) ?? const [];
        final gusts = (hourly['wind_gusts_10m'] as List?) ?? const [];
        final visibilities = (hourly['visibility'] as List?) ?? const [];
        final precips = (hourly['precipitation'] as List?) ?? const [];
        final snowfalls = (hourly['snowfall'] as List?) ?? const [];
        final snowDepths = (hourly['snow_depth'] as List?) ?? const [];
        final codes = (hourly['weather_code'] as List?) ?? const [];

        if (times.isEmpty) {
          if (attempt == maxAttempts) return _neutral(utc);
          await _delay(attempt);
          continue;
        }

        var bestIndex = 0;
        var bestDiff = double.infinity;
        for (var i = 0; i < times.length; i++) {
          DateTime parsed;
          try {
            final raw = times[i];
            parsed = DateTime.parse(raw.endsWith('Z') ? raw : '${raw}Z').toUtc();
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

        double windDir = 0;
        final rawWindDir = bestIndex < windDirs.length ? windDirs[bestIndex] : null;
        if (rawWindDir is num) windDir = rawWindDir.toDouble();

        double gust = 0;
        final rawGust = bestIndex < gusts.length ? gusts[bestIndex] : null;
        if (rawGust is num) gust = rawGust.toDouble();

        double visibility = 10000;
        final rawVis = bestIndex < visibilities.length ? visibilities[bestIndex] : null;
        if (rawVis is num) visibility = rawVis.toDouble();

        double precip = 0;
        final rawPrecip = bestIndex < precips.length ? precips[bestIndex] : null;
        if (rawPrecip is num) precip = rawPrecip.toDouble();

        double snowfall = 0;
        final rawSnow = bestIndex < snowfalls.length ? snowfalls[bestIndex] : null;
        if (rawSnow is num) snowfall = rawSnow.toDouble();

        double snowDepth = 0;
        final rawSnowDepth = bestIndex < snowDepths.length ? snowDepths[bestIndex] : null;
        if (rawSnowDepth is num) snowDepth = rawSnowDepth.toDouble();

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
          windDirectionDeg: windDir,
          windGustsKmh: gust,
          visibilityM: visibility,
          precipitationMm: precip,
          snowfallCm: snowfall,
          snowDepthM: snowDepth,
          weatherCode: code,
        );
        _cache[key] = snapshot;
        return snapshot;
      } catch (_) {
        if (attempt == maxAttempts) {
          return _neutral(utc);
        }
        await _delay(attempt);
      }
    }
    return _neutral(utc);
  }

  WeatherSnapshot fetchSync(double lat, double lng, DateTime atUtc) {
    final utc = atUtc.toUtc();
    final key = '$lat|$lng|${utc.toIso8601String().substring(0, 13)}';
    final cached = _cache[key];
    if (cached != null) return cached;
    // Dispara carga asíncrona para poblar caché sin bloquear.
    fetch(lat, lng, atUtc);
    return _neutral(utc);
  }

  WeatherSnapshot _neutral(DateTime utc) {
    return WeatherSnapshot(timestampUtc: utc);
  }
}
