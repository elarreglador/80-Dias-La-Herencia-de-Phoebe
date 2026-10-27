import 'package:flutter_test/flutter_test.dart';

import 'package:pf/services/geo_pricing.dart';
import 'package:pf/services/rail_pricing.dart';

void main() {
  group('pricePerKm', () {
    test('devuelve base de la zona × multiplicador del país', () {
      final base = RailPricing.basePricePerKm[GeoZone.europeDeveloped]!;
      expect(
        RailPricing.pricePerKm(zone: GeoZone.europeDeveloped, countryMultiplier: 1.0),
        base,
      );
      expect(
        RailPricing.pricePerKm(zone: GeoZone.europeDeveloped, countryMultiplier: 1.2),
        closeTo(base * 1.2, 1e-12),
      );
    });

    test('todas las zonas del enum tienen precio base definido', () {
      for (final zone in GeoZone.values) {
        expect(RailPricing.basePricePerKm[zone], isNotNull, reason: zone.name);
      }
    });
  });
}
