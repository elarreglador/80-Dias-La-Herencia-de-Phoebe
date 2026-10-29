import 'package:flutter_test/flutter_test.dart';

import 'package:pf/services/geo_pricing.dart';
import 'package:pf/services/hotel_pricing.dart';

void main() {
  test('HotelPricing calcula la noche por zona geografica y multiplicador', () {
    expect(HotelPricing.priceFor(GeoZone.europeDeveloped, countryMultiplier: 1.0), 90);
    expect(HotelPricing.priceFor(GeoZone.europeDeveloped, countryMultiplier: 1.5), 135);
    expect(HotelPricing.priceFor(GeoZone.asiaDeveloped, countryMultiplier: 1.2), 192);
  });

  test('HotelPricing redondea una sola vez el importe a entero en euros', () {
    // 90 * 1.25 = 112.5 -> redondeo a 113.
    expect(HotelPricing.priceFor(GeoZone.europeDeveloped, countryMultiplier: 1.25), 113);
  });
}
