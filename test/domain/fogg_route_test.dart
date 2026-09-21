import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:pf/domain/entities/fogg_city.dart';
import 'package:pf/domain/entities/fogg_route.dart';

/// Helpers Mercator para verificar pendiente idéntica en pantalla (Opción B).
double _latToY(double lat) {
  const maxLat = 85.05112878;
  final clamped = lat.clamp(-maxLat, maxLat);
  final rad = clamped * math.pi / 180.0;
  return math.log(math.tan(math.pi / 4 + rad / 2));
}

void main() {
  group('FoggRoute — Regla del Este', () {
    test('polyline contiene 8 puntos con quiebre antimeridiano (cierra en Savile Row)', () {
      // 6 ciudades + 2 puntos de quiebre 180/-180 en último tramo
      // polyline aplanado mantiene compatibilidad
      expect(mockFoggRoute.polyline.length, 8);
      // Nuevo API segmentado: 2 polylines sin segmento parásito
      expect(mockFoggRoute.polylineSegments.length, 2);
      expect(mockFoggRoute.polylineSegments[0].length, 6); // Londres..Tokio + 180
      expect(mockFoggRoute.polylineSegments[1].length, 2); // -180 + Savile
      expect(mockFoggRoute.cities.length, 6);
      // Verifica quiebre
      expect(mockFoggRoute.polyline[5].longitude, 180);
      expect(mockFoggRoute.polyline[6].longitude, -180);
      expect(mockFoggRoute.polylineSegments[0].last.longitude, 180);
      expect(mockFoggRoute.polylineSegments[1].first.longitude, -180);
      expect(mockFoggRoute.polyline.last.longitude, mockFoggRoute.cities.last.lng);
    });

    test('lng crece hacia el este en orden 0..4 y permite salto final a Savile Row', () {
      for (var i = 1; i < mockFoggRoute.cities.length; i++) {
        if (i == mockFoggRoute.cities.length - 1) {
          final curr = mockFoggRoute.cities[i].lng + 360;
          expect(
            curr,
            greaterThan(mockFoggRoute.cities[i - 1].lng),
            reason: 'Savile Row debe ser alcanzable al este vía salto meridiano',
          );
        } else {
          expect(
            mockFoggRoute.cities[i].lng,
            greaterThan(mockFoggRoute.cities[i - 1].lng),
            reason:
                'Ciudad ${mockFoggRoute.cities[i].name} debe tener lng > ${mockFoggRoute.cities[i - 1].name}',
          );
        }
        expect(mockFoggRoute.cities[i].order, mockFoggRoute.cities[i - 1].order + 1);
      }
    });

    test('ciudades en orden esperado incluyendo Savile Row', () {
      expect(mockFoggRoute.cities.map((c) => c.name).toList(),
          ['Londres', 'París', 'Estambul', 'Bombay', 'Tokio', 'Savile Row']);
    });

    test('validated factory respeta invariante', () {
      expect(() => FoggRoute.validated(cities: mockFoggRoute.cities), returnsNormally);
    });

    test('polyline coords coinciden con ciudades (con quiebre Mercator B)', () {
      final poly = mockFoggRoute.polyline;
      // Primeros 5 puntos (0..4) coinciden con ciudades 0..4
      for (var i = 0; i < 5; i++) {
        expect(poly[i].latitude, mockFoggRoute.cities[i].lat);
        expect(poly[i].longitude, mockFoggRoute.cities[i].lng);
      }
      // Quiebre 180/-180 interpolado en Y Mercator (Opción B)
      expect(poly[5].longitude, 180);
      expect(poly[6].longitude, -180);
      // Lat en antimeridiano ≈38.8917 (Mercator) — antes 38.5776 con lat lineal
      expect(poly[5].latitude, closeTo(38.8917, 0.02));
      expect(poly[6].latitude, closeTo(38.8917, 0.02));
      // Pendiente Mercator idéntica a ambos lados (y / lng)
      final y1 = _latToY(mockFoggRoute.cities[4].lat); // Tokio
      final yAt = _latToY(poly[5].latitude);
      final y2 = _latToY(mockFoggRoute.cities.last.lat); // Savile
      final lng1U = mockFoggRoute.cities[4].lng; // 139.65
      final lng2U = mockFoggRoute.cities.last.lng + 360; // 359.859
      final slopeY1 = (yAt - y1) / (180 - lng1U);
      final slopeY2 = (y2 - yAt) / (lng2U - 180);
      expect(slopeY1, closeTo(slopeY2, 1e-9));
      // Último punto coincide con Savile Row
      expect(poly.last.latitude, mockFoggRoute.cities.last.lat);
      expect(poly.last.longitude, mockFoggRoute.cities.last.lng);
    });

    test('polylineSegments evita segmento parásito 180→-180', () {
      final segs = mockFoggRoute.polylineSegments;
      // No debe existir un Polyline que contenga ambos 180 y -180 consecutivos
      for (final seg in segs) {
        for (var i = 0; i < seg.length - 1; i++) {
          final a = seg[i].longitude;
          final b = seg[i + 1].longitude;
          // Si a==180 entonces b no debe ser -180 dentro del mismo segmento
          if (a == 180) expect(b, isNot(-180));
          if (a == -180) expect(b, isNot(180));
        }
      }
      // Flatten debe coincidir con polyline legacy
      final flat = segs.expand((s) => s).toList();
      expect(flat.length, mockFoggRoute.polyline.length);
    });
  });

  group('Antimeridiano — 5 saltos reales (Opción B Mercator)', () {
    // Coordenadas reales WGS84 — fuentes: OSM / Wikipedia
    // Orden este: origen.lng_u < destino.lng_u (dest+360)
    final cases = [
      (
        name: 'Japón (Tokio) → San Francisco',
        origin: const FoggCity(name: 'Tokio', lat: 35.6895, lng: 139.692, order: 0),
        dest: const FoggCity(name: 'San Francisco', lat: 37.7749, lng: -122.4194, order: 1),
        expectedLatAt180: 36.55507,
      ),
      (
        name: 'Filipinas (Manila) → México (CDMX)',
        origin: const FoggCity(name: 'Manila', lat: 14.5995, lng: 120.9842, order: 0),
        dest: const FoggCity(name: 'CDMX', lat: 19.4326, lng: -99.1332, order: 1),
        expectedLatAt180: 16.65369,
      ),
      (
        name: 'Islas Salomón (Honiara) → Honolulu',
        origin: const FoggCity(name: 'Honiara', lat: -9.4316, lng: 159.9552, order: 0),
        dest: const FoggCity(name: 'Honolulu', lat: 21.3099, lng: -157.8581, order: 1),
        expectedLatAt180: 5.38646,
      ),
      (
        name: 'Nueva Zelanda (Wellington) → Chile (Santiago)',
        origin: const FoggCity(name: 'Wellington', lat: -41.2924, lng: 174.7787, order: 0),
        dest: const FoggCity(name: 'Santiago', lat: -33.4489, lng: -70.6693, order: 1),
        expectedLatAt180: -40.95295,
      ),
      (
        name: 'Sídney → Perú (Lima)',
        origin: const FoggCity(name: 'Sídney', lat: -33.8688, lng: 151.2093, order: 0),
        dest: const FoggCity(name: 'Lima', lat: -12.0464, lng: -77.0428, order: 1),
        expectedLatAt180: -29.42512,
      ),
    ];

    for (final c in cases) {
      test('${c.name} — quiebre con misma pendiente Mercator', () {
        final route = FoggRoute(cities: [c.origin, c.dest]);
        // Validación este debe pasar
        expect(() => FoggRoute.validated(cities: [c.origin, c.dest]), returnsNormally);

        final flat = route.polyline;
        final segs = route.polylineSegments;

        // 2 ciudades + quiebre = 4 puntos aplanados, 2 segmentos
        expect(flat.length, 4, reason: '${c.name}: flat debe ser [orig, 180, -180, dest]');
        expect(segs.length, 2, reason: '${c.name}: 2 segmentos sin salto parásito');
        expect(segs[0].length, 2);
        expect(segs[1].length, 2);

        // Puntos extremos coinciden con ciudades
        expect(flat.first.latitude, c.origin.lat);
        expect(flat.first.longitude, c.origin.lng);
        expect(flat.last.latitude, c.dest.lat);
        expect(flat.last.longitude, c.dest.lng);

        // Quiebre en 180 / -180
        expect(flat[1].longitude, 180);
        expect(flat[2].longitude, -180);
        expect(segs[0].last.longitude, 180);
        expect(segs[1].first.longitude, -180);
        // Misma latAt180 en ambos lados
        expect(flat[1].latitude, closeTo(flat[2].latitude, 1e-9));
        expect(flat[1].latitude, closeTo(c.expectedLatAt180, 0.02),
            reason: '${c.name} latAt180 Mercator');

        // Pendiente Mercator idéntica (triángulo grande → dos triángulos semejantes en Y)
        final y1 = _latToY(c.origin.lat);
        final yAt = _latToY(flat[1].latitude);
        final y2 = _latToY(c.dest.lat);
        final lng1U = c.origin.lng;
        final lng2U = c.dest.lng + 360; // todos cruzan hacia el este
        // t ya implícito en yAt, pero verificamos pendiente
        final slopeY1 = (yAt - y1) / (180 - lng1U);
        final slopeY2 = (y2 - yAt) / (lng2U - 180);
        expect(slopeY1, closeTo(slopeY2, 1e-9),
            reason: '${c.name} pendiente Y/lng idéntica (sin quiebre visual)');

        // No segmento parásito 180→-180
        final hasBridge = segs.any((s) =>
            s.any((p) => p.longitude == 180) && s.any((p) => p.longitude == -180));
        expect(hasBridge, isFalse, reason: 'Ningún segmento debe contener 180 y -180');
      });
    }

    test('ruta sin cruce no genera segmentos extra', () {
      const route = FoggRoute(cities: [
        FoggCity(name: 'Londres', lat: 51.5072, lng: -0.1276, order: 0),
        FoggCity(name: 'París', lat: 48.8566, lng: 2.3522, order: 1),
      ]);
      expect(route.polylineSegments.length, 1);
      expect(route.polylineSegments[0].length, 2);
      expect(route.polyline.length, 2);
    });

    test('ruta vacía y una ciudad', () {
      expect(const FoggRoute(cities: []).polylineSegments, isEmpty);
      expect(const FoggRoute(cities: []).polyline, isEmpty);
      const single = FoggRoute(cities: [
        FoggCity(name: 'Londres', lat: 51.5, lng: -0.1, order: 0),
      ]);
      expect(single.polylineSegments.length, 1);
      expect(single.polylineSegments[0].length, 1);
    });
  });
}
