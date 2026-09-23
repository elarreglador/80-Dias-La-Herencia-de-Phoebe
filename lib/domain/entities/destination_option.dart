import 'fogg_city.dart';
import 'transport_mode.dart';

/// Opción de vehículo para un destino concreto — precio y duración mock.
class VehicleOption {
  const VehicleOption({
    required this.mode,
    required this.duration,
    required this.price,
    this.sleeper = false,
    this.note,
  });

  final TransportMode mode;
  final Duration duration;
  final int price; // €
  final bool sleeper;
  final String? note;

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
