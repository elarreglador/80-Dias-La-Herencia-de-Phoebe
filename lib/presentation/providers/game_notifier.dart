import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/destination_option.dart';
import '../../domain/entities/fogg_city.dart';
import '../../domain/entities/fogg_status.dart';
import '../../services/budget_service.dart';
import '../../services/game_session.dart';
import 'route_catalog_provider.dart';
import 'time_engine_provider.dart';

export 'time_engine_provider.dart';

final budgetServiceProvider = Provider<BudgetService>((ref) {
  return BudgetService();
});

final gameSessionProvider = Provider<GameSession>((ref) {
  return GameSession(
    timeEngine: ref.watch(timeEngineProvider),
    budget: ref.watch(budgetServiceProvider),
    transportSelector: ref.watch(transportSelectorProvider),
  );
});

class GameNotifier extends Notifier<FoggStatus> {
  @override
  FoggStatus build() {
    final session = ref.watch(gameSessionProvider);
    final statusSub = session.statusStream.listen((s) => state = s);
    // El reloj de la partida: cada tick mueve a Phoebe y puede cerrar el
    // tramo (llegada sola a FoggArrived, sin intervención manual).
    final clockSub = session.timeEngine.clock().listen((_) {
      session.tick();
      state = session.status;
    });
    ref.onDispose(() {
      statusSub.cancel();
      clockSub.cancel();
    });
    return session.status;
  }

  GameSession get _session => ref.read(gameSessionProvider);

  void startLeg({
    required FoggCity from,
    required FoggCity to,
    required VehicleOption vehicle,
  }) {
    _session.startLeg(from: from, to: to, vehicle: vehicle);
    state = _session.status;
  }

  void tick() {
    _session.tick();
    state = _session.status;
  }

  void sleep() {
    _session.sleep();
    state = _session.status;
  }

  void restAtHotel() {
    _session.beginRestAtHotel();
    state = _session.status;
  }

  void simulateArrival() {
    _session.simulateArrival();
    state = _session.status;
  }
}

final gameNotifierProvider =
    NotifierProvider<GameNotifier, FoggStatus>(GameNotifier.new);
