import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/city_catalog.dart';
import '../../services/route_catalog.dart';
import '../../services/transport_selector.dart';
import '../../services/weather_service.dart';
import '../../domain/models/weather_snapshot.dart';

final routeCatalogProvider = FutureProvider<RouteCatalog>((ref) async {
  return RouteCatalog.load(rootBundle);
});

/// Catálogo de ciudades — `assets/data/locations.json`.
final cityCatalogProvider = FutureProvider<CityCatalog>((ref) async {
  return CityCatalog.load(rootBundle);
});

final weatherServiceProvider = Provider<WeatherService>((ref) {
  return WeatherService();
});

final transportSelectorProvider = Provider<TransportSelector?>((ref) {
  final catalog = ref.watch(routeCatalogProvider).valueOrNull;
  if (catalog == null) return null;
  return TransportSelector(
    catalog: catalog,
    cityCatalog: ref.watch(cityCatalogProvider).valueOrNull,
    weatherService: ref.watch(weatherServiceProvider),
  );
});

final weatherSnapshotProvider = FutureProvider.family<WeatherSnapshot, (double, double, DateTime)>((ref, params) async {
  return ref.watch(weatherServiceProvider).fetch(params.$1, params.$2, params.$3);
});
