import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/route_catalog.dart';
import '../../services/transport_selector.dart';
import '../../services/weather_service.dart';

final routeCatalogProvider = FutureProvider<RouteCatalog>((ref) async {
  return RouteCatalog.load(rootBundle);
});

final weatherServiceProvider = Provider<WeatherService>((ref) {
  return WeatherService();
});

final transportSelectorProvider = Provider<TransportSelector?>((ref) {
  final catalog = ref.watch(routeCatalogProvider).valueOrNull;
  if (catalog == null) return null;
  return TransportSelector(
    catalog: catalog,
    weatherService: ref.watch(weatherServiceProvider),
  );
});
