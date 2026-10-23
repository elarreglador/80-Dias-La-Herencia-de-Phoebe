import '../domain/entities/destination_option.dart';
import '../domain/entities/fogg_city.dart';
import '../domain/entities/transport_mode.dart';
import '../domain/models/route_entry.dart';
import 'city_catalog.dart';
import 'route_catalog.dart';
import 'weather_service.dart';
import '../domain/models/weather_impact.dart';

class Tariff {
  const Tariff({required this.pricePerKm, required this.speedKmh, required this.sleeper});
  final double pricePerKm;
  final double speedKmh;
  final bool sleeper;
}

class TariffTable {
  static const defaults = <TransportMode, Tariff>{
    TransportMode.ship: Tariff(pricePerKm: 1.2, speedKmh: 25, sleeper: true),
    TransportMode.train: Tariff(pricePerKm: 0.8, speedKmh: 80, sleeper: true),
    TransportMode.car: Tariff(pricePerKm: 0.6, speedKmh: 60, sleeper: false),
  };
}

class TransportSelector {
  TransportSelector({
    required this.catalog,
    this.cityCatalog,
    this.tariffs = TariffTable.defaults,
    this.weatherService,
    this.now,
  });

  final RouteCatalog catalog;

  /// Catálogo de ciudades — resuelve el destino con coordenadas y
  /// `timezone` IANA reales. Si es `null`, el destino se deriva del último
  /// vértice de la geometría.
  final CityCatalog? cityCatalog;

  final Map<TransportMode, Tariff> tariffs;
  final WeatherService? weatherService;
  final DateTime? now;

  List<DestinationOption> optionsFor(FoggCity current, {int limit = 3}) {
    final routes = catalog.routesFrom(current.name);
    // Agrupa por destino.
    final byDestination = <String, List<RouteEntry>>{};
    for (final r in routes) {
      byDestination.putIfAbsent(r.destination, () => <RouteEntry>[]).add(r);
    }

    final candidates = <_Candidate>[];
    for (final entry in byDestination.entries) {
      final destName = entry.key;
      final rs = entry.value;
      // Ciudad destino: el catálogo manda (coordenadas + timezone IANA);
      // si la ciudad no está, se deriva del último vértice de la geometría.
      final city = cityCatalog?.byName(destName) ?? _cityFromGeometry(destName, rs);
      if (city == null) continue;

      // Regla del Este: lng desenrollada > current.lng.
      if (!_isEast(current.lng, city.lng)) continue;

      candidates.add(_Candidate(city: city, routes: rs));
    }

    candidates.sort((a, b) =>
        _unfold(a.city.lng, current.lng).compareTo(_unfold(b.city.lng, current.lng)));

    final top = candidates.take(limit).toList();
    return top.map((c) => _buildOption(current, c)).toList();
  }

  /// Ciudad destino derivada del último vértice de la geometría.
  ///
  /// Recurso de último término: sin catálogo, el `timezone` queda en 'UTC'.
  static FoggCity? _cityFromGeometry(String destName, List<RouteEntry> routes) {
    for (final r in routes) {
      if (r.geometry.isNotEmpty && r.geometry.last.length >= 2) {
        final pt = r.geometry.last;
        return FoggCity(
          name: destName,
          lat: pt[1],
          lng: pt[0],
          order: 0,
          timezone: 'UTC',
        );
      }
    }
    return null;
  }

  DestinationOption _buildOption(FoggCity current, _Candidate c) {
    final city = c.city;
    // Dedup por modo: menor distanceKm.
    final bestByMode = <TransportMode, RouteEntry>{};
    for (final r in c.routes) {
      final existing = bestByMode[r.mode];
      if (existing == null || r.distanceKm < existing.distanceKm) {
        bestByMode[r.mode] = r;
      }
    }

    final vehicles = <VehicleOption>[];
    final baseNow = (now ?? DateTime.now()).toUtc();
    // Orden fijo de modos reales.
    for (final mode in [TransportMode.ship, TransportMode.train, TransportMode.car]) {
      final route = bestByMode[mode];
      if (route == null) continue;
      final tariff = tariffs[mode] ?? TariffTable.defaults[mode]!;
      final baseDuration = route.durationHours != null
          ? Duration(microseconds: (route.durationHours! * 3600000000).round())
          : Duration(microseconds: ((route.distanceKm / tariff.speedKmh) * 3600000000).round());
      final price = (route.distanceKm * tariff.pricePerKm).round();
      final dep = _departure(mode);
      var duration = baseDuration;
      WeatherImpact? impact;
      final ws = weatherService;
      if (ws != null) {
        var departureUtc = DateTime.utc(baseNow.year, baseNow.month, baseNow.day, dep.$1, dep.$2);
        if (departureUtc.isBefore(baseNow)) {
          departureUtc = departureUtc.add(const Duration(days: 1));
        }
        final arrivalUtc = departureUtc.add(baseDuration);
        final originSnap = ws.fetchSync(current.lat, current.lng, departureUtc);
        final destSnap = ws.fetchSync(city.lat, city.lng, arrivalUtc);
        impact = WeatherImpact.forMode(mode, originSnap, destSnap, departureUtc, arrivalUtc);
        if (!impact.cancelled) {
          duration = baseDuration + impact.delay;
        }
      }
      vehicles.add(VehicleOption(
        mode: mode,
        duration: duration,
        price: price,
        sleeper: tariff.sleeper,
        departureHour: dep.$1,
        departureMinute: dep.$2,
        weatherImpact: impact,
        route: route,
      ));
    }

    return DestinationOption(city: city, vehicles: vehicles);
  }

  static (int, int) _departure(TransportMode mode) {
    switch (mode) {
      case TransportMode.ship:
        return (8, 0);
      case TransportMode.train:
        return (9, 30);
      case TransportMode.car:
        return (7, 0);
      default:
        return (6, 0);
    }
  }

  static bool _isEast(double fromLng, double toLng) {
    return _unfold(toLng, fromLng) > fromLng;
  }

  static double _unfold(double lng, double base) {
    var x = lng;
    while (x <= base) {
      x += 360;
    }
    return x;
  }
}

class _Candidate {
  _Candidate({required this.city, required this.routes});
  final FoggCity city;
  final List<RouteEntry> routes;
}
