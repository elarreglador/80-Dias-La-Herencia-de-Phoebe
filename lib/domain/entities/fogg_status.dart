import 'destination_option.dart';
import 'fogg_city.dart';
import 'fogg_leg.dart';

/// Estado actual de Phoebe — viajando o en destino (sealed).
sealed class FoggStatus {
  const FoggStatus();
}

/// Phoebe está en tránsito — muestra cuenta atrás + icono transporte.
class FoggTraveling extends FoggStatus {
  const FoggTraveling({required this.leg});

  final FoggLeg leg;

  /// Tiempo restante hasta destino; zero si ya llegó.
  Duration remainingAt(DateTime now) => leg.remainingAt(now);

  bool isArrivedAt(DateTime now) => remainingAt(now) == Duration.zero;
}

/// Phoebe ha llegado — elige próximo destino (3 ciudades × 1-3 vehículos).
class FoggArrived extends FoggStatus {
  const FoggArrived({
    required this.currentCity,
    required this.options,
  });

  final FoggCity currentCity;
  final List<DestinationOption> options;
}
