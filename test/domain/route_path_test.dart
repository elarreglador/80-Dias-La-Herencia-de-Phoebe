import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:pf/domain/models/route_path.dart';

/// Distancia Haversine en km (referencia independiente del modelo).
double haversineKm(LatLng a, LatLng b) {
  const r = 6371.0;
  const d2r = math.pi / 180.0;
  final dLat = (b.latitude - a.latitude) * d2r;
  final dLng = (b.longitude - a.longitude) * d2r;
  final h = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(a.latitude * d2r) *
          math.cos(b.latitude * d2r) *
          math.sin(dLng / 2) *
          math.sin(dLng / 2);
  return 2 * r * math.atan2(math.sqrt(h), math.sqrt(1 - h));
}

/// Distancia recorrida sobre la polilínea hasta el punto [p] (proyección
/// sobre el segmento más cercano). Sirve para comprobar la monotonía.
double arcKmAt(RoutePath path, LatLng p) {
  var best = double.infinity;
  var bestArc = 0.0;
  for (var i = 0; i < path.points.length - 1; i++) {
    final a = path.points[i];
    final b = path.points[i + 1];
    var dLng = b.longitude - a.longitude;
    while (dLng > 180) {
      dLng -= 360;
    }
    while (dLng < -180) {
      dLng += 360;
    }
    final midLat = (a.latitude + b.latitude) / 2 * 3.141592653589793 / 180;
    final dx = dLng * (midLat.abs() < 1.5 ? 1 : 0.5);
    final dy = b.latitude - a.latitude;
    var pdx = p.longitude - a.longitude;
    while (pdx > 180) {
      pdx -= 360;
    }
    while (pdx < -180) {
      pdx += 360;
    }
    final pdy = p.latitude - a.latitude;
    final len2 = dx * dx + dy * dy;
    final t = len2 <= 0 ? 0.0 : ((pdx * dx + pdy * dy) / len2).clamp(0.0, 1.0);
    final qx = pdx - t * dx;
    final qy = pdy - t * dy;
    final dist = (qx * qx + qy * qy);
    if (dist < best) {
      best = dist;
      bestArc = path.cumulativeKm[i] +
          t * (path.cumulativeKm[i + 1] - path.cumulativeKm[i]);
    }
  }
  return bestArc;
}

