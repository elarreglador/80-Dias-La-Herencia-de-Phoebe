import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../domain/entities/fogg_leg.dart';

/// Límites de zoom del mapa — deben coincidir con `MapOptions` en
/// `world_map_widget.dart` (clamp 2..18, ver también `mapZoomProvider`).
const double _mapMinZoom = 2.0;
const double _mapMaxZoom = 18.0;

/// Bounds contiguos (longitud **cruda**) que contienen el origen y el
/// destino del tramo [leg].
///
/// Con `Epsg3857NoRepeat` el mundo se dibuja una sola vez, así que el
/// encuadre trabaja con coordenadas crudas: un tramo que cruza el
/// antimeridiano (p. ej. Fukuoka → Vancouver) produce un span > 180°, lo
/// que impide que ambos puntos quepan a la vez en pantallas estrechas.
LatLngBounds activeLegBounds(FoggLeg leg) {
  final west = leg.from.lng < leg.to.lng ? leg.from.lng : leg.to.lng;
  final east = leg.from.lng < leg.to.lng ? leg.to.lng : leg.from.lng;
  final south = leg.from.lat < leg.to.lat ? leg.from.lat : leg.to.lat;
  final north = leg.from.lat < leg.to.lat ? leg.to.lat : leg.from.lat;
  return LatLngBounds(LatLng(south, west), LatLng(north, east));
}

/// Cámara que encuadra el origen y el destino de [leg] desde la cámara
/// actual [camera] (usa su tamaño real de viewport), o `null` si no caben.
///
/// Devuelve `null` cuando el zoom necesario bajaría de [_mapMinZoom]: solo
/// ocurre con trayectos que cruzan el antimeridiano en pantallas estrechas
/// (el caller debe aplicar su fallback). El zoom nunca supera [_mapMaxZoom].
///
/// La viabilidad se calcula a mano porque `CameraFit` recorta el zoom al
/// `minZoom` de la cámara: con el recorte aplicado nunca se podría
/// distinguir «encuadra a zoom 2» de «necesitaría zoom 1».
MapCamera? fitActiveLeg(
  MapCamera camera,
  FoggLeg leg, {
  EdgeInsets padding = EdgeInsets.zero,
}) {
  final bounds = activeLegBounds(leg);
  final requiredZoom = _requiredZoom(camera, bounds, padding);
  if (requiredZoom < _mapMinZoom) return null;

  final fit = CameraFit.bounds(bounds: bounds, padding: padding).fit(camera);
  if (fit.zoom <= _mapMaxZoom) return fit;
  return fit.withPosition(zoom: _mapMaxZoom);
}

/// Zoom mínimo al que cabrían [bounds] con [padding] en el viewport de
/// [camera], sin recortar a `minZoom`/`maxZoom`.
double _requiredZoom(
  MapCamera camera,
  LatLngBounds bounds,
  EdgeInsets padding,
) {
  final availWidth =
      (camera.nonRotatedSize.width - padding.horizontal).clamp(0.0, double.infinity);
  final availHeight =
      (camera.nonRotatedSize.height - padding.vertical).clamp(0.0, double.infinity);
  final sw = camera.projectAtZoom(bounds.southWest, camera.zoom);
  final ne = camera.projectAtZoom(bounds.northEast, camera.zoom);
  final boundsWidth = (ne.dx - sw.dx).abs();
  final boundsHeight = (ne.dy - sw.dy).abs();
  // Tramo degenerado (origen == destino) → cualquier zoom vale.
  if (boundsWidth == 0 && boundsHeight == 0) return _mapMaxZoom;
  final scaleX = boundsWidth == 0 ? double.infinity : availWidth / boundsWidth;
  final scaleY = boundsHeight == 0 ? double.infinity : availHeight / boundsHeight;
  return camera.getScaleZoom(scaleX < scaleY ? scaleX : scaleY);
}
