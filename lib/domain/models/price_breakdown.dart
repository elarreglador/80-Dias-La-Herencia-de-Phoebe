import '../../services/rail_pricing.dart';

/// Desglose del billete del tren — trazabilidad del cálculo.
///
/// `total` es la misma fórmula que usa `TransportSelector` para fijar el
/// precio: base de la zona × distancia × multiplicador económico del país.
class PriceBreakdown {
  const PriceBreakdown({
    required this.basePricePerKm,
    required this.zone,
    required this.countryMultiplier,
    required this.distanceKm,
  });

  /// Precio base en €/km de la zona geográfica (sin multiplicador).
  final double basePricePerKm;

  /// Zona geográfica de la que procede el base.
  final GeoZone zone;

  /// Multiplicador económico del país de llegada (España = 1.0).
  final double countryMultiplier;

  /// Distancia real de la ruta en km.
  final double distanceKm;

  double get total => basePricePerKm * distanceKm * countryMultiplier;
}
