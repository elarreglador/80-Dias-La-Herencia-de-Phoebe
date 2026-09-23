import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../domain/entities/destination_option.dart';
import '../../utils/app_colors.dart';
import 'transport_icon.dart';

/// Tarjeta de ciudad candidata — muestra nombre + 1-3 vehículos.
///
/// `onPinTap` es el icono de chincheta que navega al mapa con zoom medio
/// sobre [option.city]; no selecciona destino (eso lo hace la elección de
/// vehículo en `FoggStatusPage`). Si es `null`, no se muestra el botón.
class DestinationCard extends StatelessWidget {
  const DestinationCard({
    super.key,
    required this.option,
    required this.selected,
    required this.onTap,
    this.onPinTap,
  });

  final DestinationOption option;
  final bool selected;
  final VoidCallback onTap;
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
              Row(
                children: [
                  // Círculo gris — ahora es el botón que navega al mapa (zoom medio).
                  // No selecciona destino; la selección sigue siendo vía tarjeta/vehículo.
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
                          child: Container(
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
                          ),
                        ),
                      ),
                    )
                  else
                    Container(
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
                      ),
                    ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          option.city.name,
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.labelColor),
                        ),
                        Text(
                          '${option.city.lat.toStringAsFixed(2)}, ${option.city.lng.toStringAsFixed(2)}',
                          style: TextStyle(fontSize: 11, color: AppColors.labelColor.withValues(alpha: 0.55)),
                        ),
                      ],
                    ),
                  ),
                  if (selected) const Icon(Icons.check_circle, color: AppColors.foggRed, size: 22),
                ],
              ),
              const SizedBox(height: 12),
              // Resumen vehículos — iconos + precio
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: option.vehicles.map((v) {
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceVariant,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppColors.foggRed.withValues(alpha: 0.10)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(v.mode.icon, size: 14, color: AppColors.foggRed),
                        const SizedBox(width: 4),
                        Text(v.mode.label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                        const SizedBox(width: 6),
                        Text('${v.price}€', style: TextStyle(fontSize: 11, color: AppColors.labelColor.withValues(alpha: 0.6))),
                        if (v.sleeper) ...[
                          const SizedBox(width: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                            decoration: BoxDecoration(color: AppColors.foggRed.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
                            child: const Text('sleeper', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: AppColors.foggRed)),
                          ),
                        ],
                      ],
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Chip de vehículo individual — usado tras elegir ciudad.
class VehicleChoiceChip extends StatelessWidget {
  const VehicleChoiceChip({
    super.key,
    required this.vehicle,
    required this.selected,
    required this.onTap,
  });

  final VehicleOption vehicle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.foggRed : AppColors.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: () {
          HapticFeedback.lightImpact();
          onTap();
        },
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: selected ? AppColors.foggRed : AppColors.foggRed.withValues(alpha: 0.14), width: 1.2),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              CompactTransportIcon(mode: vehicle.mode, selected: selected),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    vehicle.mode.label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: selected ? Colors.white : AppColors.labelColor,
                    ),
                  ),
                  Text(
                    '${vehicle.durationLabel} · ${vehicle.price}€${vehicle.sleeper ? ' · sleeper' : ''}',
                    style: TextStyle(
                      fontSize: 11,
                      color: selected ? Colors.white.withValues(alpha: 0.9) : AppColors.labelColor.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ),
              if (selected) ...[
                const SizedBox(width: 10),
                const Icon(Icons.check_circle, color: Colors.white, size: 18),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
