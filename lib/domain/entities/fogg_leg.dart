import 'fogg_city.dart';
import 'transport_mode.dart';

/// Tramo activo de Phoebe — origen, destino, transporte y ventana temporal.
class FoggLeg {
  const FoggLeg({
    required this.from,
    required this.to,
    required this.transport,
    required this.departureUtc,
    required this.arrivalUtc,
    required this.price,
    this.sleeper = false,
  });

  final FoggCity from;
  final FoggCity to;
  final TransportMode transport;
  final DateTime departureUtc;
  final DateTime arrivalUtc;
  final int price; // € mock
  final bool sleeper; // permite avanzar de noche (Ciclo Fogg)

  Duration get totalDuration => arrivalUtc.difference(departureUtc);

  Duration remainingAt(DateTime now) {
    final d = arrivalUtc.difference(now);
    return d.isNegative ? Duration.zero : d;
  }

  double progressAt(DateTime now) {
    final total = totalDuration.inSeconds;
    if (total <= 0) return 1.0;
    final elapsed = now.difference(departureUtc).inSeconds.clamp(0, total);
    return elapsed / total;
  }

  @override
  String toString() =>
      'FoggLeg(${from.name}→${to.name} ${transport.name} ${departureUtc.toIso8601String()}→${arrivalUtc.toIso8601String()})';
}
