import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/destination_option.dart';
import '../../domain/entities/transport_mode.dart';
import '../../domain/models/fatigue.dart';
import '../../domain/models/price_breakdown.dart';
import '../../utils/app_colors.dart';
import '../../utils/weather_formatter.dart';
import '../providers/route_catalog_provider.dart';
import '../providers/time_engine_provider.dart';
import 'transport_icon.dart';

/// Tarjeta de ciudad candidata.
///
/// Colapsada muestra el nombre de la ciudad y, alineados a la derecha y a su
/// altura, solo los iconos de los vehículos disponibles. Al expandirse
/// ([selected]) despliega cada vehículo con precio, duración, chip sleeper y un
/// botón «Iniciar trayecto» que solo se habilita cuando ese vehículo está
/// seleccionado ([selectedVehicle]). La transición colapsada ↔ expandida se
/// anima con [AnimatedSize] para que la tarjeta crezca y encoja con fluidez.
///
/// `onVehicleTap` selecciona un vehículo; `onStartTrip` inicia la ruta con el
/// vehículo ya seleccionado. `onPinTap` navega al mapa sin elegir destino.
class DestinationCard extends ConsumerWidget {
  const DestinationCard({
    super.key,
    required this.option,
    required this.selected,
    required this.onTap,
    required this.onVehicleTap,
    required this.selectedVehicle,
    required this.onStartTrip,
    this.onPinTap,
    this.onRestAtHotel,
    this.hotelPrice,
    this.fatigue = const Fatigue(),
    this.isRestingAtHotel = false,
  });

  final DestinationOption option;
  final bool selected;
  final VoidCallback onTap;
  final ValueChanged<VehicleOption> onVehicleTap;
  final VehicleOption? selectedVehicle;
  final ValueChanged<VehicleOption> onStartTrip;
  final VoidCallback? onPinTap;

  /// Acción «Ir al Hotel a descansar» — inicia el descanso en hotel.
  final VoidCallback? onRestAtHotel;

  /// Importe de la noche de hotel (€) a mostrar.
  final int? hotelPrice;

  /// Fatiga actual de Phoebe — para el mensaje de estado del descanso.
  final Fatigue fatigue;

  /// Si el descanso en hotel está en curso.
  final bool isRestingAtHotel;

  static const _expandDuration = Duration(milliseconds: 250);

  DateTime _getArrivalTime(DateTime baseNow) {
    if (option.vehicles.isEmpty) return baseNow;
    final v = option.vehicles.first;
    final dep = v.departureHour != null && v.departureMinute != null
        ? (v.departureHour!, v.departureMinute!)
        : (8, 0);
    var departureUtc = DateTime.utc(baseNow.year, baseNow.month, baseNow.day, dep.$1, dep.$2);
    if (departureUtc.isBefore(baseNow)) {
      departureUtc = departureUtc.add(const Duration(days: 1));
    }
    return departureUtc.add(v.duration);
  }

