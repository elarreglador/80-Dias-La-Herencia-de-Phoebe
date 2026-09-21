import 'package:flutter_test/flutter_test.dart';
import 'package:pf/domain/entities/fogg_route.dart';

void main() {
  group('FoggRoute — Regla del Este', () {
    test('polyline contiene 6 puntos en orden (cierra en Savile Row)', () {
      expect(mockFoggRoute.polyline.length, 6);
      expect(mockFoggRoute.cities.length, 6);
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

    test('polyline coords coinciden con ciudades', () {
      final poly = mockFoggRoute.polyline;
      for (var i = 0; i < poly.length; i++) {
        expect(poly[i].latitude, mockFoggRoute.cities[i].lat);
        expect(poly[i].longitude, mockFoggRoute.cities[i].lng);
      }
    });
  });
}
