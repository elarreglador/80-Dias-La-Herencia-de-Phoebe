import 'package:flutter/foundation.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

/// Límites mundiales — usados para contener la cámara sin salto antimeridiano.
final worldBounds = LatLngBounds(
  const LatLng(-90, -180),
  const LatLng(90, 180),
);

/// Centro inicial del mapa — el centro del mundo (primo meridiano).
///
/// Es el único centro que siempre satisface la constraint de contención
/// a cualquier zoom: con el viewport más ancho que el mundo, `contain`
/// devuelve `null` y entra el `containCenter` de reserva.
const worldCenter = LatLng(0, 0);

/// Contención híbrida: intenta `contain` (bordes dentro del mundo) y si
/// el zoom es tan bajo que el mundo cabe entero en el viewport (`contain`
/// devuelve null), cae a `containCenter` que siempre sujeta el centro.
/// Así, por mucho que se arrastre horizontalmente, el mapa se detiene en
/// el borde en lugar de saltar al otro extremo del antimeridiano.
class ContainWithFallback extends CameraConstraint {
  const ContainWithFallback(this.bounds);
  final LatLngBounds bounds;

  @override
  MapCamera? constrain(MapCamera camera) {
    final contain = CameraConstraint.contain(bounds: bounds).constrain(camera);
    if (contain != null) return contain;
    return CameraConstraint.containCenter(bounds: bounds).constrain(camera);
  }

  @override
  bool operator ==(Object other) =>
      other is ContainWithFallback && other.bounds == bounds;

  @override
  int get hashCode => bounds.hashCode;

  @override
  String toString() => 'ContainWithFallback(bounds: $bounds) — wraps ContainCamera';
}

/// CRS Mercator sin repetición horizontal — mundo finito.
/// `Epsg3857` por defecto tiene `replicatesWorldLongitude==true` y envuelve
/// el mapa infinitamente (arrastrar más allá de 180 reaparece en -180).
/// Sobrescribiendo a `false`, el mapa se detiene en el antimeridiano y
/// muestra el `backgroundColor` más allá, sin salto.
@immutable
class Epsg3857NoRepeat extends Epsg3857 {
  const Epsg3857NoRepeat();
  @override
  bool get replicatesWorldLongitude => false;
}
