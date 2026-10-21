import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/route_catalog.dart';
import '../../services/transport_selector.dart';

final routeCatalogProvider = FutureProvider<RouteCatalog>((ref) async {
  return RouteCatalog.load(rootBundle);
});

final transportSelectorProvider = Provider<TransportSelector?>((ref) {
  final catalog = ref.watch(routeCatalogProvider).valueOrNull;
  if (catalog == null) return null;
  return TransportSelector(catalog: catalog);
});
