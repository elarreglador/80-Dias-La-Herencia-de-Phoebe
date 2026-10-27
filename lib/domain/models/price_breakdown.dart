import '../../services/geo_pricing.dart';

/// Desglose del precio de un tramo — trazabilidad del cálculo.
///
/// Base común a todos los modos: zona geográfica, multiplicador económico
/// del país de llegada y distancia real. Los componentes de precio concretos
/// viven en cada subclase (`RailPriceBreakdown`, `CarPriceBreakdown` y, en el
/// futuro, `ShipPriceBreakdown`).
abstract class PriceBreakdown {
  const PriceBreakdown({
    required this.zone,
    required this.countryMultiplier,
    required this.distanceKm,
  });

  /// Zona geográfica de la que procede el base.
  final GeoZone zone;

  /// Multiplicador económico del país de llegada (España = 1.0).
  final double countryMultiplier;

  /// Distancia real de la ruta en km.
  final double distanceKm;

  double get total;
}

/// Desglose del billete del tren — base de la zona × distancia × multiplicador.
class RailPriceBreakdown extends PriceBreakdown {
  const RailPriceBreakdown({
    required this.basePricePerKm,
    required super.zone,
    required super.countryMultiplier,
    required super.distanceKm,
  });

  /// Precio base en €/km de la zona geográfica (sin multiplicador).
  final double basePricePerKm;

  @override
  double get total => basePricePerKm * distanceKm * countryMultiplier;
}

/// Desglose del coche — alquiler fijo del tramo + combustible por km.
///
/// Ambos componentes se escalan por el multiplicador económico del país de
/// llegada; el alquiler no depende de la distancia (SPEC 019, §6).
///
/// Si Phoebe llega a una ciudad en coche y sale de ella en coche, continúa
/// con el mismo vehículo: no alquila uno nuevo y el alquiler se anula
/// (`rentalWaived`, SPEC 019 addenda §11). Solo paga entonces el combustible.
class CarPriceBreakdown extends PriceBreakdown {
  const CarPriceBreakdown({
    required this.fuelBasePricePerKm,
    required this.rentalBasePrice,
    required super.zone,
    required super.countryMultiplier,
    required super.distanceKm,
    this.rentalWaived = false,
  });

  /// €/km de combustible de la zona (sin multiplicador).
  final double fuelBasePricePerKm;

  /// € fijos de alquiler de la zona (sin multiplicador).
  final double rentalBasePrice;

  /// `true` si Phoebe conserva el coche del tramo anterior → sin alquiler.
  final bool rentalWaived;

  double get fuel => fuelBasePricePerKm * countryMultiplier * distanceKm;
  double get rental => rentalWaived ? 0.0 : rentalBasePrice * countryMultiplier;

  @override
  double get total => rental + fuel;
}
