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
  List<LatLng> get polyline => cities.map((c) => LatLng(c.lat, c.lng)).toList();

  static bool _isEastward(List<FoggCity> cities) {
    if (cities.length <= 1) return true;
    for (var i = 1; i < cities.length; i++) {
      if (cities[i].lng <= cities[i - 1].lng) return false;
      if (cities[i].order != cities[i - 1].order + 1) return false;
    }
    return true;
  }
}

/// Mock embebido — MVP 5 ciudades este Londres → París → Estambul → Bombay → Tokio.
const mockFoggRoute = FoggRoute(cities: [
  FoggCity(name: 'Londres', lat: 51.5072, lng: -0.1276, order: 0),
  FoggCity(name: 'París', lat: 48.8566, lng: 2.3522, order: 1),
  FoggCity(name: 'Estambul', lat: 41.0082, lng: 28.9784, order: 2),
  FoggCity(name: 'Bombay', lat: 19.0760, lng: 72.8777, order: 3),
  FoggCity(name: 'Tokio', lat: 35.6762, lng: 139.6503, order: 4),
]);
