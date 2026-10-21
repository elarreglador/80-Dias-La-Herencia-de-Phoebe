import '../entities/transport_mode.dart';

enum RouteSource { sea, car, rail }

class RouteEntry {
  const RouteEntry({
    required this.source,
    required this.origin,
    required this.destination,
    required this.distanceKm,
    this.durationHours,
    required this.heading,
    required this.geometry,
  });

  final RouteSource source;
  final String origin;
  final String destination;
  final double distanceKm;
  final double? durationHours;
  final String heading;
  final List<List<double>> geometry;

  TransportMode get mode => switch (source) {
        RouteSource.sea => TransportMode.ship,
        RouteSource.car => TransportMode.car,
        RouteSource.rail => TransportMode.train,
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RouteEntry &&
          source == other.source &&
          origin == other.origin &&
          destination == other.destination &&
          distanceKm == other.distanceKm &&
          durationHours == other.durationHours &&
          heading == other.heading &&
          _listEquals(geometry, other.geometry);

  @override
  int get hashCode => Object.hash(
        source,
        origin,
        destination,
        distanceKm,
        durationHours,
        heading,
        geometry.length,
      );

  static bool _listEquals(List<List<double>> a, List<List<double>> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].length != b[i].length) return false;
      for (var j = 0; j < a[i].length; j++) {
        if (a[i][j] != b[i][j]) return false;
      }
    }
    return true;
  }
}
