import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/fogg_status.dart';
import 'bottom_nav_provider.dart';
import 'game_notifier.dart';

/// Stream de cuenta atrás — emite Duration restante cada segundo cuando está viajando.
/// Solo hace tick cuando la pestaña Fogg (índice 2) está visible; en otro caso
/// emite una única vez para evitar Timers pendientes en tests con pumpAndSettle.
/// Formato objetivo: Xd HH:MM:SS (ver formatCountdown).
final countdownProvider = StreamProvider.autoDispose<Duration>((ref) async* {
  final status = ref.watch(gameNotifierProvider);
  if (status is! FoggTraveling) {
    yield Duration.zero;
    return;
  }
  final engine = ref.watch(timeEngineProvider);
  // Emite inmediatamente.
  Duration compute() => status.remainingAt(engine.now());
  yield compute();

  // Solo tick si Fogg está visible — evita pending Timer cuando IndexedStack está en Mapa.
  final navIndex = ref.watch(bottomNavIndexProvider);
  if (navIndex != 2) return;

  await for (final _ in Stream.periodic(const Duration(seconds: 1))) {
    // Re-lee status por si cambió a Arrived externamente o se cambió de pestaña.
    final current = ref.read(gameNotifierProvider);
    if (current is! FoggTraveling) {
      yield Duration.zero;
      break;
    }
    if (ref.read(bottomNavIndexProvider) != 2) break;
    final remaining = current.remainingAt(engine.now());
    yield remaining;
    if (remaining == Duration.zero) break;
  }
});

/// Formatea Duration a "Xd HH:MM:SS" o "HH:MM:SS" si <1 día.
/// Siempre 2 dígitos para HH/MM/SS. Ej: 1d 05:23:11, 05:23:11, 00:00:07.
String formatCountdown(Duration d) {
  if (d.isNegative) d = Duration.zero;
  final days = d.inDays;
  final hours = d.inHours % 24;
  final minutes = d.inMinutes % 60;
  final seconds = d.inSeconds % 60;
  final hms =
      '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  if (days > 0) return '${days}d $hms';
  return hms;
}
