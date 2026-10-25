import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../domain/entities/fogg_city.dart';
import '../../domain/entities/fogg_leg.dart';
import '../../domain/entities/fogg_status.dart';
import '../../domain/entities/transport_mode.dart';
import '../../domain/models/route_path.dart';
import '../../services/city_catalog.dart';
import '../../utils/app_colors.dart';

const _labelColor = Color(0xFF1A1A1A);

/// Color del trazado según el modo de transporte.
Color routeColor(TransportMode mode) => switch (mode) {
      TransportMode.ship => AppColors.routeShip,
      TransportMode.train => AppColors.routeTrain,
      TransportMode.car => AppColors.routeCar,
      _ => AppColors.routeCandidate,
    };

/// Polilíneas del mapa — historial, tramo activo y candidatas.
List<Polyline> buildRoutePolylines({
  required FoggStatus status,
  required DateTime now,
  required List<FoggLeg> completedLegs,
}) {
  final polylines = <Polyline>[];

  // Historial — cada tramo ya recorrido en el color de su modo, 2 px.
  for (final leg in completedLegs) {
    final path = leg.path;
    if (path == null) continue;
    final color = routeColor(leg.transport);
    for (final segment in path.renderSegments()) {
      polylines.add(Polyline(
        points: segment,
        color: color,
        strokeWidth: 2.0,
      ));
    }
  }

  switch (status) {
    case FoggTraveling(leg: final leg):
      final path = leg.path;
      if (path == null) break;
      final color = routeColor(leg.transport);
      final parts = path.splitAt(leg.progressAt(now));
      // Parte recorrida — sólida, 4 px.
      for (final segment in RoutePath.splitAtAntimeridian(parts.traveled)) {
        polylines.add(Polyline(
          points: segment,
          color: color,
          strokeWidth: 4.0,
        ));
      }
      // Parte pendiente — discontinua, 4 px.
      for (final segment in RoutePath.splitAtAntimeridian(parts.pending)) {
        polylines.add(Polyline(
          points: segment,
          color: color,
          strokeWidth: 4.0,
          pattern: StrokePattern.dashed(segments: const [12, 8]),
        ));
      }
    case FoggArrived(options: final options):
      // Candidatas — solo en ciudad y sin trayecto elegido.
      for (final option in options) {
        for (final vehicle in option.vehicles) {
          final route = vehicle.route;
          if (route == null) continue;
          final path = RoutePath.fromGeometry(route.geometry);
          if (path == null) continue;
          for (final segment in path.renderSegments()) {
            polylines.add(Polyline(
              points: segment,
              color: AppColors.routeCandidate.withValues(alpha: 0.35),
              strokeWidth: 2.0,
            ));
          }
        }
      }
  }

  return polylines;
}

/// Marcadores del tramo activo — origen y destino.
List<Marker> buildLegMarkers({
  required FoggStatus status,
  CityCatalog? catalog,
}) {
  switch (status) {
    case FoggTraveling(leg: final leg):
      return [
        _cityMarker(_canonical(leg.from, catalog)),
        _cityMarker(_canonical(leg.to, catalog)),
      ];
    case FoggArrived():
      return const [];
  }
}

/// Ciudad canónica del catálogo — las coordenadas reales del city catalog
/// mandan sobre las de la partida, para que el marcador caiga exacto
/// sobre el vértice de la ruta.
FoggCity _canonical(FoggCity city, CityCatalog? catalog) =>
    catalog?.byName(city.name) ?? city;

/// Marcador de ciudad — punto rojo con etiqueta.
Marker _cityMarker(FoggCity city) {
  return Marker(
    point: LatLng(city.lat, city.lng),
    width: 80,
    height: 60,
    alignment: Alignment.center,
    child: Stack(
      alignment: Alignment.center,
      children: [
        // Punto rojo centrado exactamente en LatLng — la polyline pasa por aquí
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: AppColors.foggRed,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
          ),
        ),
        // Label 22px por encima del punto (dy -22) + halo blanco 0.6
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                city.name,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: _labelColor,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      ],
    ),
  );
}
