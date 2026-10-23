import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pf/domain/models/route_path.dart';
import 'package:pf/services/route_catalog.dart';

/// Invariantes de la geometría real del catálogo (SPEC 016).
///
/// El catálogo tiene rutas que cruzan el antimeridiano; el corte en el
/// meridiano debe impedir tanto la línea horizontal parasite como los
/// saltos de longitud mayores de 180° dentro de una misma polilínea.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('ninguna polilínea del catálogo cruza el antimeridiano sin cortar', () async {
    final catalog = await RouteCatalog.load(rootBundle);
    final routes = catalog.byOrigin.values.expand((r) => r).toList();
    expect(routes, isNotEmpty);

    var segmentsChecked = 0;
    for (final route in routes) {
      final path = RoutePath.fromGeometry(route.geometry);
      if (path == null) continue;

      for (final segment in path.renderSegments()) {
        segmentsChecked++;
        final hasBoth = segment.any((p) => p.longitude == 180) &&
            segment.any((p) => p.longitude == -180);
        expect(hasBoth, isFalse,
            reason: '${route.origin}→${route.destination}: +180 y -180 en la '
                'misma polilínea');
        for (var i = 1; i < segment.length; i++) {
          final delta =
              (segment[i].longitude - segment[i - 1].longitude).abs();
          expect(delta, lessThanOrEqualTo(180.0),
              reason: '${route.origin}→${route.destination}: salto de '
                  '${delta.toStringAsFixed(3)}° entre vértices');
        }
      }
    }
    expect(segmentsChecked, greaterThan(routes.length));
  });

  test('los extremos de la ruta coinciden con el origen y el destino', () async {
    final catalog = await RouteCatalog.load(rootBundle);
    final routes = catalog.byOrigin.values.expand((r) => r).toList();

    for (final route in routes) {
      final path = RoutePath.fromGeometry(route.geometry);
      if (path == null) continue;
      final start = path.positionAt(0);
      final end = path.positionAt(1);
      expect(start.latitude, closeTo(path.points.first.latitude, 1e-9));
      expect(start.longitude, closeTo(path.points.first.longitude, 1e-9));
      expect(end.latitude, closeTo(path.points.last.latitude, 1e-9));
      expect(end.longitude, closeTo(path.points.last.longitude, 1e-9));
    }
  });
}
