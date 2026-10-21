import 'dart:math';

import '../domain/entities/fogg_leg.dart';
import '../domain/models/travel_event.dart';
import '../domain/models/weather_snapshot.dart';

class EventEngine {
  EventEngine({
    this.delayWindKmh = 40,
    this.stormPrecipMm = 5,
    Random? rng,
  }) : _rng = rng;

  final double delayWindKmh;
  final double stormPrecipMm;
  final Random? _rng;

  Random? get rng => _rng;

  List<TravelEvent> roll({
    required FoggLeg leg,
    required WeatherSnapshot weather,
    Random? rng,
  }) {
    final events = <TravelEvent>[];
    final wind = weather.windSpeedKmh;
    final precip = weather.precipitationMm;
    final condition = weather.condition;

    if (wind > delayWindKmh || condition == 'windy') {
      events.add(const DelayEvent(hours: 2));
    }

    if (condition == 'storm' || precip > stormPrecipMm) {
      var severity = 1;
      if (precip > stormPrecipMm * 2 || wind > delayWindKmh * 1.5) {
        severity = 2;
      }
      if (precip > stormPrecipMm * 4) {
        severity = 3;
      }
      events.add(StormEvent(severity: severity, extraFatigue: severity * 5.0));
    }

    return events;
  }
}
