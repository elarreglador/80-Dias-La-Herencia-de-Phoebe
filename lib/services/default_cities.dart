import '../domain/entities/destination_option.dart';
import '../domain/entities/fogg_city.dart';
import '../domain/entities/transport_mode.dart';
import '../domain/services/east_rule.dart';

/// Ciudades por defecto de la partida — trazado extendido de Phoebe.
/// `timezone` IANA — la hora civil se deriva vía `TimezoneService`.
const List<FoggCity> defaultCities = [
  FoggCity(name: 'Londres', lat: 51.5072, lng: -0.1276, order: 0, timezone: 'Europe/London'),
  FoggCity(name: 'París', lat: 48.8566, lng: 2.3522, order: 1, timezone: 'Europe/Paris'),
  FoggCity(name: 'Estambul', lat: 41.0082, lng: 28.9784, order: 2, timezone: 'Europe/Istanbul'),
  FoggCity(name: 'Bombay', lat: 19.0760, lng: 72.8777, order: 3, timezone: 'Asia/Kolkata'),
  FoggCity(name: 'Tokio', lat: 35.6762, lng: 139.6503, order: 4, timezone: 'Asia/Tokyo'),
  FoggCity(name: 'San Francisco', lat: 37.7749, lng: -122.4194, order: 5, timezone: 'America/Los_Angeles'),
  FoggCity(name: 'Nueva York', lat: 40.7128, lng: -74.0060, order: 6, timezone: 'America/New_York'),
  FoggCity(name: 'Savile Row', lat: 51.5107, lng: -0.1410, order: 7, timezone: 'Europe/London'),
];

/// Opciones de destino de respaldo cuando no hay `TransportSelector` o falla.
///
/// Filtra ciudades al este por la Regla del Este, ordena por distancia angular
/// y devuelve las tres más cercanas con un par de vehículos mock (barco/tren).
List<DestinationOption> mockDestinationOptions({
  required FoggCity current,
  required List<FoggCity> cities,
}) {
  final candidates = cities
      .where((c) => c != current && isEast(current, c))
      .toList()
    ..sort((a, b) =>
        eastDistance(current, a).compareTo(eastDistance(current, b)));
  final top = candidates.take(3).toList();
  return top
      .map((city) => DestinationOption(
            city: city,
            vehicles: [
              const VehicleOption(
                mode: TransportMode.ship,
                duration: Duration(hours: 18),
                price: 8200,
                sleeper: true,
                note: 'Sleeper',
                departureHour: 8,
                departureMinute: 0,
              ),
              const VehicleOption(
                mode: TransportMode.train,
                duration: Duration(hours: 14),
                price: 6400,
                sleeper: true,
                departureHour: 9,
                departureMinute: 30,
              ),
            ],
          ))
      .toList();
}
