import 'dart:math' as math;

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

  // ---------------------------------------------------------------------------
  // Helpers Mercator (EPSG:3857) — Opción B
  // ---------------------------------------------------------------------------

  static const double _maxMercatorLat = 85.05112878;

  static double _clampLat(double lat) =>
      lat.clamp(-_maxMercatorLat, _maxMercatorLat);

  /// Convierte latitud a Y Mercator (Web Mercator).
  /// y = ln(tan(π/4 + lat_rad/2))
  static double _latToMercatorY(double lat) {
    final clamped = _clampLat(lat);
    final rad = clamped * math.pi / 180.0;
    return math.log(math.tan(math.pi / 4 + rad / 2));
  }

  /// Convierte Y Mercator de vuelta a latitud en grados.
  static double _mercatorYToLat(double y) {
    final latRad = 2 * math.atan(math.exp(y)) - math.pi / 2;
    return latRad * 180.0 / math.pi;
  }

  /// Polyline derivado — compatibilidad legacy (aplanado).
  /// Para cualquier tramo donde lng decrece (cruce antimeridiano hacia el este),
  /// inserta quiebre en 180/-180 con lat interpolada en Y Mercator para que
  /// ambas semirrectas tengan idéntica pendiente en pantalla (Opción B).
  /// Preferir [polylineSegments] para dibujar sin segmento parásito 180→-180.
  List<LatLng> get polyline => polylineSegments.expand((s) => s).toList();

  /// Segmentos de polyline sin salto parásito.
  /// Cada sub-lista es un Polyline continuo; cruces antimeridiano generan nuevo segmento.
  /// Usa interpolación en Y Mercator para pendiente visual idéntica (Opción B).
  List<List<LatLng>> get polylineSegments {
    if (cities.isEmpty) return [];
    final segments = <List<LatLng>>[];
    var current = <LatLng>[LatLng(cities.first.lat, cities.first.lng)];
    segments.add(current);

    double offset = 0;
    double prevUnwrappedLng = cities.first.lng;

    for (var i = 1; i < cities.length; i++) {
      final currRealLng = cities[i].lng;
      var currUnwrapped = currRealLng + offset;
      if (currUnwrapped <= prevUnwrappedLng) {
        currUnwrapped += 360;
        offset += 360;
      }
      final prevCity = cities[i - 1];
      final currCity = cities[i];
      final prevLat = prevCity.lat;
      final currLat = currCity.lat;

      final prevWrap = ((prevUnwrappedLng + 180) / 360).floor();
      final currWrap = ((currUnwrapped + 180) / 360).floor();

      if (prevWrap != currWrap) {
        // Puede cruzar múltiples antimeridianos si Δlng >360 (futuro loop 80 días).
        // Iterar cada meridiano 180 + k*360 entre prev y curr.
        final prevY = _latToMercatorY(prevLat);
        final currY = _latToMercatorY(currLat);
        for (var k = prevWrap; k < currWrap; k++) {
          final antimeridianLng = 180 + k * 360;
          final t = (antimeridianLng - prevUnwrappedLng) /
              (currUnwrapped - prevUnwrappedLng);
          final yAt = prevY + t * (currY - prevY);
          final latAt180 = _mercatorYToLat(yAt);
          // Cierra segmento actual en 180
          current.add(LatLng(latAt180, 180));
          // Nuevo segmento empieza en -180
          current = <LatLng>[LatLng(latAt180, -180)];
          segments.add(current);
        }
      }
      current.add(LatLng(currCity.lat, currCity.lng));
      prevUnwrappedLng = currUnwrapped;
    }
    return segments;
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

/// Ruta extendida — mock original + salto Japón→costa oeste EEUU→Nueva York→gabinete Phileas.
/// Mantiene las 6 ciudades originales y reemplaza el último salto directo por:
/// Tokio (139.65) → San Francisco (-122.41, lng_u 237.58) → Nueva York (-74.00, lng_u 285.99) → Savile Row (-0.14, lng_u 359.85).
/// Un único cruce antimeridiano en Tokio→SF (el resto ya en hemisferio oeste desenrollado).
const extendedFoggRoute = FoggRoute(cities: [
  FoggCity(name: 'Londres', lat: 51.5072, lng: -0.1276, order: 0),
  FoggCity(name: 'París', lat: 48.8566, lng: 2.3522, order: 1),
  FoggCity(name: 'Estambul', lat: 41.0082, lng: 28.9784, order: 2),
  FoggCity(name: 'Bombay', lat: 19.0760, lng: 72.8777, order: 3),
  FoggCity(name: 'Tokio', lat: 35.6762, lng: 139.6503, order: 4),
  FoggCity(name: 'San Francisco', lat: 37.7749, lng: -122.4194, order: 5),
  FoggCity(name: 'Nueva York', lat: 40.7128, lng: -74.0060, order: 6),
  FoggCity(name: 'Savile Row', lat: 51.5107, lng: -0.1410, order: 7),
]);
