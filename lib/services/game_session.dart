import 'dart:async';

import 'package:latlong2/latlong.dart';

import '../domain/entities/destination_option.dart';
import '../domain/entities/fogg_city.dart';
import '../domain/entities/fogg_leg.dart';
import '../domain/entities/fogg_status.dart';
import '../domain/entities/transport_mode.dart';
import '../domain/models/route_path.dart';
import '../domain/models/travel_event.dart';
import '../domain/models/weather_snapshot.dart';
import 'event_engine.dart';
import '../domain/models/fatigue.dart';
import 'budget_service.dart';
import 'time_engine.dart';
import 'transport_selector.dart';

class SleepRequiredException implements Exception {
  const SleepRequiredException();

  @override
  String toString() => 'SleepRequiredException';
}

class WeatherCancellationException implements Exception {
  const WeatherCancellationException(this.reason);

  final String? reason;

  @override
  String toString() => 'WeatherCancellationException: $reason';
}

class GameSession {
  GameSession({
    required this.timeEngine,
    required this.budget,
    List<FoggCity>? cities,
    TransportSelector? transportSelector,
    EventEngine? eventEngine,
    WeatherSnapshot? weatherSnapshot,
  }) : _cities = cities ?? _defaultCities,
       _transportSelector = transportSelector,
       _eventEngine = eventEngine,
       _weatherSnapshot = weatherSnapshot {
    _status = FoggArrived(
      currentCity: _currentCity,
      options: _buildOptions(_currentCity),
    );
  }

  final TimeEngine timeEngine;
  final BudgetService budget;
  final List<FoggCity> _cities;
  final TransportSelector? _transportSelector;
  final EventEngine? _eventEngine;
  final WeatherSnapshot? _weatherSnapshot;

  late FoggStatus _status;
  FoggCity _currentCity = _defaultCities[0];
  Fatigue _fatigue = const Fatigue();
  double _legStartFatigue = 100.0;
  FoggLeg? _currentLeg;
  final List<FoggLeg> _completedLegs = [];

  FoggStatus get status => _status;
  FoggLeg? get currentLeg => _currentLeg;
  FoggCity get currentCity => _currentCity;
  Fatigue get fatigue => _fatigue;

  /// Tramos ya recorridos — el historial que se dibuja en el mapa.
  List<FoggLeg> get completedLegs => List<FoggLeg>.unmodifiable(_completedLegs);

  List<DestinationOption> get options {
    if (_status is FoggArrived) return (_status as FoggArrived).options;
    return const [];
  }

  Stream<FoggStatus> get statusStream => _statusController.stream;
  final _statusController = StreamController<FoggStatus>.broadcast();

  void _emit() => _statusController.add(_status);

  void startLeg({
    required FoggCity from,
    required FoggCity to,
    required VehicleOption vehicle,
    WeatherSnapshot? weather,
  }) {
    if (_fatigue.mustSleep && !vehicle.sleeper) {
      throw const SleepRequiredException();
    }
    if (!budget.canAfford(vehicle.price)) {
      throw InsufficientBudgetException(vehicle.price, budget.balance);
    }
    if (vehicle.weatherImpact != null && vehicle.weatherImpact!.cancelled) {
      throw WeatherCancellationException(vehicle.weatherImpact!.reason);
    }

    _legStartFatigue = _fatigue.value;

    budget.spend(vehicle.price, '${from.name}->${to.name} ${vehicle.mode.label}');

    final departure = timeEngine.nextScheduledDeparture(
      timeEngine.now(),
      originTimezone: from.timezone,
      departureHour: vehicle.departureHour,
      departureMinute: vehicle.departureMinute,
      sleeper: vehicle.sleeper,
    );
    var arrival = departure.add(vehicle.duration);

    final engine = _eventEngine;
    if (engine != null) {
      try {
        final snapshot = weather ?? _weatherSnapshot ?? WeatherSnapshot(timestampUtc: departure.toUtc());
        final rollLeg = FoggLeg(
          from: from,
          to: to,
          transport: vehicle.mode,
          departureUtc: departure,
          arrivalUtc: arrival,
          price: vehicle.price,
          sleeper: vehicle.sleeper,
        );
        final events = engine.roll(leg: rollLeg, weather: snapshot);
        for (final event in events) {
          if (event is DelayEvent) {
            arrival = arrival.add(Duration(minutes: (event.hours * 60).round()));
          }
          if (event is StormEvent) {
            _fatigue = _fatigue.drain(event.extraFatigue);
          }
        }
        if (events.any((e) => e is StormEvent)) {
          _legStartFatigue = _fatigue.value;
        }
      } catch (_) {
        // fallback: comportamiento actual
      }
    }

    final leg = FoggLeg(
      from: from,
      to: to,
      transport: vehicle.mode,
      departureUtc: departure,
      arrivalUtc: arrival,
      price: vehicle.price,
      sleeper: vehicle.sleeper,
      path: _buildPath(from, to, vehicle),
    );

    _currentCity = from;
    _currentLeg = leg;
    _status = FoggTraveling(leg: leg);
    _emit();
  }

