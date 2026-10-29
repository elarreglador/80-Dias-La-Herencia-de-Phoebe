import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/destination_option.dart';
import '../../domain/entities/fogg_city.dart';
import '../../domain/entities/fogg_leg.dart';
import '../../domain/entities/fogg_status.dart';
import '../../domain/models/fatigue.dart';
import '../../services/geo_pricing.dart';
import '../../services/hotel_pricing.dart';
import '../../utils/app_colors.dart';
import '../providers/bottom_nav_provider.dart';
import '../providers/countdown_provider.dart';
import '../providers/fogg_status_provider.dart';
import '../providers/game_notifier.dart';
import '../providers/map_focus_provider.dart';
import '../widgets/city_info_card.dart';
import '../widgets/countdown_widget.dart';
import '../widgets/destination_card.dart';
import '../widgets/hotel_rest_card.dart';
import '../widgets/transport_icon.dart';

/// Pantalla «Qué hace la Srta. Fogg ahora» — dos estados según FoggStatus.
///
/// * Viajando → cuenta atrás + icono transporte + progreso.
/// * En destino → 3 ciudades candidatas (este) + 1-3 vehículos por ciudad.
class FoggStatusPage extends ConsumerWidget {
  const FoggStatusPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(gameNotifierProvider);

    return switch (status) {
      FoggTraveling(:final leg) => _TravelingView(leg: leg),
      FoggArrived(:final currentCity, :final options, :final fatigue) => _ArrivedView(
          currentCity: currentCity,
          options: options,
          fatigue: fatigue,
        ),
    };
  }
}

// ---------------------------------------------------------------------------
// Viajando
// ---------------------------------------------------------------------------

class _TravelingView extends ConsumerWidget {
  const _TravelingView({required this.leg});

  final FoggLeg leg;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final countdownAsync = ref.watch(countdownProvider);
    final now = ref.watch(timeEngineProvider).now();

    final remaining = countdownAsync.valueOrNull ?? leg.remainingAt(now);
    final progress = leg.progressAt(now).clamp(0.0, 1.0);
    final totalLabel = _formatTotal(leg.totalDuration);

    return SingleChildScrollView(
      key: const ValueKey('fogg-status-traveling'),
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Header
          Text(
            'Phoebe está viajando',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.labelColor.withValues(alpha: 0.6), letterSpacing: 0.6),
          ),
          const SizedBox(height: 6),
          Text(
            '${leg.from.name} → ${leg.to.name}',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.labelColor),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            'vía ${leg.transport.label} · ${leg.price}€${leg.sleeper ? ' · sleeper' : ''} · $totalLabel',
            style: TextStyle(fontSize: 12, color: AppColors.labelColor.withValues(alpha: 0.6)),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 28),

          // Icono transporte grande
          TransportIcon(mode: leg.transport, size: 88),
          const SizedBox(height: 24),

          // Cuenta atrás
          countdownAsync.when(
            data: (d) => CountdownWidget(remaining: d),
            loading: () => CountdownWidget(remaining: remaining),
            error: (_, __) => CountdownWidget(remaining: remaining),
          ),
          const SizedBox(height: 8),
          Text(
            'hasta ${leg.to.name}',
            style: TextStyle(fontSize: 12, color: AppColors.labelColor.withValues(alpha: 0.55)),
          ),
          const SizedBox(height: 24),

          // Progreso
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 8,
              backgroundColor: AppColors.foggRed.withValues(alpha: 0.12),
              valueColor: const AlwaysStoppedAnimation(AppColors.foggRed),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(leg.from.name, style: TextStyle(fontSize: 11, color: AppColors.labelColor.withValues(alpha: 0.55))),
              Text('${(progress * 100).toStringAsFixed(0)}%', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.foggRed)),
              Text(leg.to.name, style: TextStyle(fontSize: 11, color: AppColors.labelColor.withValues(alpha: 0.55))),
            ],
          ),
          const SizedBox(height: 28),
        ],
      ),
    );
  }

  String _formatTotal(Duration d) {
    final days = d.inDays;
    final h = d.inHours % 24;
    if (days > 0) return '${days}d ${h}h';
    return '${d.inHours}h ${d.inMinutes % 60}min';
  }
}

// ---------------------------------------------------------------------------
// En destino
// ---------------------------------------------------------------------------

class _ArrivedView extends ConsumerWidget {
  const _ArrivedView({required this.currentCity, required this.options, required this.fatigue});

  final FoggCity currentCity;
  final List<DestinationOption> options;
  final Fatigue fatigue;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedDestination = ref.watch(selectedDestinationProvider);
    final selectedVehicle = ref.watch(selectedVehicleProvider);

    final hotelPrice = HotelPricing.priceFor(
      GeoPricing.zoneForTimezone(currentCity.timezone),
      countryMultiplier: GeoPricing.countryMultiplierForTimezone(currentCity.timezone),
    );

    void startTrip(DestinationOption option, VehicleOption vehicle) {
      // Transición real a viajando — el origen es la ciudad actual del estado.
      ref.read(gameNotifierProvider.notifier).startLeg(
            from: currentCity,
            to: option.city,
            vehicle: vehicle,
          );
      ref.read(selectedDestinationProvider.notifier).state = null;
      ref.read(selectedVehicleProvider.notifier).state = null;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('¡En ruta a ${option.city.name} en ${vehicle.mode.label}!')),
      );
    }

    return SingleChildScrollView(
      key: const ValueKey('fogg-status-arrived'),
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CityInfoCard(city: currentCity),
          const SizedBox(height: 18),
          Text(
            'Destinos disponibles',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppColors.labelColor.withValues(alpha: 0.7),
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'Elige el próximo destino hacia el este',
            style: TextStyle(fontSize: 12, color: AppColors.labelColor.withValues(alpha: 0.6)),
          ),
          const SizedBox(height: 10),

          // Tarjeta independiente de descanso en hotel — primera opción de la
          // lista, antes de los destinos candidatos.
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: HotelRestCard(
              onRestAtHotel: () => ref.read(gameNotifierProvider.notifier).restAtHotel(),
              hotelPrice: hotelPrice,
              fatigue: fatigue,
              isRestingAtHotel: ref.read(gameSessionProvider).restingAtHotel,
            ),
          ),

          // Todas las opciones — la chincheta solo navega al mapa; la
          // selección de destino expande su tarjeta.
          ...options.map((opt) {
            final isSelected = selectedDestination?.city == opt.city;
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: DestinationCard(
                option: opt,
                selected: isSelected,
                selectedVehicle: isSelected ? selectedVehicle : null,
                onTap: () {
                  ref.read(selectedDestinationProvider.notifier).state = opt;
                  // Resetea vehículo si no pertenece a la nueva ciudad.
                  final currentVehicle = ref.read(selectedVehicleProvider);
                  if (currentVehicle != null && !opt.vehicles.contains(currentVehicle)) {
                    ref.read(selectedVehicleProvider.notifier).state = null;
                  }
                },
                onVehicleTap: (vehicle) {
                  ref.read(selectedVehicleProvider.notifier).state = vehicle;
                },
                onStartTrip: (vehicle) => startTrip(opt, vehicle),
                onPinTap: () {
                  // Solo navega al mapa con zoom medio; no selecciona destino/vehículo.
                  ref.read(mapFocusProvider.notifier).request(opt.city);
                  ref.read(bottomNavIndexProvider.notifier).state = 0;
                },
              ),
            );
          }),
        ],
      ),
    );
  }
}
