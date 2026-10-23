import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../domain/entities/destination_option.dart';
import '../../utils/app_colors.dart';
import 'transport_icon.dart';

/// Tarjeta de ciudad candidata — colapsada muestra solo iconos de vehículos.
///
/// Al expandirse ([selected]) despliega cada vehículo con precio, duración,
/// chip sleeper y un botón «Iniciar trayecto» que solo se habilita cuando ese
/// vehículo está seleccionado ([selectedVehicle]).
///
/// `onVehicleTap` selecciona un vehículo; `onStartTrip` inicia la ruta con el
/// vehículo ya seleccionado. `onPinTap` navega al mapa sin elegir destino.
class DestinationCard extends StatelessWidget {
  const DestinationCard({
    super.key,
    required this.option,
    required this.selected,
    required this.onTap,
    required this.onVehicleTap,
    required this.selectedVehicle,
    required this.onStartTrip,
    this.onPinTap,
  });

  final DestinationOption option;
  final bool selected;
  final VoidCallback onTap;
  final ValueChanged<VehicleOption> onVehicleTap;
  final VehicleOption? selectedVehicle;
  final ValueChanged<VehicleOption> onStartTrip;
  final VoidCallback? onPinTap;

  @override
  Widget build(BuildContext context) {
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
              _header(),
              const SizedBox(height: 12),
              if (selected)
                ...option.vehicles.map(_vehicleRow)
              else
                _collapsedVehicles(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header() {
    return Row(
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
          child: Text(
            option.city.name,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppColors.labelColor,
            ),
          ),
        ),
        if (selected) const Icon(Icons.check_circle, color: AppColors.foggRed, size: 22),
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

  /// Estado colapsado: solo los iconos de los vehículos disponibles.
  Widget _collapsedVehicles() {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: option.vehicles.map((v) {
        final cancelled = v.weatherImpact?.cancelled ?? false;
        return Container(
          key: ValueKey('vehicle-icon-${option.city.name}-${v.mode.name}'),
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: AppColors.surfaceVariant,
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.foggRed.withValues(alpha: 0.10)),
          ),
          child: Icon(
            v.mode.icon,
            size: 20,
            color: cancelled
                ? AppColors.labelColor.withValues(alpha: 0.35)
                : AppColors.foggRed,
          ),
        );
      }).toList(),
    );
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
                          vehicle.mode.label,
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
