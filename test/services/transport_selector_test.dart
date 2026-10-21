import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pf/domain/entities/fogg_city.dart';
import 'package:pf/domain/entities/transport_mode.dart';
import 'package:pf/services/route_catalog.dart';
import 'package:pf/services/transport_selector.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('optionsFor devuelve <=3 destinos hacia el este', () async {
    final catalog = await RouteCatalog.load(rootBundle);
    const current = FoggCity(name: 'Londres', lat: 51.5085, lng: -0.1257, order: 0, timezone: 'Europe/London');
    final selector = TransportSelector(catalog: catalog);
    final opts = selector.optionsFor(current);
    expect(opts.length, lessThanOrEqualTo(3));
    expect(opts, isNotEmpty);
    for (final o in opts) {
      // unfolded lng > current
      var x = o.city.lng;
      while (x <= current.lng) x += 360;
      expect(x, greaterThan(current.lng));
    }
  });

  test('foot siempre presente y price>0', () async {
    final catalog = await RouteCatalog.load(rootBundle);
    const current = FoggCity(name: 'Londres', lat: 51.5085, lng: -0.1257, order: 0, timezone: 'Europe/London');
    final selector = TransportSelector(catalog: catalog);
    final opts = selector.optionsFor(current);
    for (final o in opts) {
      expect(o.vehicles.any((v) => v.mode == TransportMode.foot), isTrue);
      for (final v in o.vehicles) {
        expect(v.price, greaterThan(0));
        expect(v.departureHour, isNotNull);
        expect(v.departureMinute, isNotNull);
      }
    }
  });
}
