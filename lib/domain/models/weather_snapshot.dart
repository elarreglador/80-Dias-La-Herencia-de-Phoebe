class WeatherSnapshot {
  const WeatherSnapshot({
    required this.timestampUtc,
    this.temperatureC,
    this.condition,
    this.windSpeedKmh = 0,
    this.windDirectionDeg = 0,
    this.windGustsKmh = 0,
    this.visibilityM = 10000,
    this.precipitationMm = 0,
    this.snowfallCm = 0,
    this.snowDepthM = 0,
    this.weatherCode = 0,
  });

  final DateTime timestampUtc;
  final double? temperatureC;
  final String? condition;
  final double windSpeedKmh;
  final double windDirectionDeg;
  final double windGustsKmh;
  final double visibilityM;
  final double precipitationMm;
  final double snowfallCm;
  final double snowDepthM;
  final int weatherCode;
}
