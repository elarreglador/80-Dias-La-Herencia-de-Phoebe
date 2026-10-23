import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/time_engine.dart';

/// Factor de aceleración del reloj de juego en builds de depuración.
///
/// En release siempre es 1× (tiempo real); `TimeEngine` también lo fuerza con
/// `kReleaseMode`, pero lo dejamos explícito aquí para que la intención se lea.
const double debugTimeScale = 60.0;

/// Reloj único de la partida. En debug adelanta [debugTimeScale]× para poder
/// ver pasar días, llegadas y el terminador solar sin esperar en tiempo real.
final timeEngineProvider = Provider<TimeEngine>((ref) {
  return TimeEngine(
    startUtc: DateTime.now().toUtc(),
    timeScale: kReleaseMode ? 1.0 : debugTimeScale,
  );
});
