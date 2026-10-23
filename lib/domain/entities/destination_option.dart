import 'fogg_city.dart';
import 'transport_mode.dart';
import '../models/route_entry.dart';
import '../models/weather_impact.dart';

/// Opción de vehículo para un destino concreto — precio y duración mock.
class VehicleOption {
  const VehicleOption({
    required this.mode,
    required this.duration,
    required this.price,
    this.sleeper = false,
    this.note,
    this.departureHour,
    this.departureMinute,
    this.weatherImpact,
    this.route,
  });

  final TransportMode mode;
  final Duration duration;
  final int price; // €
  final bool sleeper;
  final String? note;
  final int? departureHour; // hora local del origen (0-23)
  final int? departureMinute; // minuto local del origen (0-59)
  final WeatherImpact? weatherImpact;

  /// Ruta real del catálogo para este modo — conserva la geometría elegida.
  /// `null` en los vehículos sin ruta real (mocks).
  final RouteEntry? route;

  String get durationLabel {
    final h = duration.inHours;
    final m = duration.inMinutes % 60;
    if (h > 0 && m > 0) return '${h}h ${m}min';
    if (h > 0) return '${h}h';
    return '${m}min';
  }
}

/// Destino candidato con 1-3 vehículos — respeta Regla del Este en factory.
class DestinationOption {
  const DestinationOption({
    required this.city,
    required this.vehicles,
  });

  final FoggCity city;
  final List<VehicleOption> vehicles;
}
