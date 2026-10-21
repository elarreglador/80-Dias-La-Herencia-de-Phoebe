import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/destination_option.dart';
import 'game_notifier.dart';

/// Alias temporal hacia [gameNotifierProvider] (compatibilidad SPEC 012).
/// @deprecated Usar [gameNotifierProvider].
@Deprecated('Usar gameNotifierProvider')
final foggStatusProvider = gameNotifierProvider;

/// Selección en estado llegado — ciudad y vehículo elegidos (null = sin elegir).
final selectedDestinationProvider = StateProvider<DestinationOption?>((ref) => null);
final selectedVehicleProvider = StateProvider<VehicleOption?>((ref) => null);
