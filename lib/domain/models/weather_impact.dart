import '../entities/transport_mode.dart';
import 'weather_snapshot.dart';

/// Impacto meteorológico sobre un vehículo: retraso y/o cancelación.
class WeatherImpact {
  const WeatherImpact({
    this.delay = Duration.zero,
    this.cancelled = false,
    this.reason,
  });

  final Duration delay;
  final bool cancelled;
  final String? reason;

  /// Calcula el impacto para [mode] usando el peor de [origin]/[destination].
  static WeatherImpact forMode(
    TransportMode mode,
    WeatherSnapshot origin,
    WeatherSnapshot destination,
    DateTime departureUtc,
    DateTime arrivalUtc,
  ) {
    final originImpact = _forSnapshot(mode, origin);
    final destImpact = _forSnapshot(mode, destination);

    var cancelled = false;
    String? reason;
    Duration delay = Duration.zero;

    for (final impact in [originImpact, destImpact]) {
      if (impact.cancelled && !cancelled) {
        cancelled = true;
        reason = impact.reason;
      }
      if (impact.delay > delay) delay = impact.delay;
    }

    if (cancelled) {
      return WeatherImpact(cancelled: true, reason: reason);
    }
    return WeatherImpact(delay: delay);
  }

  static WeatherImpact _forSnapshot(TransportMode mode, WeatherSnapshot w) {
    String? cancelReason;
    switch (mode) {
      case TransportMode.ship:
        if (w.windSpeedKmh >= 63) {
          cancelReason = 'Viento >=63 km/h';
        } else if (w.windGustsKmh >= 75) {
          cancelReason = 'Rafagas >=75 km/h';
        } else if (w.visibilityM < 926) {
          cancelReason = 'Visibilidad <926 m';
        } else if (w.weatherCode == 95 ||
            w.weatherCode == 96 ||
            w.weatherCode == 99) {
          cancelReason = 'Tormenta';
        } else if (w.precipitationMm > 20) {
          cancelReason = 'Precipitacion >20 mm/h';
        }
        break;
      case TransportMode.train:
        if (w.snowDepthM > 0.10) {
          cancelReason = 'Nieve >0.10 m';
        } else if (w.temperatureC != null &&
            (w.temperatureC! < -20 || w.temperatureC! > 45)) {
          cancelReason = 'Temperatura extrema';
        } else if (w.windSpeedKmh >= 100) {
          cancelReason = 'Viento >=100 km/h';
        } else if (w.visibilityM < 500) {
          cancelReason = 'Visibilidad <500 m';
        } else if (w.weatherCode == 95 ||
            w.weatherCode == 96 ||
            w.weatherCode == 99) {
          cancelReason = 'Tormenta';
        } else if (w.precipitationMm > 20) {
          cancelReason = 'Precipitacion >20 mm/h';
        }
        break;
      case TransportMode.car:
        if (w.visibilityM < 200) {
          cancelReason = 'Visibilidad <200 m';
        } else if (w.snowDepthM > 0.20) {
          cancelReason = 'Nieve >0.20 m';
        } else if (w.windSpeedKmh >= 120) {
          cancelReason = 'Viento >=120 km/h';
        } else if (w.precipitationMm > 30) {
          cancelReason = 'Precipitacion >30 mm/h';
        } else if (w.temperatureC != null &&
            (w.temperatureC! < -25 || w.temperatureC! > 45)) {
          cancelReason = 'Temperatura extrema';
        }
        break;
      default:
        break;
    }

    if (cancelReason != null) {
      return WeatherImpact(cancelled: true, reason: cancelReason);
    }

    final headwind = w.windSpeedKmh;
    double hours = 0;
    switch (mode) {
      case TransportMode.ship:
        hours = headwind * 0.06;
        if (hours > 6) hours = 6;
        break;
      case TransportMode.train:
        hours = headwind * 0.03;
        if (hours > 3) hours = 3;
        break;
      case TransportMode.car:
        hours = headwind * 0.02;
        if (hours > 2) hours = 2;
        break;
      default:
        hours = 0;
        break;
    }

    return WeatherImpact(
      delay: Duration(microseconds: (hours * 3600000000).round()),
    );
  }
}
