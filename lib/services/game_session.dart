import 'dart:async';

import 'package:latlong2/latlong.dart';

import '../domain/entities/destination_option.dart';
import '../domain/entities/fogg_city.dart';
import '../domain/entities/fogg_leg.dart';
import '../domain/entities/fogg_status.dart';
import '../domain/models/route_path.dart';
import '../domain/models/travel_event.dart';
import '../domain/models/weather_snapshot.dart';
import 'event_engine.dart';
import '../domain/models/fatigue.dart';
import 'budget_service.dart';
import 'default_cities.dart';
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
  }) : _cities = cities ?? defaultCities,
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
  FoggCity _currentCity = defaultCities[0];
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

    final departure = timeEngine.now();
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
      priceBreakdown: vehicle.priceBreakdown,
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
    return mockDestinationOptions(current: current, cities: _cities);
  }

}
