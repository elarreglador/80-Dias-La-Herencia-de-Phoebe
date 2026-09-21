import 'package:latlong2/latlong.dart';

import 'fogg_city.dart';

/// Trazado de Phoebe Fogg — lista ordenada de ciudades hacia el este.
class FoggRoute {
  const FoggRoute({required this.cities});

  /// Constructor con validación debug de la Regla del Este.
  factory FoggRoute.validated({required List<FoggCity> cities}) {
    assert(
      _isEastward(cities),
      'Regla del Este violada: cada ciudad debe tener lng > anterior y order consecutivos',
    );
    return FoggRoute(cities: cities);
  }

  final List<FoggCity> cities;

  /// Polyline derivado: LatLng por cada ciudad en orden.
  /// Si el último tramo es wrap (lng decrece), inserta quiebre en 180/-180
  /// para dibujar el corte antimeridiano en mundo finito.
  List<LatLng> get polyline {
    final needsWrap = cities.length >= 2 && cities.last.lng <= cities[cities.length - 2].lng;
    if (!needsWrap) {
      return cities.map((c) => LatLng(c.lat, c.lng)).toList();
    }
    // Corta en antimeridiano: Tokio → 180, -180 → Savile Row
    final base = cities.sublist(0, cities.length - 1).map((c) => LatLng(c.lat, c.lng)).toList();
    final lastLat = cities.last.lat;
    final lastLng = cities.last.lng;
    return [...base, LatLng(lastLat, 180), LatLng(lastLat, -180), LatLng(lastLat, lastLng)];
  }

  /// Valida Regla del Este permitiendo salto de meridiano en el último tramo
  /// (cierre del loop en Savile Row). Para i < n-1 exige lng creciente;
  /// para el último permite wrap añadiendo 360.
  static bool _isEastward(List<FoggCity> cities) {
    if (cities.length <= 1) return true;
    for (var i = 1; i < cities.length; i++) {
      final currLng = cities[i].lng;
      final prevLng = cities[i - 1].lng;
      final isLastWrap = i == cities.length - 1 && currLng <= prevLng;
      final effectiveLng = isLastWrap ? currLng + 360 : currLng;
      if (effectiveLng <= prevLng) return false;
      if (cities[i].order != cities[i - 1].order + 1) return false;
    }
    return true;
  }
}

/// Mock embebido — 6 ciudades este cerrando el loop en Savile Row.
/// Último tramo Tokio (139.65) → Savile Row (-0.141) permite salto antimeridiano.
const mockFoggRoute = FoggRoute(cities: [
  FoggCity(name: 'Londres', lat: 51.5072, lng: -0.1276, order: 0),
  FoggCity(name: 'París', lat: 48.8566, lng: 2.3522, order: 1),
  FoggCity(name: 'Estambul', lat: 41.0082, lng: 28.9784, order: 2),
  FoggCity(name: 'Bombay', lat: 19.0760, lng: 72.8777, order: 3),
  FoggCity(name: 'Tokio', lat: 35.6762, lng: 139.6503, order: 4),
  FoggCity(name: 'Savile Row', lat: 51.5107, lng: -0.1410, order: 5),
]);