  /// Geometría del tramo: la real del catálogo si el vehículo la trae,
  /// si no una recta de origen a destino (mocks).
  static RoutePath _buildPath(FoggCity from, FoggCity to, VehicleOption vehicle) {
    final route = vehicle.route;
    if (route != null) {
      final geometry = RoutePath.fromGeometry(route.geometry);
      if (geometry != null) return geometry;
    }
    return RoutePath.straight(
      LatLng(from.lat, from.lng),
      LatLng(to.lat, to.lng),
    );
  }

  void tick() {
    final traveling = _status;
    if (traveling is! FoggTraveling) return;
    final leg = traveling.leg;
    final now = timeEngine.now();
    if (now.isBefore(leg.arrivalUtc)) {
      final elapsedHours = now.difference(leg.departureUtc).inMinutes / 60.0;
      final drain = (elapsedHours * 5.0).clamp(0.0, 100.0);
      _fatigue = Fatigue(value: (_legStartFatigue - drain).clamp(0.0, 100.0));
      // Nueva instancia del estado: el reloj publica el avance para que la
      // pantalla (posición de Phoebe, tramo recorrido) se repinte.
      _status = FoggTraveling(leg: leg);
      _emit();
      return;
    }

    final totalHours = leg.arrivalUtc.difference(leg.departureUtc).inMinutes / 60.0;
    final drain = (totalHours * 5.0).clamp(0.0, 100.0);
    _fatigue = Fatigue(value: (_legStartFatigue - drain).clamp(0.0, 100.0));
    _currentCity = leg.to;
    _currentLeg = null;
    _completedLegs.add(leg);
    _status = FoggArrived(
      currentCity: leg.to,
      options: _buildOptions(leg.to),
    );
    _emit();
  }

  void sleep({Duration? duration}) {
    if (duration == null) {
      _fatigue = const Fatigue(value: 100.0);
    } else {
      final recovered = (_fatigue.value + duration.inMinutes / 60.0 * 20.0)
          .clamp(0.0, 100.0);
      _fatigue = Fatigue(value: recovered);
    }
    _emit();
  }

  void simulateArrival() {
    final traveling = _status;
    if (traveling is! FoggTraveling) return;
    _legStartFatigue = _fatigue.value;
    _currentCity = traveling.leg.to;
    _currentLeg = null;
    _completedLegs.add(traveling.leg);
    _status = FoggArrived(
      currentCity: traveling.leg.to,
      options: _buildOptions(traveling.leg.to),
    );
    _emit();
  }

  void simulateDeparture() {
    _status = FoggTraveling(leg: _defaultLeg());
    _currentLeg = (_status as FoggTraveling).leg;
    _legStartFatigue = _fatigue.value;
    _emit();
  }

  List<DestinationOption> _buildOptions(FoggCity current) {
    final selector = _transportSelector;
    if (selector != null) {
      try {
        final selected = selector.optionsFor(current);
        if (selected.isNotEmpty) return selected;
      } catch (_) {
        // fallback mock
      }
    }
    final candidates = _cities
        .where((c) => c != current && _isEast(current, c))
        .toList()
      ..sort((a, b) => _eastDistance(current, a).compareTo(_eastDistance(current, b)));
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

  bool _isEast(FoggCity from, FoggCity to) {
    double unfold(double lng, double base) {
      var x = lng;
      while (x <= base) {
        x += 360;
      }
      return x;
    }

    return unfold(to.lng, from.lng) > from.lng;
  }

  double _eastDistance(FoggCity from, FoggCity to) {
    double unfold(double lng, double base) {
      var x = lng;
      while (x <= base) {
        x += 360;
      }
      return x;
    }

    return (unfold(to.lng, from.lng) - from.lng).abs();
  }

  static List<FoggCity> get _defaultCities => const [
        FoggCity(name: 'Londres', lat: 51.5072, lng: -0.1276, order: 0, timezone: 'Europe/London'),
        FoggCity(name: 'París', lat: 48.8566, lng: 2.3522, order: 1, timezone: 'Europe/Paris'),
        FoggCity(name: 'Estambul', lat: 41.0082, lng: 28.9784, order: 2, timezone: 'Europe/Istanbul'),
        FoggCity(name: 'Bombay', lat: 19.0760, lng: 72.8777, order: 3, timezone: 'Asia/Kolkata'),
        FoggCity(name: 'Tokio', lat: 35.6762, lng: 139.6503, order: 4, timezone: 'Asia/Tokyo'),
        FoggCity(name: 'San Francisco', lat: 37.7749, lng: -122.4194, order: 5, timezone: 'America/Los_Angeles'),
        FoggCity(name: 'Nueva York', lat: 40.7128, lng: -74.0060, order: 6, timezone: 'America/New_York'),
        FoggCity(name: 'Savile Row', lat: 51.5107, lng: -0.1410, order: 7, timezone: 'Europe/London'),
      ];

  static FoggLeg _defaultLeg() {
    final now = DateTime.now().toUtc();
    return FoggLeg(
      from: _defaultCities[3],
      to: _defaultCities[4],
      transport: TransportMode.train,
      departureUtc: now.subtract(const Duration(hours: 2)),
      arrivalUtc: now.add(const Duration(days: 1, hours: 5)),
      price: 4200,
      sleeper: true,
    );
  }
}
