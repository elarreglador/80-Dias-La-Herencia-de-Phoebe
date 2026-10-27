import 'geo_pricing.dart';

/// Precio del billete de tren — base por zona × multiplicador del país.
///
/// El base refleja el coste de infraestructura de la zona; el multiplicador,
/// el nivel económico del país de llegada. Fuentes del base:
/// traintrackings.com (2025), T&E Ranking (2024), Pedestrian Observations (2024).
class RailPricing {
  const RailPricing._();

  /// Precio base en €/km por zona (2ª clase intercity, tarifa publicada media).
  static const basePricePerKm = <GeoZone, double>{
    GeoZone.europeDeveloped: 0.15,
    GeoZone.northAmerica: 0.16,
    GeoZone.asiaDeveloped: 0.18, // Japón
    GeoZone.asiaDeveloping: 0.06, // China, India, SE asiático
    GeoZone.oceania: 0.11,
    GeoZone.africa: 0.05, // estimación
    GeoZone.southAmerica: 0.08, // estimación
    GeoZone.middleEast: 0.07, // estimación
  };

  /// Precio final por km para un tramo concreto.
  static double pricePerKm({
    required GeoZone zone,
    required double countryMultiplier,
  }) =>
      basePricePerKm[zone]! * countryMultiplier;
}
