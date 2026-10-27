import 'geo_pricing.dart';

/// Precios base del coche — combustible (€/km) y alquiler (€/tramo) por zona.
///
/// La zona y el multiplicador económico del país de llegada proceden de
/// `GeoPricing` (SPEC 019); esta clase solo aporta las cifras base.
class CarPricing {
  const CarPricing._();

  /// Combustible en €/km por zona.
  /// Cálculo: consumo medio 7,5 L/100 km × precio medio del carburante por zona.
  /// Fuentes: Global Petrol Prices (2025), IEA (2025).
  static const fuelBasePricePerKm = <GeoZone, double>{
    GeoZone.europeDeveloped: 0.12,
    GeoZone.northAmerica: 0.06,
    GeoZone.asiaDeveloped: 0.10, // Japón
    GeoZone.asiaDeveloping: 0.07,
    GeoZone.oceania: 0.09,
    GeoZone.africa: 0.08,
    GeoZone.southAmerica: 0.08,
    GeoZone.middleEast: 0.05,
  };

  /// Alquiler del coche en € por tramo (tarifa de un día de turismo económico,
  /// fija: NO escala con la duración del trayecto).
  /// Fuente: estimación sobre tarifas públicas de alquiler (2025).
  static const rentalBasePrice = <GeoZone, double>{
    GeoZone.europeDeveloped: 50,
    GeoZone.northAmerica: 45,
    GeoZone.asiaDeveloped: 55,
    GeoZone.asiaDeveloping: 25,
    GeoZone.oceania: 45,
    GeoZone.africa: 40,
    GeoZone.southAmerica: 35,
    GeoZone.middleEast: 30,
  };
}
