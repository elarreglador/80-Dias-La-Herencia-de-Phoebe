import 'package:flutter_test/flutter_test.dart';

import 'package:pf/domain/models/price_breakdown.dart';
import 'package:pf/services/car_pricing.dart';
import 'package:pf/services/geo_pricing.dart';

void main() {
  group('CarPricing', () {
    test('todas las zonas tienen combustible y alquiler definidos', () {
      for (final zone in GeoZone.values) {
        expect(CarPricing.fuelBasePricePerKm[zone], isNotNull,
            reason: 'fuel ${zone.name}');
        expect(CarPricing.rentalBasePrice[zone], isNotNull,
            reason: 'rental ${zone.name}');
      }
    });

    test('las tablas no comparten cifras con el tren', () {
      // El coche no debe depender de RailPricing (SPEC 019, criterio 4).
      expect(CarPricing.fuelBasePricePerKm[GeoZone.europeDeveloped], isNot(0.15));
    });
  });

  group('CarPriceBreakdown', () {
    test('total = alquiler + combustible con las fórmulas del contrato', () {
      const b = CarPriceBreakdown(
        fuelBasePricePerKm: 0.12,
        rentalBasePrice: 50,
        zone: GeoZone.europeDeveloped,
        countryMultiplier: 1.0,
        distanceKm: 300,
      );
      expect(b.fuel, closeTo(0.12 * 1.0 * 300, 1e-12));
      expect(b.rental, closeTo(50 * 1.0, 1e-12));
      expect(b.total, closeTo(b.rental + b.fuel, 1e-12));
      expect(b.total, closeTo(86.0, 1e-12));
    });

    test('ambos componentes se escalan por el multiplicador del país', () {
      const b = CarPriceBreakdown(
        fuelBasePricePerKm: 0.12,
        rentalBasePrice: 50,
        zone: GeoZone.europeDeveloped,
        countryMultiplier: 1.2,
        distanceKm: 100,
      );
      expect(b.fuel, closeTo(0.12 * 1.2 * 100, 1e-12));
      expect(b.rental, closeTo(50 * 1.2, 1e-12));
      expect(b.total, closeTo(b.rental + b.fuel, 1e-12));
    });

    test('el alquiler es fijo: no escala con la distancia', () {
      CarPriceBreakdown build(double km) => CarPriceBreakdown(
            fuelBasePricePerKm: CarPricing.fuelBasePricePerKm[GeoZone.africa]!,
            rentalBasePrice: CarPricing.rentalBasePrice[GeoZone.africa]!,
            zone: GeoZone.africa,
            countryMultiplier: GeoPricing.countryMultiplierForTimezone('Africa/Nairobi'),
            distanceKm: km,
          );
      final corto = build(50);
      final largo = build(2500);
      expect(corto.rental, closeTo(largo.rental, 1e-12));
      expect(corto.fuel, lessThan(largo.fuel));
      expect(corto.total, lessThan(largo.total));
    });

    test('con rentalWaived no se cobra alquiler y el total es el combustible', () {
      const b = CarPriceBreakdown(
        fuelBasePricePerKm: 0.12,
        rentalBasePrice: 50,
        zone: GeoZone.europeDeveloped,
        countryMultiplier: 1.2,
        distanceKm: 300,
        rentalWaived: true,
      );
      expect(b.rental, 0.0);
      expect(b.fuel, closeTo(0.12 * 1.2 * 300, 1e-12));
      expect(b.total, closeTo(b.fuel, 1e-12));
      // La tarifa base de la zona sigue documentada aunque no se aplique.
      expect(b.rentalBasePrice, 50);
      expect(b.rentalWaived, isTrue);
    });

    test('zona y multiplicador proceden de GeoPricing', () {
      final zone = GeoPricing.zoneForTimezone('Europe/Madrid');
      final mult = GeoPricing.countryMultiplierForTimezone('Europe/Madrid');
      expect(zone, GeoZone.europeDeveloped);
      expect(mult, 1.0);
      const b = CarPriceBreakdown(
        fuelBasePricePerKm: 0.12,
        rentalBasePrice: 50,
        zone: GeoZone.europeDeveloped,
        countryMultiplier: 1.0,
        distanceKm: 100,
      );
      expect(b.zone, zone);
      expect(b.countryMultiplier, mult);
    });

    test('fallback de multiplicador 1.0 para husos sin entrada', () {
      expect(GeoPricing.countryMultiplierForTimezone('Europe/Narnia'), 1.0);
      expect(GeoPricing.countryMultiplierForTimezone('UTC'), 1.0);
    });
  });
}
