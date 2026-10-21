import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pf/services/route_catalog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('RouteCatalog.load carga los 3 JSON', () async {
    final catalog = await RouteCatalog.load(rootBundle);
    expect(catalog.byOrigin.isNotEmpty, isTrue);
    var total = 0;
    for (final v in catalog.byOrigin.values) {
      total += v.length;
    }
    expect(total, greaterThan(1000));
  });

  test('indexación por origen', () async {
    final catalog = await RouteCatalog.load(rootBundle);
    final routes = catalog.routesFrom('Londres');
    expect(routes, isNotEmpty);
  });

  test('marítimas durationHours null, terrestres no', () async {
    final catalog = await RouteCatalog.load(rootBundle);
    final all = catalog.byOrigin.values.expand((e) => e).toList();
    final sea = all.where((r) => r.source.toString().contains('sea')).toList();
    final car = all.where((r) => r.source.toString().contains('car')).toList();
    expect(sea.any((r) => r.durationHours == null), isTrue);
    expect(car.every((r) => r.durationHours != null), isTrue);
  });
}
