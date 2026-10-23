import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

/// Geometría de un trayecto — puntos, distancia acumulada e interpolación.
///
/// Objeto de valor inmutable. Envuelve la geometría que devuelve el catálogo
/// de rutas (`[lng, lat]` por vértice) y ofrece:
///
/// - medida por distancia Haversine **acumulada** (no por índice de vértice:
///   la densidad de vértices es irregular y el reparto por índice daría
///   saltos de velocidad);
/// - longitudes **desenrolladas** con arco más corto (`Δlng` normalizado a
///   ±180°) para que el cruce del antimeridiano no altere la distancia ni la
///   interpolación;
/// - corte de la polilínea en el meridiano para dibujar sin la línea
///   horizontal parasite que cruzaría el mapa entero.
class RoutePath {
  const RoutePath._({
    required this.points,
    required this.cumulativeKm,
    required List<double> unwrappedLng,
  }) : _unwrappedLng = unwrappedLng;

  /// Puntos en coordenadas reales tal como vienen del catálogo
  /// (`lng` en [-180, 180]).
  final List<LatLng> points;

  /// Distancia Haversine acumulada en km. `cumulativeKm.last` es el total.
  final List<double> cumulativeKm;

  /// Longitudes desenrolladas (arco más corto) — interno, para medir e
  /// interpolar sin saltos de 360°.
  final List<double> _unwrappedLng;

  /// Distancia total del trayecto en km.
  double get totalKm => cumulativeKm.isEmpty ? 0 : cumulativeKm.last;

  /// Construye el trayecto desde la geometría del catálogo (`[lng, lat]`).
  ///
  /// Descarta vértices no numéricos o fuera de rango (`|lat| > 90`,
  /// `|lng| > 180`). Si quedan menos de 2 puntos válidos devuelve `null`:
  /// una geometría degenerada no es un trayecto.
  static RoutePath? fromGeometry(List<List<double>> geometry) {
    final pts = <LatLng>[];
    for (final coord in geometry) {
      if (coord.length < 2) continue;
      final lng = coord[0];
      final lat = coord[1];
      if (!lng.isFinite || !lat.isFinite) continue;
      if (lat.abs() > 90 || lng.abs() > 180) continue;
      pts.add(LatLng(lat, lng));
    }
    if (pts.length < 2) return null;
    return _build(pts);
  }

  /// Tramos sin ruta real (mocks): recta de origen a destino.
  factory RoutePath.straight(LatLng from, LatLng to) => _build([from, to]);

  static RoutePath _build(List<LatLng> pts) {
    final unwrapped = <double>[];
    final cumulative = <double>[];
    var acc = 0.0;
    for (var i = 0; i < pts.length; i++) {
      if (i == 0) {
        unwrapped.add(pts[i].longitude);
        cumulative.add(0);
        continue;
      }
      final delta = _shortArcDelta(pts[i - 1].longitude, pts[i].longitude);
      unwrapped.add(unwrapped[i - 1] + delta);
      acc += _haversine(
        pts[i - 1].latitude,
        pts[i - 1].longitude,
        pts[i].latitude,
        pts[i].longitude,
        delta,
      );
      cumulative.add(acc);
    }
    return RoutePath._(
      points: List<LatLng>.unmodifiable(pts),
      cumulativeKm: List<double>.unmodifiable(cumulative),
      unwrappedLng: List<double>.unmodifiable(unwrapped),
    );
  }

  /// Punto sobre la ruta al progreso dado (0..1), por distancia acumulada.
  ///
  /// La longitud devuelta está normalizada a `[-180, 180)`.
  LatLng positionAt(double progress) {
    if (points.isEmpty) return const LatLng(0, 0);
    if (points.length == 1) return points.first;
    final p = progress.clamp(0.0, 1.0);
    if (totalKm <= 0) return points.first;

    final target = p * totalKm;
    final i = _segmentIndex(target);
    final segLen = cumulativeKm[i + 1] - cumulativeKm[i];
    final t = segLen <= 0 ? 0.0 : ((target - cumulativeKm[i]) / segLen).clamp(0.0, 1.0);

    final lat = points[i].latitude +
        t * (points[i + 1].latitude - points[i].latitude);
    final lng = _unwrappedLng[i] + t * (_unwrappedLng[i + 1] - _unwrappedLng[i]);
    return LatLng(lat, _normalizeLng(lng));
  }

  /// Divide el trayecto en la parte ya recorrida y la pendiente.
  ///
  /// Ambas listas incluyen el punto exacto del corte ([positionAt]) para que
  /// las dos mitades encajen sin hueco ni solape.
  ({List<LatLng> traveled, List<LatLng> pending}) splitAt(double progress) {
    if (points.isEmpty) return (traveled: const [], pending: const []);
    if (points.length == 1) {
      return (traveled: List<LatLng>.unmodifiable([points.first]), pending: const []);
    }
    final p = progress.clamp(0.0, 1.0);
    if (totalKm <= 0 || p <= 0) {
      return (
        traveled: List<LatLng>.unmodifiable([points.first]),
        pending: List<LatLng>.unmodifiable(points),
      );
    }
    if (p >= 1) {
      return (
        traveled: List<LatLng>.unmodifiable(points),
        pending: const [],
      );
    }

    final target = p * totalKm;
    final i = _segmentIndex(target);
    final cut = positionAt(p);

    final traveled = <LatLng>[...points.sublist(0, i + 1)];
    if (!_samePoint(traveled.last, cut)) traveled.add(cut);

    final pending = <LatLng>[cut];
    if (!_samePoint(points[i + 1], cut)) pending.add(points[i + 1]);
    pending.addAll(points.sublist(i + 2));

    return (
      traveled: List<LatLng>.unmodifiable(traveled),
      pending: List<LatLng>.unmodifiable(pending),
    );
  }

