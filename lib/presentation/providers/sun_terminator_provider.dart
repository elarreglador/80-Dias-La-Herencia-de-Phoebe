import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../services/sun_terminator_service.dart';
import 'time_engine_provider.dart';

/// Emite el UTC del reloj de juego, acelerado en debug ([debugTimeScale]×).
///
/// Se apoya en `TimeEngine.clock()`, que ya emite cada segundo en producción y
/// un único valor bajo `TestWidgetsFlutterBinding` (sin `Timer.periodic`
/// pendiente, respetando `binding.dart:2543` `!timersPending`). Los tests que
/// necesitan una hora fija siguen usando `currentUtcProvider.overrideWith`.
final currentUtcProvider = StreamProvider.autoDispose<DateTime>((ref) {
  return ref.watch(timeEngineProvider).clock();
});

/// Polígonos nocturnos derivados del UTC actual — fix completo.
///
/// Recalcula vía `SunTerminatorService.nightPolygons` sin intervención
/// del usuario y sin fuga de `Timer` al `dispose` (Riverpod cancela stream).
/// Para `|subLat|<0.5°` (equinoccio) devuelve 2 rectángulos; si no, 1 polígono
/// curvo 183 vértices. Compatible con `Epsg3857NoRepeat` y clamp 85.05°.
final sunTerminatorProvider =
    Provider.autoDispose<List<List<LatLng>>>((ref) {
  final utc = ref.watch(currentUtcProvider).value ?? DateTime.now().toUtc();
  return SunTerminatorService.nightPolygons(utc);
});

/// Alias legacy — polígono único aplanado (1er polígono).
/// Usar [sunTerminatorProvider] para fix completo con split antimeridiano.
final sunTerminatorLegacyProvider = Provider.autoDispose<List<LatLng>>((ref) {
  final polys = ref.watch(sunTerminatorProvider);
  if (polys.isEmpty) return [];
  if (polys.length == 1) return polys.first;
  // Equinoccio 2 polígonos: flatten no es correcto para fill, pero mantiene
  // compatibilidad con código antiguo que espera lista única.
  return polys.first;
});
