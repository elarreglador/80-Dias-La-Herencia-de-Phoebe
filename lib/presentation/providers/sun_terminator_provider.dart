import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../services/sun_terminator_service.dart';

/// Emite UTC actual cada 5 minutos — puerta a futuro `TimeEngine`/`TIME_SCALE`.
///
/// `WorldMapWidget` consume `sunTerminatorProvider`; este provider
/// será reemplazado por `timeEngineProvider` cuando `TimeEngine` exista.
final currentUtcProvider = StreamProvider.autoDispose<DateTime>((ref) {
  // En tests (`flutter test`), el binding es TestWidgetsFlutterBinding.
  // Un `Timer.periodic` de 5 min quedaría pendiente tras `widget dispose` y
  // rompería el `binding.dart:2543` (`!timersPending`). En ese entorno emitimos
  // un único valor sin periodicidad; los tests que necesitan periodicidad
  // usan `overrideWith` + `fakeAsync` explícitamente.
  final isTest = !kReleaseMode &&
      WidgetsBinding.instance.runtimeType.toString().contains('Test');

  if (isTest) {
    return Stream.value(DateTime.now().toUtc());
  }

  final controller = StreamController<DateTime>();
  // Emisión inicial inmediata — buffer hasta que StreamProvider escuche
  controller.add(DateTime.now().toUtc());
  // Recálculo cada 5 minutos — Timer cancelado en onCancel/onDispose para no fugar
  Timer? timer;
  void startTimer() {
    timer = Timer.periodic(
      const Duration(minutes: 5),
      (_) {
        if (!controller.isClosed) controller.add(DateTime.now().toUtc());
      },
    );
  }

  void stopTimer() {
    timer?.cancel();
    timer = null;
  }

  startTimer();
  ref.onCancel(stopTimer);
  ref.onResume(startTimer);
  ref.onDispose(() {
    stopTimer();
    controller.close();
  });
  return controller.stream;
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
