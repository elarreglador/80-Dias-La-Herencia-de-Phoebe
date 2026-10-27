import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pf/domain/entities/fogg_city.dart';
import 'package:pf/domain/entities/transport_mode.dart';
import 'package:pf/domain/models/price_breakdown.dart';
import 'package:pf/services/city_catalog.dart';
import 'package:pf/services/car_pricing.dart';
import 'package:pf/services/geo_pricing.dart';
import 'package:pf/services/rail_pricing.dart';
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

  Future<TransportSelector> buildSelector() async {
    final catalog = await RouteCatalog.load(rootBundle);
    final cityCatalog = await CityCatalog.load(rootBundle);
    return TransportSelector(catalog: catalog, cityCatalog: cityCatalog);
  }

  test('el tren usa la fórmula real y rellena priceBreakdown', () async {
    final selector = await buildSelector();
    final opts = selector.optionsFor(current);
    expect(opts, isNotEmpty);
    var trainSeen = false;
    for (final o in opts) {
      for (final v in o.vehicles) {
        if (v.mode != TransportMode.train) continue;
        trainSeen = true;
        final zone = GeoPricing.zoneForTimezone(o.city.timezone);
        final mult = GeoPricing.countryMultiplierForTimezone(o.city.timezone);
        final expectedPerKm = RailPricing.basePricePerKm[zone]! * mult;
        expect(v.price, (v.route!.distanceKm * expectedPerKm).round());
        expect(v.priceBreakdown, isNotNull);
        final b = v.priceBreakdown! as RailPriceBreakdown;
        expect(b.zone, zone);
        expect(b.countryMultiplier, mult);
        expect(b.basePricePerKm, RailPricing.basePricePerKm[zone]!);
        expect(b.distanceKm, v.route!.distanceKm);
        expect(b.total, closeTo(v.price, 1.0));
      }
    }
    expect(trainSeen, isTrue, reason: 'algún destino debe ofrecer tren');
  });

  test('el barco mantiene la tarifa mock y sin desglose', () async {
    final selector = await buildSelector();
    final opts = selector.optionsFor(current);
    for (final o in opts) {
      for (final v in o.vehicles) {
        if (v.mode != TransportMode.ship) continue;
        expect(v.priceBreakdown, isNull);
        final tariff = TariffTable.defaults[v.mode]!;
        expect(v.price, (v.route!.distanceKm * tariff.pricePerKm).round());
      }
    }
  });

  test('el coche usa alquiler + combustible y rellena priceBreakdown', () async {
    final selector = await buildSelector();
    final opts = selector.optionsFor(current);
    expect(opts, isNotEmpty);
    var carSeen = false;
    for (final o in opts) {
      for (final v in o.vehicles) {
        if (v.mode != TransportMode.car) continue;
        carSeen = true;
        final zone = GeoPricing.zoneForTimezone(o.city.timezone);
        final mult = GeoPricing.countryMultiplierForTimezone(o.city.timezone);
        final fuelBase = CarPricing.fuelBasePricePerKm[zone]!;
        final rentalBase = CarPricing.rentalBasePrice[zone]!;
        final expectedFuel = fuelBase * mult * v.route!.distanceKm;
        final expectedRental = rentalBase * mult;
        expect(v.priceBreakdown, isNotNull);
        final b = v.priceBreakdown! as CarPriceBreakdown;
        expect(b.zone, zone);
        expect(b.countryMultiplier, mult);
        expect(b.fuelBasePricePerKm, fuelBase);
        expect(b.rentalBasePrice, rentalBase);
        expect(b.distanceKm, v.route!.distanceKm);
        expect(b.fuel, closeTo(expectedFuel, 1e-9));
        expect(b.rental, closeTo(expectedRental, 1e-9));
        expect(b.total, closeTo(expectedRental + expectedFuel, 1e-9));
        // El precio mostrado es el total redondeado una sola vez.
        expect(v.price, b.total.round());
      }
    }
    expect(carSeen, isTrue, reason: 'algún destino debe ofrecer coche');
  });

  test('el alquiler del coche es fijo: no escala con la distancia', () async {
    final selector = await buildSelector();
    final opts = selector.optionsFor(current);
    // Agrupa por zona + multiplicador (misma zona y país → mismo alquiler).
    final byZoneAndMult = <(GeoZone, double), List<CarPriceBreakdown>>{};
    for (final o in opts) {
      for (final v in o.vehicles) {
        if (v.mode != TransportMode.car) continue;
        final b = v.priceBreakdown! as CarPriceBreakdown;
        byZoneAndMult.putIfAbsent((b.zone, b.countryMultiplier), () => []).add(b);
      }
    }
    expect(byZoneAndMult, isNotEmpty);
    for (final entry in byZoneAndMult.entries) {
      final (zone, mult) = entry.key;
      final expected = CarPricing.rentalBasePrice[zone]! * mult;
      final distances = <double>{};
      for (final b in entry.value) {
        expect(b.rental, closeTo(expected, 1e-9));
        distances.add(b.distanceKm);
      }
      // Con más de un tramo de distinta distancia, el alquiler es idéntico.
      if (distances.length > 1) {
        final rentals = entry.value.map((b) => b.rental).toSet();
        expect(rentals.length, 1,
            reason: 'alquiler idéntico con distancias $distances');
      }
    }
  });

  test('el precio del tren depende del país de llegada', () async {
    final selector = await buildSelector();
    final opts = selector.optionsFor(current);
    for (final o in opts) {
      for (final v in o.vehicles) {
        if (v.mode != TransportMode.train) continue;
        // Si el destino no está en la tabla, fallback 1.0 — coherencia con
        // GeoPricing.countryMultiplierForTimezone.
        expect(v.priceBreakdown!.countryMultiplier,
            GeoPricing.countryMultiplierForTimezone(o.city.timezone));
      }
    }
  });
}
