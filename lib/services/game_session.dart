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
import '../domain/models/road_rest_type.dart';
import 'budget_service.dart';
import 'default_cities.dart';
import 'geo_pricing.dart';
import 'hotel_pricing.dart';
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
      fatigue: _fatigue,
    );
    _arrivedAtUtc = timeEngine.now().toUtc();
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

  /// Descanso en hotel en curso — flag transitorio (SPEC 022 §6): no es un
  /// `FoggStatus`, el descanso es una acción sobre el estado de llegada.
  bool _restingAtHotel = false;

  /// Momento (reloj de juego, UTC) en que Phoebe llegó a la ciudad actual.
  DateTime? _arrivedAtUtc;

  /// Momento de la última llamada a `tick()`, usado para calcular delta en la
  /// rama de "llegado a ciudad": evita la acumulación super-lineal al aplicar
  /// el drenaje/recuperación por intervalo de 1 segundo en lugar de total.
  DateTime? _lastTickTime;

  /// Auditoría del vehículo elegido para "Iniciar trayecto". Si startLeg()
  /// lanza excepción, se restaura este vehículo en lugar de dejarlo cancelado
  /// por impactos meteorológicos, de modo que el botón nunca parezca sin
  /// respuesta ni el candidato de coche quede persistingemente deshabilitado.
  VehicleOption? _selectedVehicle;

  VehicleOption? get selectedVehicle => _selectedVehicle;

  void setSelectedVehicle(VehicleOption v) => _selectedVehicle = v;

  FoggStatus get status => _status;
  FoggLeg? get currentLeg => _currentLeg;
  FoggCity get currentCity => _currentCity;
  Fatigue get fatigue => _fatigue;

  /// Descanso en hotel en curso — flag transitorio (SPEC 022 §6): no es un
  /// `FoggStatus`, el descanso es una acción sobre el estado de llegada.
  bool get restingAtHotel => _restingAtHotel;

  /// Importe de la noche de hotel: tarifa por zona geográfica × multiplicador país.
  int get hotelPrice {
    final zone = GeoPricing.zoneForTimezone(_currentCity.timezone);
    return HotelPricing.priceFor(
      zone,
      countryMultiplier: GeoPricing.countryMultiplierForTimezone(_currentCity.timezone),
    );
  }

  /// Importe del hostel de carretera: 70% del hotel de la misma zona/país.
  int get hostelPrice {
    final zone = GeoPricing.zoneForTimezone(_currentCity.timezone);
    return HotelPricing.hostelPriceFor(
      zone,
      countryMultiplier: GeoPricing.countryMultiplierForTimezone(_currentCity.timezone),
    );
  }

  /// Inicia el descanso en hotel en la ciudad actual: descuenta el importe
  /// de la noche y fija el flag de descanso.
  void beginRestAtHotel() {
    budget.spend(hotelPrice, '${_currentCity.name} descanso en hotel');
    _restingAtHotel = true;
  }

  /// Termina el descanso en hotel (al iniciar la ruta o al cancelar).
  void endRestAtHotel() => _restingAtHotel = false;

  /// Despierta a Phoebe en ruta y reanuda el tramo (SPEC 023).
  void wakeUpOnRoute() {
    final traveling = _status;
    if (traveling is! FoggTraveling) return;
    final leg = traveling.leg;
    if (leg.restType == null) return;
    _resumeFromRest(leg, timeEngine.now());
    _status = FoggTraveling(leg: _currentLeg!, fatigue: _fatigue);
    _emit();
  }

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
    // El descanso se interrumpe al iniciar la ruta: arranca el viaje.
    _restingAtHotel = false;
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
    _status = FoggTraveling(leg: leg, fatigue: _fatigue);
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
    if (traveling is FoggTraveling) {
      final leg = traveling.leg;
      final now = timeEngine.now();

      // Descanso en ruta en curso (SPEC 023): recuperar fatiga y, al llegar
      // al 100%, reanudar el tramo automáticamente.
      if (leg.restType != null) {
        final elapsedHours = _lastTickTime == null
            ? now.difference(leg.restStartedAtUtc!).inMinutes / 60.0
            : now.difference(_lastTickTime!).inMinutes / 60.0;
        _fatigue = _fatigue.recover(elapsedHours * leg.restType!.recoveryRate);
        if (_fatigue.value >= 100.0) {
          _resumeFromRest(leg, now);
          _status = FoggTraveling(leg: _currentLeg!, fatigue: _fatigue);
        } else {
          _status = FoggTraveling(leg: leg, fatigue: _fatigue);
        }
        _lastTickTime = now;
        _emit();
        return;
      }

      if (now.isBefore(leg.arrivalUtc)) {
        final elapsedHours = now.difference(leg.departureUtc).inMinutes / 60.0;
        final newFatigue = _advanceFatigue(elapsedHours, leg);
        // Agotamiento en tramo en coche → descanso en ruta (SPEC 023).
        if (newFatigue.mustSleep && leg.transport == TransportMode.car) {
          _fatigue = const Fatigue(value: 0.0);
          var type = RoadRestType.roll();
          if (type.isPaid) {
            final price = type == RoadRestType.hotel ? hotelPrice : hostelPrice;
            if (!budget.canAfford(price)) {
              type = RoadRestType.serviceArea;
            } else {
              budget.spend(price, '${_currentCity.name} descanso en carretera ${type.label}');
            }
          }
          final progress = leg.progressAt(now).clamp(0.0, 1.0);
          final restLeg = FoggLeg(
            from: leg.from,
            to: leg.to,
            transport: leg.transport,
            departureUtc: leg.departureUtc,
            arrivalUtc: leg.arrivalUtc,
            price: leg.price,
            sleeper: leg.sleeper,
            path: leg.path,
            priceBreakdown: leg.priceBreakdown,
            restType: type,
            restStartedAtUtc: now,
            restProgress: progress,
          );
          _currentLeg = restLeg;
          _lastTickTime = now;
          _status = FoggTraveling(leg: restLeg, fatigue: _fatigue);
          _emit();
          return;
        }
        _fatigue = newFatigue;
        // Nueva instancia del estado: el reloj publica el avance para que la
        // pantalla (posición de Phoebe, tramo recorrido) se repinte.
        _status = FoggTraveling(leg: leg, fatigue: _fatigue);
        _emit();
        return;
      }

      final totalHours = leg.arrivalUtc.difference(leg.departureUtc).inMinutes / 60.0;
      _fatigue = _advanceFatigue(totalHours, leg);
      _currentCity = leg.to;
      _currentLeg = null;
      _completedLegs.add(leg);
      _arrivedAtUtc = now;
      _status = FoggArrived(
        currentCity: leg.to,
        options: _buildOptions(leg.to),
        fatigue: _fatigue,
      );
      _emit();
      return;
    }

    // En destino: descanso en hotel o espera en ciudad (drena).
    final now = timeEngine.now();
    final elapsedHours = _lastTickTime == null
        ? now.difference(_arrivedAtUtc!).inMinutes / 60.0
        : now.difference(_lastTickTime!).inMinutes / 60.0;
    _lastTickTime = now;
    if (restingAtHotel) {
      _fatigue = _fatigue.recover(elapsedHours * Fatigue.hotelRecoverRate);
    } else {
      _fatigue = _fatigue.drain(elapsedHours * Fatigue.cityDrainRate);
    }
    final arrived = _status as FoggArrived;
    _status = FoggArrived(
      currentCity: arrived.currentCity,
      options: arrived.options,
      fatigue: _fatigue,
    );
    _emit();
  }

  void _resumeFromRest(FoggLeg leg, DateTime now) {
    final restDuration = now.difference(leg.restStartedAtUtc!);
    final newLeg = FoggLeg(
      from: leg.from,
      to: leg.to,
      transport: leg.transport,
      departureUtc: leg.departureUtc.add(restDuration),
      arrivalUtc: leg.arrivalUtc.add(restDuration),
      price: leg.price,
      sleeper: leg.sleeper,
      path: leg.path,
      priceBreakdown: leg.priceBreakdown,
    );
    _currentLeg = newLeg;
    _legStartFatigue = _fatigue.value;
    _lastTickTime = now;
  }

  /// Avanza la fatiga a lo largo de un tramo: recupera en sleeper, drena en
  /// coche o modos sin sleeper (mocks).
  Fatigue _advanceFatigue(double elapsedHours, FoggLeg leg) {
    if (leg.sleeper) {
      return Fatigue(
        value: (_legStartFatigue + elapsedHours * Fatigue.sleeperRecoverRate).clamp(0.0, 100.0),
      );
    }
    final rate = leg.transport == TransportMode.car ? Fatigue.carDrainRate : Fatigue.genericDrainRate;
    return Fatigue(value: (_legStartFatigue - elapsedHours * rate).clamp(0.0, 100.0));
  }

  void sleep({Duration? duration}) {
    if (duration == null) {
      _fatigue = const Fatigue(value: 100.0);
    } else {
      final recovered = (_fatigue.value + duration.inMinutes / 60.0 * 20.0)
          .clamp(0.0, 100.0);
      _fatigue = Fatigue(value: recovered);
    }
    _status = switch (_status) {
      FoggTraveling(:final leg) => FoggTraveling(leg: leg, fatigue: _fatigue),
      FoggArrived(:final currentCity, :final options) => FoggArrived(
          currentCity: currentCity,
          options: options,
          fatigue: _fatigue,
        ),
    };
    _emit();
  }

  void simulateArrival() {
    final traveling = _status;
    if (traveling is! FoggTraveling) return;
    _legStartFatigue = _fatigue.value;
    _arrivedAtUtc = timeEngine.now().toUtc();
    _currentCity = traveling.leg.to;
    _currentLeg = null;
    _completedLegs.add(traveling.leg);
    _status = FoggArrived(
      currentCity: traveling.leg.to,
      options: _buildOptions(traveling.leg.to),
      fatigue: _fatigue,
    );
    _emit();
  }

  List<DestinationOption> _buildOptions(FoggCity current) {
    final selector = _transportSelector;
    if (selector != null) {
      try {
        final selected = selector.optionsFor(current, hasCar: _hasCar);
        if (selected.isNotEmpty) return selected;
      } catch (_) {
        // fallback mock
      }
    }
    return mockDestinationOptions(current: current, cities: _cities);
  }

  /// Phoebe conserva el coche solo si el último tramo completado fue en
  /// coche. Si cambia de modo, el vehículo se queda (o se devuelve) y en el
  /// siguiente destino vuelve a pagar alquiler (SPEC 019 addenda §11).
  bool get _hasCar =>
      _completedLegs.isNotEmpty &&
      _completedLegs.last.transport == TransportMode.car;
}
