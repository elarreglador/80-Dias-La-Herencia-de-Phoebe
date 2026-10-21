import 'dart:convert';

import 'package:flutter/services.dart';

import '../domain/models/route_entry.dart';

class RouteCatalog {
  RouteCatalog(this.byOrigin);

  final Map<String, List<RouteEntry>> byOrigin;

  List<RouteEntry> routesFrom(String origin) => byOrigin[origin] ?? const [];

  static Future<RouteCatalog> load(AssetBundle bundle) async {
    final merged = <String, List<RouteEntry>>{};

    final files = <(String, RouteSource)>[
      ('assets/data/sea_routes.json', RouteSource.sea),
      ('assets/data/car_routes.json', RouteSource.car),
      ('assets/data/rail_routes.json', RouteSource.rail),
    ];

    for (final (path, source) in files) {
      List<dynamic> routes;
      try {
        final raw = await bundle.loadString(path);
        final decoded = jsonDecode(raw);
        if (decoded is! Map<String, dynamic>) continue;
        final list = decoded['routes'];
        if (list is! List) continue;
        routes = list;
      } catch (_) {
        continue;
      }

      for (final item in routes) {
        if (item is! Map<String, dynamic>) continue;
        final r = item;
        final origin = r['origin'];
        final destination = r['destination'];
        final distance = r['distanceKm'];
        if (origin is! String || destination is! String) continue;
        if (distance is! num) continue;

        final durationRaw = r['durationHours'];
        final double? durationHours =
            durationRaw is num ? durationRaw.toDouble() : null;

        final heading = r['heading'] is String ? r['heading'] as String : 'east';

        final geomRaw = r['geometry'];
        final coords = <List<double>>[];
        if (geomRaw is Map<String, dynamic>) {
          final c = geomRaw['coordinates'];
          if (c is List) {
            for (final pt in c) {
              if (pt is List && pt.length >= 2) {
                final x = pt[0];
                final y = pt[1];
                if (x is num && y is num) {
                  coords.add([x.toDouble(), y.toDouble()]);
                }
              }
            }
          }
        }
        if (coords.isEmpty) continue;

        final entry = RouteEntry(
          source: source,
          origin: origin,
          destination: destination,
          distanceKm: distance.toDouble(),
          durationHours: durationHours,
          heading: heading,
          geometry: coords,
        );
        merged.putIfAbsent(origin, () => <RouteEntry>[]).add(entry);
      }
    }

    return RouteCatalog(merged);
  }
}
