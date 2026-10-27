import 'package:flutter_test/flutter_test.dart';

import 'package:pf/services/rail_pricing.dart';

void main() {
  group('zoneForTimezone', () {
    test('casos límite del criterio de aceptación', () {
      expect(RailPricing.zoneForTimezone('Europe/Madrid'), GeoZone.europeDeveloped);
      expect(RailPricing.zoneForTimezone('Asia/Tokyo'), GeoZone.asiaDeveloped);
      expect(RailPricing.zoneForTimezone('America/Sao_Paulo'), GeoZone.southAmerica);
    });

    test('prefijos de región', () {
      expect(RailPricing.zoneForTimezone('Europe/London'), GeoZone.europeDeveloped);
      expect(RailPricing.zoneForTimezone('Africa/Nairobi'), GeoZone.africa);
      expect(RailPricing.zoneForTimezone('Australia/Sydney'), GeoZone.oceania);
      expect(RailPricing.zoneForTimezone('Pacific/Tahiti'), GeoZone.oceania);
    });

    test('Asia se subdivide: desarrollada, en desarrollo y Oriente Medio', () {
      expect(RailPricing.zoneForTimezone('Asia/Seoul'), GeoZone.asiaDeveloped);
      expect(RailPricing.zoneForTimezone('Asia/Shanghai'), GeoZone.asiaDeveloping);
      expect(RailPricing.zoneForTimezone('Asia/Kolkata'), GeoZone.asiaDeveloping);
      expect(RailPricing.zoneForTimezone('Asia/Riyadh'), GeoZone.middleEast);
      expect(RailPricing.zoneForTimezone('Asia/Tehran'), GeoZone.middleEast);
    });

    test('America se subdivide: EE.UU./Canadá vs resto', () {
      expect(RailPricing.zoneForTimezone('America/New_York'), GeoZone.northAmerica);
      expect(RailPricing.zoneForTimezone('America/Toronto'), GeoZone.northAmerica);
      expect(RailPricing.zoneForTimezone('America/Mexico_City'), GeoZone.southAmerica);
      expect(RailPricing.zoneForTimezone('America/Argentina/Cordoba'), GeoZone.southAmerica);
    });

    test('Atlantic y husos genéricos caen en zona europea por defecto', () {
      expect(RailPricing.zoneForTimezone('Atlantic/Faroe'), GeoZone.europeDeveloped);
      expect(RailPricing.zoneForTimezone('Atlantic/St_Helena'), GeoZone.africa);
      expect(RailPricing.zoneForTimezone('UTC'), GeoZone.europeDeveloped);
    });
  });

  group('countryMultiplierForTimezone', () {
    test('España es la base 1.0', () {
      expect(RailPricing.countryMultiplierForTimezone('Europe/Madrid'), 1.0);
    });

    test('sin entrada conocida el fallback es 1.0', () {
      expect(RailPricing.countryMultiplierForTimezone('Europe/Narnia'), 1.0);
      expect(RailPricing.countryMultiplierForTimezone('UTC'), 1.0);
    });

    test('los países con ciudades de locations.json tienen entrada propia', () {
      // Muestra representativa por zona — no todas devuelven el fallback.
      expect(RailPricing.countryMultiplierForTimezone('Asia/Tokyo'), 1.20);
      expect(RailPricing.countryMultiplierForTimezone('America/New_York'), 1.10);
      expect(RailPricing.countryMultiplierForTimezone('Africa/Cairo'), 0.35);
      expect(RailPricing.countryMultiplierForTimezone('Asia/Shanghai'), 0.45);
    });
  });

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
