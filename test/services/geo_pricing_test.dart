import 'package:flutter_test/flutter_test.dart';

import 'package:pf/services/geo_pricing.dart';

void main() {
  group('zoneForTimezone', () {
    test('casos límite del criterio de aceptación', () {
      expect(GeoPricing.zoneForTimezone('Europe/Madrid'), GeoZone.europeDeveloped);
      expect(GeoPricing.zoneForTimezone('Asia/Tokyo'), GeoZone.asiaDeveloped);
      expect(GeoPricing.zoneForTimezone('America/Sao_Paulo'), GeoZone.southAmerica);
    });

    test('prefijos de región', () {
      expect(GeoPricing.zoneForTimezone('Europe/London'), GeoZone.europeDeveloped);
      expect(GeoPricing.zoneForTimezone('Africa/Nairobi'), GeoZone.africa);
      expect(GeoPricing.zoneForTimezone('Australia/Sydney'), GeoZone.oceania);
      expect(GeoPricing.zoneForTimezone('Pacific/Tahiti'), GeoZone.oceania);
    });

    test('Asia se subdivide: desarrollada, en desarrollo y Oriente Medio', () {
      expect(GeoPricing.zoneForTimezone('Asia/Seoul'), GeoZone.asiaDeveloped);
      expect(GeoPricing.zoneForTimezone('Asia/Shanghai'), GeoZone.asiaDeveloping);
      expect(GeoPricing.zoneForTimezone('Asia/Kolkata'), GeoZone.asiaDeveloping);
      expect(GeoPricing.zoneForTimezone('Asia/Riyadh'), GeoZone.middleEast);
      expect(GeoPricing.zoneForTimezone('Asia/Tehran'), GeoZone.middleEast);
    });

    test('America se subdivide: EE.UU./Canadá vs resto', () {
      expect(GeoPricing.zoneForTimezone('America/New_York'), GeoZone.northAmerica);
      expect(GeoPricing.zoneForTimezone('America/Toronto'), GeoZone.northAmerica);
      expect(GeoPricing.zoneForTimezone('America/Mexico_City'), GeoZone.southAmerica);
      expect(GeoPricing.zoneForTimezone('America/Argentina/Cordoba'), GeoZone.southAmerica);
    });

    test('Atlantic y husos genéricos caen en zona europea por defecto', () {
      expect(GeoPricing.zoneForTimezone('Atlantic/Faroe'), GeoZone.europeDeveloped);
      expect(GeoPricing.zoneForTimezone('Atlantic/St_Helena'), GeoZone.africa);
      expect(GeoPricing.zoneForTimezone('UTC'), GeoZone.europeDeveloped);
    });
  });

  group('countryMultiplierForTimezone', () {
    test('España es la base 1.0', () {
      expect(GeoPricing.countryMultiplierForTimezone('Europe/Madrid'), 1.0);
    });

    test('sin entrada conocida el fallback es 1.0', () {
      expect(GeoPricing.countryMultiplierForTimezone('Europe/Narnia'), 1.0);
      expect(GeoPricing.countryMultiplierForTimezone('UTC'), 1.0);
    });

    test('los países con ciudades de locations.json tienen entrada propia', () {
      // Muestra representativa por zona — no todas devuelven el fallback.
      expect(GeoPricing.countryMultiplierForTimezone('Asia/Tokyo'), 1.20);
      expect(GeoPricing.countryMultiplierForTimezone('America/New_York'), 1.10);
      expect(GeoPricing.countryMultiplierForTimezone('Africa/Cairo'), 0.35);
      expect(GeoPricing.countryMultiplierForTimezone('Asia/Shanghai'), 0.45);
    });
  });
}
