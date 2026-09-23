import 'package:flutter/material.dart';

import '../../domain/entities/transport_mode.dart';
import '../../utils/app_colors.dart';

/// Icono grande de transporte — usado en cuenta atrás y chips.
/// Estética minimalista: círculo con fondo foggRed 12% + icono.
class TransportIcon extends StatelessWidget {
  const TransportIcon({
    super.key,
    required this.mode,
    this.size = 64,
    this.showLabel = true,
  });

  final TransportMode mode;
  final double size;
  final bool showLabel;

  @override
  Widget build(BuildContext context) {
    final iconSize = size * 0.5;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: AppColors.foggRed.withValues(alpha: 0.10),
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.foggRed.withValues(alpha: 0.18), width: 1.5),
          ),
          child: Icon(mode.icon, size: iconSize, color: AppColors.foggRed),
        ),
        if (showLabel) ...[
          const SizedBox(height: 8),
          Text(
            mode.label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.labelColor.withValues(alpha: 0.75),
              letterSpacing: 0.3,
            ),
          ),
        ],
      ],
    );
  }
}

/// Variante compacta para chips (24dp círculo).
class CompactTransportIcon extends StatelessWidget {
  const CompactTransportIcon({super.key, required this.mode, this.selected = false});

  final TransportMode mode;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: selected ? AppColors.foggRed : AppColors.foggRed.withValues(alpha: 0.10),
        shape: BoxShape.circle,
      ),
      child: Icon(
        mode.icon,
        size: 20,
        color: selected ? Colors.white : AppColors.foggRed,
      ),
    );
  }
}
