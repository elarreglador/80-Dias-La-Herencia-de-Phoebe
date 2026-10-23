import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../domain/entities/fogg_status.dart';
import 'game_notifier.dart';

/// Posición actual de Phoebe Fogg — derivada del estado de la partida.
///
/// En ruta: el punto exacto sobre la geometría del tramo, según el
/// progreso que marca el reloj. En ciudad: las coordenadas de la ciudad.
/// Nadie escribe la posición a mano.
final foggPositionProvider = Provider<LatLng?>((ref) {
  final status = ref.watch(gameNotifierProvider);
  final now = ref.watch(timeEngineProvider).now();
  return switch (status) {
    FoggTraveling(leg: final leg) => leg.path?.positionAt(leg.progressAt(now)) ??
        LatLng(leg.from.lat, leg.from.lng),
    FoggArrived(currentCity: final city) => LatLng(city.lat, city.lng),
  };
});

/// Zoom actual del mapa — sincronizado con MapController.
final mapZoomProvider = StateProvider<double>((ref) => 3.0);
