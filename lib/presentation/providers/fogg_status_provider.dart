import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/destination_option.dart';
import '../../domain/entities/fogg_city.dart';
import '../../domain/entities/fogg_leg.dart';
import '../../domain/entities/fogg_status.dart';
import '../../domain/entities/transport_mode.dart';

/// Ciudades mock reutilizadas — coherentes con FoggRoute.
const _bombay = FoggCity(name: 'Bombay', lat: 19.0760, lng: 72.8777, order: 3);
const _tokio = FoggCity(name: 'Tokio', lat: 35.6762, lng: 139.6503, order: 4);
const _sanFrancisco = FoggCity(name: 'San Francisco', lat: 37.7749, lng: -122.4194, order: 5);
const _nuevaYork = FoggCity(name: 'Nueva York', lat: 40.7128, lng: -74.0060, order: 6);
const _savileRow = FoggCity(name: 'Savile Row', lat: 51.5107, lng: -0.1410, order: 7);

/// Factoría — crea un FoggTraveling ficticio con llegada en [durationFromNow].
FoggTraveling _mockTraveling({
  required FoggCity from,
  required FoggCity to,
  required TransportMode mode,
  required Duration durationFromNow,
  required int price,
  bool sleeper = false,
}) {
  final now = DateTime.now().toUtc();
  return FoggTraveling(
    leg: FoggLeg(
      from: from,
      to: to,
      transport: mode,
      departureUtc: now.subtract(const Duration(hours: 2)),
      arrivalUtc: now.add(durationFromNow),
      price: price,
      sleeper: sleeper,
    ),
  );
}

/// Estado mock viajando por defecto — Bombay→Tokio en tren, ~1 día + 5h.
FoggTraveling _defaultTraveling() => _mockTraveling(
      from: _bombay,
      to: _tokio,
      mode: TransportMode.train,
      durationFromNow: const Duration(days: 1, hours: 5, minutes: 23, seconds: 11),
      price: 4200,
      sleeper: true,
    );

/// Estado mock en destino — Tokio hub con 3 opciones hacia el este (desenrollado).
/// Tokio 139.65 → SF -122.41 (lng_u 237) → NY -74 (285) → Savile -0.14 (359) todos >139 con offset.
FoggArrived _defaultArrived() => const FoggArrived(
      currentCity: _tokio,
      options: [
        DestinationOption(
          city: _sanFrancisco,
          vehicles: [
            VehicleOption(mode: TransportMode.ship, duration: Duration(hours: 18), price: 8200, sleeper: true, note: 'Sleeper'),
            VehicleOption(mode: TransportMode.balloon, duration: Duration(hours: 9, minutes: 30), price: 9500),
          ],
        ),
        DestinationOption(
          city: _nuevaYork,
          vehicles: [
            VehicleOption(mode: TransportMode.train, duration: Duration(hours: 14), price: 6400, sleeper: true),
            VehicleOption(mode: TransportMode.car, duration: Duration(hours: 8), price: 1200),
            VehicleOption(mode: TransportMode.camel, duration: Duration(hours: 36), price: 300),
          ],
        ),
        DestinationOption(
          city: _savileRow,
          vehicles: [
            VehicleOption(mode: TransportMode.ship, duration: Duration(hours: 22), price: 7000, sleeper: true),
          ],
        ),
      ],
    );

/// Provider principal — mock ficticio, estética primero.
/// Alterna entre viajando/en destino vía notifier o métodos helper.
final foggStatusProvider = StateProvider<FoggStatus>((ref) => _defaultTraveling());

/// Helper para togglear en UI debug sin exponer ciudades internas.
extension FoggStatusX on StateController<FoggStatus> {
  void goTravelingMock({
    FoggCity from = _tokio,
    FoggCity to = _sanFrancisco,
    TransportMode mode = TransportMode.ship,
    Duration duration = const Duration(days: 1, hours: 2),
    int price = 5000,
    bool sleeper = true,
  }) {
    state = _mockTraveling(from: from, to: to, mode: mode, durationFromNow: duration, price: price, sleeper: sleeper);
  }

  void goArrivedMock() => state = _defaultArrived();
  void goDefaultTraveling() => state = _defaultTraveling();
}

/// Selección en estado llegado — ciudad y vehículo elegidos (null = sin elegir).
final selectedDestinationProvider = StateProvider<DestinationOption?>((ref) => null);
final selectedVehicleProvider = StateProvider<VehicleOption?>((ref) => null);
