/// Ciudad del trazado Fogg — respeta Regla del Este (lng crece hacia el este).
class FoggCity {
  const FoggCity({
    required this.name,
    required this.lat,
    required this.lng,
    required this.order,
  });

  /// Nombre de la ciudad, ej. "Londres".
  final String name;

  /// Latitud en grados decimales.
  final double lat;

  /// Longitud en grados decimales — crece hacia el este (Regla del Este).
  final double lng;

  /// Orden de visita 0..n. Menor order = prioridad en colisión de labels.
  final int order;

  @override
  String toString() => 'FoggCity(name: $name, lat: $lat, lng: $lng, order: $order)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FoggCity &&
          runtimeType == other.runtimeType &&
          name == other.name &&
          lat == other.lat &&
          lng == other.lng &&
          order == other.order;

  @override
  int get hashCode => Object.hash(name, lat, lng, order);
}
