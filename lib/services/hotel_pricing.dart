import 'geo_pricing.dart';

/// Precios de hotel por noche y zona geográfica.
///
/// La tarifa por noche se fija por zona geográfica y se multiplica por el
/// multiplicador económico del país de la ciudad (base España = 1.0), siguiendo
/// el patrón de `CarPricing` / `RailPricing` (SPEC 019). El importe final se
/// redondea una sola vez a entero en €.
class HotelPricing {
  const HotelPricing._();

  /// Tarifa por noche en € por zona geográfica (turismo económico ficticio).
  static const Map<GeoZone, int> nightlyRatePerZone = <GeoZone, int>{
    GeoZone.europeDeveloped: 90,
    GeoZone.northAmerica: 130,
    GeoZone.asiaDeveloped: 160,
    GeoZone.asiaDeveloping: 100,
    GeoZone.oceania: 120,
    GeoZone.africa: 80,
    GeoZone.southAmerica: 70,
    GeoZone.middleEast: 110,
  };

  /// Importe de la noche de hotel: tarifa por zona × multiplicador del país.
  static int priceFor(
    GeoZone zone, {
    required double countryMultiplier,
  }) {
    return ((nightlyRatePerZone[zone] ?? 0) * countryMultiplier).round();
  }
}
