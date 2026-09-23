import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/destination_option.dart';
import '../../domain/entities/fogg_leg.dart';
import '../../domain/entities/fogg_status.dart';
import '../../utils/app_colors.dart';
import '../providers/bottom_nav_provider.dart';
import '../providers/countdown_provider.dart';
import '../providers/fogg_status_provider.dart';
import '../providers/map_focus_provider.dart';
import '../widgets/countdown_widget.dart';
import '../widgets/destination_card.dart';
import '../widgets/transport_icon.dart';

/// Pantalla «Qué hace la Srta. Fogg ahora» — dos estados según FoggStatus.
///
/// * Viajando → cuenta atrás + icono transporte + progreso.
/// * En destino → 3 ciudades candidatas (este) + 1-3 vehículos por ciudad.
class FoggStatusPage extends ConsumerWidget {
  const FoggStatusPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(foggStatusProvider);

    return switch (status) {
      FoggTraveling(:final leg) => _TravelingView(leg: leg),
      FoggArrived(:final currentCity, :final options) => _ArrivedView(
          currentCityName: currentCity.name,
          options: options,
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

    final remaining = countdownAsync.valueOrNull ?? leg.remainingAt(DateTime.now().toUtc());
    final progress = leg.progressAt(DateTime.now().toUtc()).clamp(0.0, 1.0);
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

          // Debug toggle — solo estética ficticia
          _DebugToggle(),
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
  const _ArrivedView({required this.currentCityName, required this.options});

  final String currentCityName;
  final List<DestinationOption> options;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedCity = ref.watch(selectedDestinationProvider);
    final selectedVehicle = ref.watch(selectedVehicleProvider);

    // Vehículos disponibles según ciudad elegida
    final vehicles = selectedCity?.vehicles ?? const <VehicleOption>[];

    final canConfirm = selectedCity != null && selectedVehicle != null;

    return SingleChildScrollView(
      key: const ValueKey('fogg-status-arrived'),
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header llegada
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.foggRed.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.foggRed.withValues(alpha: 0.12)),
            ),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: const BoxDecoration(color: AppColors.foggRed, shape: BoxShape.circle),
                  child: const Icon(Icons.flag, color: Colors.white, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('¡Phoebe ha llegado a $currentCityName!',
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.labelColor)),
                      const SizedBox(height: 2),
                      Text('Elige el próximo destino hacia el este',
                          style: TextStyle(fontSize: 12, color: AppColors.labelColor.withValues(alpha: 0.6))),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Text('Destinos disponibles',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.labelColor.withValues(alpha: 0.7), letterSpacing: 0.5)),
          const SizedBox(height: 10),

          // 3 ciudades — chincheta solo navega al mapa, selección es vía vehículo
          ...options.map((opt) {
            final isSelected = selectedCity?.city == opt.city;
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: DestinationCard(
                option: opt,
                selected: isSelected,
                onTap: () {
                  ref.read(selectedDestinationProvider.notifier).state = opt;
                  // Resetea vehículo si no pertenece a la nueva ciudad
                  final currentVehicle = ref.read(selectedVehicleProvider);
                  if (currentVehicle != null && !opt.vehicles.contains(currentVehicle)) {
                    ref.read(selectedVehicleProvider.notifier).state = null;
                  }
                },
                onPinTap: () {
                  // Solo navega al mapa con zoom medio; no selecciona destino/vehículo
                  ref.read(mapFocusProvider.notifier).request(opt.city);
                  ref.read(bottomNavIndexProvider.notifier).state = 0;
                },
              ),
            );
          }),

          if (selectedCity != null) ...[
            const SizedBox(height: 14),
            Text('Vehículos hacia ${selectedCity.city.name}',
                style:
                    TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.labelColor.withValues(alpha: 0.7), letterSpacing: 0.5)),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: vehicles.map((v) {
                final isSelected = selectedVehicle == v;
                return VehicleChoiceChip(
                  vehicle: v,
                  selected: isSelected,
                  onTap: () => ref.read(selectedVehicleProvider.notifier).state = v,
                );
              }).toList(),
            ),
          ],

          const SizedBox(height: 20),
          // Botón confirmar
          SizedBox(
            height: 48,
            child: FilledButton.icon(
              onPressed: canConfirm
                  ? () {
                      // ignore: unnecessary_non_null_assertion
                      final city = selectedCity!;
                      // ignore: unnecessary_non_null_assertion
                      final vehicle = selectedVehicle!;
                      // Transición mock a viajando — estética ficticia
                      ref.read(foggStatusProvider.notifier).goTravelingMock(
                            from: options.firstWhere((o) => o.city.name == currentCityName,
                                    orElse: () => options.first)
                                .city,
                            to: city.city,
                            mode: vehicle.mode,
                            duration: vehicle.duration,
                            price: vehicle.price,
                            sleeper: vehicle.sleeper,
                          );
                      ref.read(selectedDestinationProvider.notifier).state = null;
                      ref.read(selectedVehicleProvider.notifier).state = null;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('¡En ruta a ${city.city.name} en ${vehicle.mode.label}!')),
                      );
                    }
                  : null,
              icon: const Icon(Icons.arrow_forward, size: 18),
              label: Text(canConfirm ? 'Confirmar viaje a ${selectedCity.city.name}' : 'Elige destino y vehículo'),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.foggRed,
                disabledBackgroundColor: AppColors.foggRed.withValues(alpha: 0.35),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          const SizedBox(height: 14),
          _DebugToggle(),
        ],
      ),
    );
  }
}

/// Toggle debug para alternar estados sin backend — solo mock estético.
class _DebugToggle extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(foggStatusProvider);
    final isTraveling = status is FoggTraveling;
    return OutlinedButton.icon(
      onPressed: () {
        if (isTraveling) {
          ref.read(foggStatusProvider.notifier).goArrivedMock();
          ref.read(selectedDestinationProvider.notifier).state = null;
          ref.read(selectedVehicleProvider.notifier).state = null;
        } else {
          ref.read(foggStatusProvider.notifier).goDefaultTraveling();
        }
      },
      icon: Icon(isTraveling ? Icons.location_on_outlined : Icons.train_outlined, size: 16),
      label: Text(isTraveling ? 'Simular llegada (debug)' : 'Simular salida (debug)', style: const TextStyle(fontSize: 12)),
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.labelColor.withValues(alpha: 0.7),
        side: BorderSide(color: AppColors.labelColor.withValues(alpha: 0.15)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }
}
