/// Ciudad del trazado Fogg — respeta Regla del Este (lng crece hacia el este).
/// `timezone` es IANA (`Europe/Paris`) — la hora civil `-7/+2` se deriva
/// en [TimezoneService] con DST correcto para cada fecha UTC.
class FoggCity {
  const FoggCity({
    required this.name,
    required this.lat,
    required this.lng,
    required this.order,
    this.timezone = 'UTC',
  });

  /// Nombre de la ciudad, ej. "Londres".
  final String name;

  /// Latitud en grados decimales.
  final double lat;

  /// Longitud en grados decimales — crece hacia el este (Regla del Este).
  final double lng;

  /// Orden de visita 0..n. Menor order = prioridad en colisión de labels.
  final int order;

  /// Zona IANA para hora civil DST-correcta (ej. `Europe/Paris`).
  /// No persistir offset numérico — se deriva con [TimezoneService.offsetAt].
  final String timezone;

  @override
  String toString() =>
      'FoggCity(name: $name, lat: $lat, lng: $lng, order: $order, timezone: $timezone)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FoggCity &&
          runtimeType == other.runtimeType &&
          name == other.name &&
          lat == other.lat &&
          lng == other.lng &&
          order == other.order &&
          timezone == other.timezone;

  @override
  int get hashCode => Object.hash(name, lat, lng, order, timezone);
}
