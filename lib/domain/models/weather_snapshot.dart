class WeatherSnapshot {
  const WeatherSnapshot({
    required this.timestampUtc,
    this.temperatureC,
    this.condition,
  });

  final DateTime timestampUtc;
  final double? temperatureC;
  final String? condition;
}
