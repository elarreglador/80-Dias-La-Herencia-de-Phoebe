import '../domain/models/weather_snapshot.dart';

/// Formatea un snapshot meteorológico en una línea de resumen legible para UI.
String? formatWeatherSummary(WeatherSnapshot snapshot) {
  final parts = <String>[];
  if (snapshot.temperatureC != null) {
    parts.add('${snapshot.temperatureC!.round()}°C');
  }
  if (snapshot.condition != null) {
    final cond = snapshot.condition!.toLowerCase();
    if (cond == 'clear') {
      parts.add('Despejado');
    } else if (cond == 'windy') {
      parts.add('Ventoso');
    } else if (cond == 'storm') {
      parts.add('Tormenta');
    } else {
      parts.add(snapshot.condition!);
    }
  }
  if (snapshot.windSpeedKmh > 30) {
    parts.add('💨 ${snapshot.windSpeedKmh.round()} km/h');
  }
  if (snapshot.precipitationMm > 0) {
    parts.add('🌧️');
  }
  if (snapshot.snowfallCm > 0 || snapshot.snowDepthM > 0) {
    parts.add('❄️');
  }
  if (parts.isEmpty) return null;
  return parts.join(' · ');
}