void main() {
  group('RoutePath.fromGeometry', () {
    test('devuelve null si quedan menos de 2 puntos válidos', () {
      expect(RoutePath.fromGeometry(const []), isNull);
      expect(RoutePath.fromGeometry(const [[1.0, 2.0]]), isNull);
      expect(
        RoutePath.fromGeometry(const [
          [1.0, 2.0],
          [500.0, 91.0],
        ]),
        isNull,
        reason: 'vértices fuera de rango se descartan',
      );
    });

    test('descarta vértices no numéricos o fuera de rango', () {
      final path = RoutePath.fromGeometry(const [
        [1.0, 2.0],
        [999.0, 3.0],
        [double.nan, 4.0],
        [3.0, 4.0],
      ]);
      expect(path, isNotNull);
      expect(path!.points.length, 2);
      expect(path.points.first, const LatLng(2.0, 1.0));
      expect(path.points.last, const LatLng(4.0, 3.0));
    });

    test('la distancia acumulada coincide con el Haversine', () {
      final path = RoutePath.fromGeometry(const [
        [0.0, 0.0],
        [10.0, 0.0],
        [20.0, 0.0],
      ])!;
      final expected = haversineKm(const LatLng(0, 0), const LatLng(0, 10)) +
          haversineKm(const LatLng(0, 10), const LatLng(0, 20));
      expect(path.totalKm, closeTo(expected, 0.5));
      expect(path.cumulativeKm.first, 0);
    });
  });

  group('RoutePath.positionAt', () {
    final straight = RoutePath.fromGeometry(const [
      [0.0, 0.0],
      [10.0, 0.0],
    ])!;

    test('positionAt(0) es el origen y positionAt(1) el destino', () {
      expect(straight.positionAt(0).latitude, closeTo(0, 1e-9));
      expect(straight.positionAt(0).longitude, closeTo(0, 1e-9));
      expect(straight.positionAt(1).latitude, closeTo(0, 1e-9));
      expect(straight.positionAt(1).longitude, closeTo(10, 1e-9));
    });

    test('el punto medio cae en la mitad de la distancia', () {
      final mid = straight.positionAt(0.5);
      expect(mid.longitude, closeTo(5.0, 1e-6));
      expect(mid.latitude, closeTo(0.0, 1e-9));
    });

    test('recorta el progreso fuera de [0,1]', () {
      expect(straight.positionAt(-3).longitude, closeTo(0, 1e-9));
      expect(straight.positionAt(4).longitude, closeTo(10, 1e-9));
    });

    test('la longitud devuelta está normalizada a [-180, 180)', () {
      final crossing = RoutePath.fromGeometry(const [
        [170.0, 10.0],
        [-170.0, 10.0],
      ])!;
      for (var i = 0; i <= 20; i++) {
        final p = crossing.positionAt(i / 20);
        expect(p.longitude, greaterThanOrEqualTo(-180.0));
        expect(p.longitude, lessThan(180.0));
      }
    });

    test('la posición es monótona: avanzar nunca retrocede', () {
      final path = RoutePath.fromGeometry(const [
        [0.0, 0.0],
        [10.0, 0.0],
        [25.0, 5.0],
        [40.0, 12.0],
      ])!;
      var previous = -1.0;
      for (var i = 0; i <= 100; i++) {
        final p = path.positionAt(i / 100);
        final arc = arcKmAt(path, p);
        expect(arc, greaterThanOrEqualTo(previous - 1e-6));
        previous = arc;
      }
    });

    test('con distancia total cero devuelve el primer punto', () {
      final degenerate = RoutePath.fromGeometry(const [
        [5.0, 5.0],
        [5.0, 5.0],
      ])!;
      expect(degenerate.totalKm, 0);
      expect(degenerate.positionAt(0.5).longitude, closeTo(5.0, 1e-9));
    });
  });

  group('RoutePath.renderSegments', () {
    test('una ruta sin cruce devuelve un único segmento', () {
      final path = RoutePath.fromGeometry(const [
        [0.0, 0.0],
        [5.0, 5.0],
      ])!;
      final segments = path.renderSegments();
      expect(segments.length, 1);
      expect(segments.first.length, 2);
    });

    test('el cruce del antimeridiano parte la línea en dos segmentos', () {
      // Caso real del catálogo: Perth (178.90051) → Apia (-180.0).
      final path = RoutePath.fromGeometry(const [
        [178.90051, -31.95224],
        [-180.0, -13.8333],
        [-179.5, -13.5],
      ])!;
      final segments = path.renderSegments();
      expect(segments.length, greaterThan(1));
      for (final seg in segments) {
        final hasBoth = seg.any((p) => p.longitude == 180) &&
            seg.any((p) => p.longitude == -180);
        expect(hasBoth, isFalse,
            reason: 'ninguna polilínea puede contener +180 y -180 a la vez');
      }
    });

    test('ninguna polilínea tiene un salto de longitud mayor de 180°', () {
      final path = RoutePath.fromGeometry(const [
        [170.0, 10.0],
        [-175.0, 12.0],
        [-160.0, 15.0],
      ])!;
      final segments = path.renderSegments();
      expect(segments.length, greaterThan(1));
      for (final seg in segments) {
        for (var i = 1; i < seg.length; i++) {
          final delta = (seg[i].longitude - seg[i - 1].longitude).abs();
          expect(delta, lessThanOrEqualTo(180.0));
        }
      }
    });

    test('la latitud del corte se interpola en Y Mercator', () {
      final path = RoutePath.fromGeometry(const [
        [170.0, 0.0],
        [-170.0, 40.0],
      ])!;
      final segments = path.renderSegments();
      expect(segments.length, 2);
      // El corte no está en un vértice: las latitudes de los extremos del
      // corte deben ser distintas de las de los vértices.
      expect(segments.first.last.latitude, isNot(closeTo(0.0, 1e-6)));
      expect(segments.first.last.latitude, isNot(closeTo(40.0, 1e-6)));
      expect(segments.last.first.latitude, segments.first.last.latitude);
    });

    test('el vértice exactamente en ±180 no se duplica', () {
      final path = RoutePath.fromGeometry(const [
        [178.9, 10.0],
        [-180.0, 10.0],
      ])!;
      final segments = path.renderSegments();
      final flat = segments.expand((s) => s).toList();
      final at180 = flat.where((p) => p.longitude == -180).toList();
      expect(at180.length, 1, reason: 'el vértice -180 no debe duplicarse');
    });
  });

  group('RoutePath.splitAt', () {
    test('las dos mitades se encuentran en el punto de corte', () {
      final path = RoutePath.fromGeometry(const [
        [0.0, 0.0],
        [10.0, 0.0],
        [20.0, 0.0],
      ])!;
      final parts = path.splitAt(0.5);
      expect(parts.traveled.last, parts.pending.first);
      expect(parts.traveled.first, path.points.first);
      expect(parts.pending.last, path.points.last);
    });
  });

  group('RoutePath.straight', () {
    test('une origen y destino', () {
      final path = RoutePath.straight(const LatLng(10, 20), const LatLng(30, 40));
      expect(path.points.length, 2);
      expect(path.positionAt(0).latitude, closeTo(10, 1e-9));
      expect(path.positionAt(1).longitude, closeTo(40, 1e-9));
    });

    test('corta el antimeridiano si el tramo lo cruza', () {
      final path = RoutePath.straight(const LatLng(0, 170), const LatLng(0, -170));
      expect(path.renderSegments().length, 2);
    });
  });
}
