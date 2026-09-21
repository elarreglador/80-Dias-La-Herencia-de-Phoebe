import 'package:flutter_test/flutter_test.dart';
import 'package:pf/domain/entities/fogg_route.dart';

void main() {
  group('FoggRoute — Regla del Este', () {
    test('polyline contiene 8 puntos con quiebre antimeridiano (cierra en Savile Row)', () {
      // 6 ciudades + 2 puntos de quiebre 180/-180 en último tramo
      expect(mockFoggRoute.polyline.length, 8);
      expect(mockFoggRoute.cities.length, 6);
      // Verifica quiebre
      expect(mockFoggRoute.polyline[5].longitude, 180);
      expect(mockFoggRoute.polyline[6].longitude, -180);
      expect(mockFoggRoute.polyline.last.longitude, mockFoggRoute.cities.last.lng);
    });

    test('lng crece hacia el este en orden 0..4 y permite salto final a Savile Row', () {
      for (var i = 1; i < mockFoggRoute.cities.length; i++) {
        if (i == mockFoggRoute.cities.length - 1) {
          // Último tramo Tokio → Savile Row permite salto antimeridiano
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
            reason: 'Ciudad ${mockFoggRoute.cities[i].name} debe tener lng > ${mockFoggRoute.cities[i - 1].name}',
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

    test('polyline coords coinciden con ciudades (con quiebre interpolado)', () {
      final poly = mockFoggRoute.polyline;
      // Primeros 5 puntos (0..4) coinciden con ciudades 0..4
      for (var i = 0; i < 5; i++) {
        expect(poly[i].latitude, mockFoggRoute.cities[i].lat);
        expect(poly[i].longitude, mockFoggRoute.cities[i].lng);
      }
      // Quiebre 180/-180 interpolado entre Tokio y Savile Row (misma pendiente)
      expect(poly[5].longitude, 180);
      expect(poly[6].longitude, -180);
      // Lat en antimeridiano ≈38.58 (interpolado para que ambas semirrectas tengan idéntica pendiente)
      expect(poly[5].latitude, closeTo(38.5776, 0.01));
      expect(poly[6].latitude, closeTo(38.5776, 0.01));
      // Pendiente idéntica a ambos lados del corte
      final slope1 = (poly[5].latitude - poly[4].latitude) / (poly[5].longitude - poly[4].longitude);
      final slope2 = (poly.last.latitude - poly[6].latitude) / (poly.last.longitude - poly[6].longitude);
      expect(slope1, closeTo(slope2, 0.001));
      // Último punto coincide con Savile Row
      expect(poly.last.latitude, mockFoggRoute.cities.last.lat);
      expect(poly.last.longitude, mockFoggRoute.cities.last.lng);
    });
  });
}