  /// Segmentos listos para dibujar, cortados en el antimeridiano.
  List<List<LatLng>> renderSegments() => splitAtAntimeridian(points);

  /// Corta una polilínea en el meridiano.
  ///
  /// Cada sub-lista es una polilínea continua: ninguna contiene a la vez `+180`
  /// y `-180`, ni un salto de longitud mayor de 180° entre vértices.
  ///
  /// Cuando el corte no cae en un vértice, la latitud del corte se interpola
  /// en Y Mercator (misma técnica que `FoggRoute.polylineSegments`) para que
  /// ambos segmentos tengan la misma pendiente en pantalla.
  static List<List<LatLng>> splitAtAntimeridian(List<LatLng> pts) {
    if (pts.isEmpty) return [];
    if (pts.length == 1) return [List<LatLng>.unmodifiable(pts)];

    final segments = <List<LatLng>>[];
    var current = <LatLng>[pts.first];
    segments.add(current);

    for (var i = 1; i < pts.length; i++) {
      final prev = pts[i - 1];
      final curr = pts[i];
      final rawDelta = curr.longitude - prev.longitude;

      if (rawDelta.abs() > 180) {
        // La dirección del cruce la decide el arco más corto: si el recorrido
        // va hacia el este, el tramo anterior cierra en +180 y el siguiente
        // abre en -180 (y al revés si va hacia el oeste).
        final eastward = _shortArcDelta(prev.longitude, curr.longitude) > 0;
        final t = _crossingFraction(prev, curr, eastward);
        final lat = t <= 0
            ? prev.latitude
            : (t >= 1
                ? curr.latitude
                : _interpolateLatMercator(prev.latitude, curr.latitude, t));
        final closeLng = eastward ? 180.0 : -180.0;
        final openLng = eastward ? -180.0 : 180.0;
        if (!_samePoint(current.last, LatLng(lat, closeLng))) {
          current.add(LatLng(lat, closeLng));
        }
        current = <LatLng>[LatLng(lat, openLng)];
        segments.add(current);
      }

      if (!_samePoint(current.last, curr)) current.add(curr);
    }

    return segments
        .map((s) => List<LatLng>.unmodifiable(s))
        .toList(growable: false);
  }

  /// Fracción del tramo [a]→[b] donde se cruza el meridiano.
  ///
  /// Si un extremo está exactamente en ±180, el corte cae en ese vértice.
  static double _crossingFraction(LatLng a, LatLng b, bool eastward) {
    if (a.longitude.abs() == 180) return 0;
    if (b.longitude.abs() == 180) return 1;
    if (eastward) {
      // Arco: (180 - a.lng) + (b.lng + 180).
      final arc = 360 + b.longitude - a.longitude;
      return arc <= 0 ? 0 : (180 - a.longitude) / arc;
    }
    // Arco: (a.lng + 180) + (b.lng + 180).
    final arc = a.longitude + b.longitude + 360;
    return arc <= 0 ? 1 : (a.longitude + 180) / arc;
  }

  /// Índice del segmento `[i, i+1]` que contiene la distancia [target].
  int _segmentIndex(double target) {
    var lo = 0;
    var hi = cumulativeKm.length - 1;
    while (lo < hi - 1) {
      final mid = (lo + hi) >> 1;
      if (cumulativeKm[mid] <= target) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    return lo.clamp(0, cumulativeKm.length - 2);
  }

  static bool _samePoint(LatLng a, LatLng b) =>
      a.latitude == b.latitude && a.longitude == b.longitude;

  /// Diferencia de longitud por el arco más corto, en (-180, 180].
  static double _shortArcDelta(double fromLng, double toLng) {
    var d = (toLng - fromLng) % 360.0;
    if (d > 180) d -= 360;
    if (d <= -180) d += 360;
    return d;
  }

  /// Normaliza una longitud al intervalo `[-180, 180)`.
  static double _normalizeLng(double lng) {
    var v = (lng + 180.0) % 360.0;
    if (v < 0) v += 360.0;
    return v - 180.0;
  }

  static double _haversine(
    double lat1,
    double lng1,
    double lat2,
    double lng2,
    double lngDelta,
  ) {
    const r = 6371.0;
    final dLat = (lat2 - lat1) * math.pi / 180.0;
    final dLng = lngDelta * math.pi / 180.0;
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1 * math.pi / 180.0) *
            math.cos(lat2 * math.pi / 180.0) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return r * c;
  }

  // --- Mercator (EPSG:3857) — para el corte en el meridiano ---

  static const double _maxMercatorLat = 85.05112878;

  static double _latToMercatorY(double lat) {
    final clamped = lat.clamp(-_maxMercatorLat, _maxMercatorLat);
    final rad = clamped * math.pi / 180.0;
    return math.log(math.tan(math.pi / 4 + rad / 2));
  }

  static double _mercatorYToLat(double y) {
    final latRad = 2 * math.atan(math.exp(y)) - math.pi / 2;
    return latRad * 180.0 / math.pi;
  }

  static double _interpolateLatMercator(double lat1, double lat2, double t) {
    final y = _latToMercatorY(lat1) +
        t * (_latToMercatorY(lat2) - _latToMercatorY(lat1));
    return _mercatorYToLat(y);
  }
}
