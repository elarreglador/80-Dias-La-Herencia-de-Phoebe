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
  /// Para cualquier tramo donde lng decrece (cruce antimeridiano hacia el este),
  /// inserta quiebre en 180/-180 con lat interpolada para que ambas
  /// semirrectas tengan idéntica pendiente y parezcan una sola línea.
  List<LatLng> get polyline {
    if (cities.isEmpty) return [];
    final points = <LatLng>[];
    // Acumulador de offset para desenrollar longitudes hacia el este
    double offset = 0;
    double prevUnwrappedLng = cities.first.lng;
    points.add(LatLng(cities.first.lat, cities.first.lng));

    for (var i = 1; i < cities.length; i++) {
      final currRealLng = cities[i].lng;
      var currUnwrapped = currRealLng + offset;
      // Si el siguiente punto está al oeste en coordenadas reales, desenrolla
      if (currUnwrapped <= prevUnwrappedLng) {
        currUnwrapped += 360;
        offset += 360;
      }
      final prevCity = cities[i - 1];
      final currCity = cities[i];
      final prevLat = prevCity.lat;
      final currLat = currCity.lat;
      // ¿Cruza el antimeridiano? (unwrapped cruza 180 + k*360)
      // Detecta si el segmento cruza el antimeridiano usando +180 offset
      final prevWrap = ((prevUnwrappedLng + 180) / 360).floor();
      final currWrap = ((currUnwrapped + 180) / 360).floor();
      if (prevWrap != currWrap) {
        // Hay cruce: calcula intersección con 180 + prevWrap*360
        final antimeridianLng = 180 + prevWrap * 360;
        final t = (antimeridianLng - prevUnwrappedLng) / (currUnwrapped - prevUnwrappedLng);
        final latAt180 = prevLat + t * (currLat - prevLat);
        // Normaliza 180 a 180 y -180 para el quiebre finito sin lng>360
        points.add(LatLng(latAt180, 180));
        points.add(LatLng(latAt180, -180));
      }
      // Añade el punto destino con lng real (no unwrapped) para que el marcador coincida
      points.add(LatLng(currCity.lat, currCity.lng));
      prevUnwrappedLng = currUnwrapped;
    }
    return points;
  }

  /// Valida Regla del Este permitiendo salto antimeridiano en cualquier tramo
  /// (p.ej. Tokio→Hawái, Hawái→México, Tokio→Savile Row). Usa longitudes
  /// desenrolladas para que lng pueda crecer más allá de 180.
  static bool _isEastward(List<FoggCity> cities) {
    if (cities.length <= 1) return true;
    double offset = 0;
    double prevUnwrapped = cities.first.lng;
    for (var i = 1; i < cities.length; i++) {
      final currReal = cities[i].lng;
      var currUnwrapped = currReal + offset;
      if (currUnwrapped <= prevUnwrapped) {
        currUnwrapped += 360;
        offset += 360;
        if (currUnwrapped <= prevUnwrapped) return false; // aún no supera ni con wrap
      }
      if (cities[i].order != cities[i - 1].order + 1) return false;
      prevUnwrapped = currUnwrapped;
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
