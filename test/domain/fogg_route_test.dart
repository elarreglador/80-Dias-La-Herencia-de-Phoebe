import 'package:flutter_test/flutter_test.dart';
import 'package:pf/domain/entities/fogg_route.dart';

void main() {
  group('FoggRoute — Regla del Este', () {
    test('polyline contiene 5 puntos en orden', () {
      expect(mockFoggRoute.polyline.length, 5);
      expect(mockFoggRoute.cities.length, 5);
    });

    test('lng crece hacia el este en orden 0..4', () {
      for (var i = 1; i < mockFoggRoute.cities.length; i++) {
        expect(
          mockFoggRoute.cities[i].lng,
          greaterThan(mockFoggRoute.cities[i - 1].lng),
          reason: 'Ciudad ${mockFoggRoute.cities[i].name} debe tener lng > ${mockFoggRoute.cities[i - 1].name}',
        );
        expect(mockFoggRoute.cities[i].order, mockFoggRoute.cities[i - 1].order + 1);
      }
    });

    test('ciudades en orden esperado', () {
      expect(mockFoggRoute.cities.map((c) => c.name).toList(),
          ['Londres', 'París', 'Estambul', 'Bombay', 'Tokio']);
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
