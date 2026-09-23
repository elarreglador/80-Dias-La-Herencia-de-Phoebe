import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/fogg_city.dart';

/// Petición de foco en el mapa — navega a pestaña Mapa y anima cámara.
///
/// `nonce` fuerza notificación aunque se pulse 2× la misma ciudad (el
/// `Notifier` compararía por identidad si usáramos solo `FoggCity`).
class MapFocusRequest {
  const MapFocusRequest({
    required this.city,
    required this.zoom,
    required this.nonce,
  });

  final FoggCity city;
  final double zoom;
  final int nonce;

  @override
  String toString() => 'MapFocusRequest(city: ${city.name}, zoom: $zoom, nonce: $nonce)';
}

/// Notifier que emite `MapFocusRequest` bajo demanda.
///
/// Consumo: `ref.read(mapFocusProvider.notifier).request(city, zoom: 6.0)`
/// + `ref.read(bottomNavIndexProvider.notifier).state = 0` para cambiar pestaña.
/// `WorldMapWidget` escucha vía `ref.listen(mapFocusProvider, ...)` y anima.
class MapFocusNotifier extends Notifier<MapFocusRequest?> {
  int _nonce = 0;

  @override
  MapFocusRequest? build() => null;

  /// Solicita foco en [city] con [zoom] (defecto 7.0 — zoom medio-alto).
  ///
  /// Cada llamada incrementa `nonce` para que `ref.listen` dispare aunque
  /// la ciudad sea la misma que la anterior. 7.0 muestra la ciudad con
  /// contexto cercano y garantiza `visibleOrders` (≥6 = todos los labels).
  void request(FoggCity city, {double zoom = 7.0}) {
    _nonce++;
    state = MapFocusRequest(city: city, zoom: zoom, nonce: _nonce);
  }

  /// Limpia la petición (opcional, no requerido por flujo actual).
  void clear() => state = null;
}

final mapFocusProvider =
    NotifierProvider<MapFocusNotifier, MapFocusRequest?>(MapFocusNotifier.new);
