import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pf/domain/entities/fogg_city.dart';
import 'package:pf/services/city_catalog.dart';
import 'package:pf/services/route_catalog.dart';
import 'package:pf/services/transport_selector.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const current = FoggCity(
      name: 'Londres', lat: 51.5085, lng: -0.1257, order: 0, timezone: 'Europe/London');

  test('optionsFor devuelve <=3 destinos hacia el este', () async {
    final catalog = await RouteCatalog.load(rootBundle);
    final selector = TransportSelector(catalog: catalog);
    final opts = selector.optionsFor(current);
    expect(opts.length, lessThanOrEqualTo(3));
    expect(opts, isNotEmpty);
    for (final o in opts) {
      // unfolded lng > current
      var x = o.city.lng;
      while (x <= current.lng) {
        x += 360;
      }
      expect(x, greaterThan(current.lng));
    }
  });

  test('cada vehículo tiene price>0 y hora de salida', () async {
    final catalog = await RouteCatalog.load(rootBundle);
    final selector = TransportSelector(catalog: catalog);
    final opts = selector.optionsFor(current);
    for (final o in opts) {
      for (final v in o.vehicles) {
        expect(v.price, greaterThan(0));
        expect(v.departureHour, isNotNull);
        expect(v.departureMinute, isNotNull);
      }
    }
  });

  test('el vehículo conserva la RouteEntry de la ruta elegida', () async {
    final catalog = await RouteCatalog.load(rootBundle);
    final selector = TransportSelector(catalog: catalog);
    final opts = selector.optionsFor(current);
    for (final o in opts) {
      for (final v in o.vehicles) {
        expect(v.route, isNotNull, reason: '${v.mode.label} conserva su ruta');
        expect(v.route!.geometry, isNotEmpty);
        expect(v.route!.destination, o.city.name);
        expect(v.route!.mode, v.mode);
      }
    }
  });

  test('el destino usa el timezone IANA real del catálogo', () async {
    final catalog = await RouteCatalog.load(rootBundle);
    final cityCatalog = await CityCatalog.load(rootBundle);
    final selector = TransportSelector(catalog: catalog, cityCatalog: cityCatalog);
    final opts = selector.optionsFor(current);
    expect(opts, isNotEmpty);
    for (final o in opts) {
      expect(o.city.timezone, isNot('UTC'));
      final catalogCity = cityCatalog.byName(o.city.name);
      expect(catalogCity, isNotNull);
      expect(o.city.timezone, catalogCity!.timezone);
      expect(o.city.lat, closeTo(catalogCity.lat, 1e-9));
      expect(o.city.lng, closeTo(catalogCity.lng, 1e-9));
    }
  });
}