  /// Título del vehículo en la fila expandida.
  ///
  /// Para el coche añade el desglose del precio (SPEC 019 addenda §11):
  /// «Coche (alquiler 31€ + combustible 80€)» o, cuando Phoebe conserva el
  /// coche del tramo anterior y no paga alquiler, «Coche (combustible 80€)».
  /// El combustible se muestra como resto del total para que las dos partes
  /// sumen exactamente el precio que aparece en la línea de abajo.
  /// El resto de modos mantiene su etiqueta simple.
  static String _vehicleLabel(VehicleOption vehicle) {
    final breakdown = vehicle.priceBreakdown;
    if (vehicle.mode != TransportMode.car || breakdown is! CarPriceBreakdown) {
      return vehicle.mode.label;
    }
    final rentalPart = breakdown.rentalWaived ? 0 : breakdown.rental.round();
    if (rentalPart == 0) {
      return '${vehicle.mode.label} (combustible ${vehicle.price}€)';
    }
    final fuelPart = vehicle.price - rentalPart;
    return '${vehicle.mode.label} (alquiler $rentalPart€ + combustible $fuelPart€)';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentTime = ref.watch(timeEngineProvider).now();
    final arrivalTime = _getArrivalTime(currentTime);
    final weatherService = ref.watch(weatherServiceProvider);
    final weatherAsync = ref.watch(weatherSnapshotProvider((option.city.lat, option.city.lng, arrivalTime)));
    final snapshot = weatherAsync.valueOrNull ?? weatherService.fetchSync(option.city.lat, option.city.lng, arrivalTime);
    final weatherSummary = formatWeatherSummary(snapshot);

    return Material(
      color: selected ? AppColors.foggRed.withValues(alpha: 0.08) : AppColors.surface,
      borderRadius: BorderRadius.circular(16),
      elevation: selected ? 2 : 0,
      child: InkWell(
        onTap: () {
          HapticFeedback.lightImpact();
          onTap();
        },
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? AppColors.foggRed : AppColors.foggRed.withValues(alpha: 0.12),
              width: selected ? 1.8 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _header(weatherSummary),
              AnimatedSize(
                duration: _expandDuration,
                curve: Curves.easeInOut,
                alignment: Alignment.topCenter,
                child: selected ? _expandedVehicles() : const SizedBox.shrink(),
              ),
              if (selected) _hotelRestSection(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(String? weatherSummary) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (onPinTap != null)
          Tooltip(
            message: 'Ver ${option.city.name} en el mapa',
            child: Material(
              color: Colors.transparent,
              shape: const CircleBorder(),
              child: InkWell(
                onTap: () {
                  HapticFeedback.lightImpact();
                  onPinTap!.call();
                },
                customBorder: const CircleBorder(),
                child: _pinCircle(),
              ),
            ),
          )
        else
          _pinCircle(),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                option.city.name,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.labelColor,
                ),
              ),
              if (weatherSummary != null)
                Text(
                  weatherSummary,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.labelColor,
                  ),
                ),
            ],
          ),
        ),
        if (selected)
          const Icon(Icons.check_circle, color: AppColors.foggRed, size: 22)
        else
          _collapsedIconsRow(),
      ],
    );
  }

  Widget _pinCircle() {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: selected ? AppColors.foggRed : AppColors.surfaceVariant,
        shape: BoxShape.circle,
      ),
      child: Icon(
        Icons.location_on,
        size: 22,
        color: selected ? Colors.white : AppColors.foggRed.withValues(alpha: 0.8),
        semanticLabel: 'Ver ${option.city.name} en el mapa',
      ),
    );
  }

  /// Estado colapsado: iconos de los vehículos alineados a la derecha, a la
  /// altura del nombre de la ciudad.
  Widget _collapsedIconsRow() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final vehicle in option.vehicles)
          Padding(
            padding: const EdgeInsets.only(left: 6),
            child: _collapsedIcon(vehicle),
          ),
      ],
    );
  }

  Widget _collapsedIcon(VehicleOption vehicle) {
    final cancelled = vehicle.weatherImpact?.cancelled ?? false;
    return Container(
      key: ValueKey('vehicle-icon-${option.city.name}-${vehicle.mode.name}'),
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.foggRed.withValues(alpha: 0.10)),
      ),
      child: Icon(
        vehicle.mode.icon,
        size: 20,
        color: cancelled
            ? AppColors.labelColor.withValues(alpha: 0.35)
            : AppColors.foggRed,
      ),
    );
  }

  /// Estado expandido: una fila por vehículo bajo la cabecera.
  Widget _expandedVehicles() {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: option.vehicles.map(_vehicleRow).toList(),
      ),
    );
  }

  /// Tarjeta de descanso en hotel — visible en el estado expandido.
  /// Icono de hotel, label «Ir al Hotel a descansar», importe y mensaje de
  /// estado; sin iconos de vehículo (es una acción de descanso, no una opción).
  Widget _hotelRestSection() {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Material(
        color: AppColors.foggRed.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          key: const ValueKey('hotel-rest-card'),
          onTap: onRestAtHotel == null
              ? null
              : () {
                  HapticFeedback.lightImpact();
                  onRestAtHotel!();
                },
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    const Icon(Icons.hotel, size: 22, color: AppColors.foggRed),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'Ir al Hotel a descansar',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppColors.labelColor,
                        ),
                      ),
                    ),
                    if (hotelPrice != null)
                      Text(
                        '$hotelPrice€',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: AppColors.foggRed,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  _restStatusMessage,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.labelColor.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String get _restStatusMessage {
    if (isRestingAtHotel) return 'Descansando en el hotel...';
    if (fatigue.mustSleep) return 'Phoebe está agotada: debe descansar antes de continuar';
    return 'Descanso en hotel: recuperación ${Fatigue.hotelRecoverRate}%/h';
  }

  Widget _vehicleRow(VehicleOption vehicle) {
    final cancelled = vehicle.weatherImpact?.cancelled ?? false;
    final reason = vehicle.weatherImpact?.reason;
    final isSelected = selectedVehicle == vehicle;

    return Opacity(
      opacity: cancelled ? 0.55 : 1,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Material(
          color: isSelected ? AppColors.foggRed.withValues(alpha: 0.08) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            key: ValueKey('vehicle-row-${option.city.name}-${vehicle.mode.name}'),
            onTap: cancelled
                ? () {}
                : () {
                    HapticFeedback.lightImpact();
                    onVehicleTap(vehicle);
                  },
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  CompactTransportIcon(mode: vehicle.mode, selected: isSelected),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _vehicleLabel(vehicle),
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: AppColors.labelColor,
                          ),
                        ),
                        Row(
                          children: [
                            Text(
                              '${vehicle.price}€',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.labelColor.withValues(alpha: 0.7),
                              ),
                            ),
                            Text(
                              ' · ${vehicle.durationLabel}',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.labelColor.withValues(alpha: 0.55),
                              ),
                            ),
                            if (vehicle.sleeper) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppColors.foggRed.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Text(
                                  'sleeper',
                                  style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.foggRed,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        if (cancelled && reason != null)
                          Text(
                            reason,
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: AppColors.foggRed,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    key: ValueKey('start-trip-${option.city.name}-${vehicle.mode.name}'),
                    onPressed: (cancelled || !isSelected)
                        ? null
                        : () {
                            HapticFeedback.lightImpact();
                            onStartTrip(vehicle);
                          },
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.foggRed,
                      disabledBackgroundColor: AppColors.foggRed.withValues(alpha: 0.30),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      minimumSize: const Size(0, 36),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: const Text(
                      'Iniciar trayecto',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
