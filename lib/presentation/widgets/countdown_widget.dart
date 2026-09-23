import 'package:flutter/material.dart';

import '../../utils/app_colors.dart';

/// Widget puro de cuenta atrás — recibe Duration ya computada.
/// Formato "Xd HH:MM:SS" monoespaciado, sin lógica temporal interna.
class CountdownWidget extends StatelessWidget {
  const CountdownWidget({
    super.key,
    required this.remaining,
    this.compact = false,
  });

  final Duration remaining;
  final bool compact;

  static String format(Duration d) {
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

  @override
  Widget build(BuildContext context) {
    final text = format(remaining);
    // Separa días si existen para resaltar
    final hasDays = remaining.inDays > 0;
    final daysStr = hasDays ? '${remaining.inDays}d ' : '';
    final hmsStr = text.substring(hasDays ? daysStr.length : 0);

    return Semantics(
      label: 'Cuenta atrás $text hasta destino',
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: compact ? 14 : 20, vertical: compact ? 10 : 14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.foggRed.withValues(alpha: 0.12), width: 1),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.schedule, size: compact ? 18 : 20, color: AppColors.foggRed.withValues(alpha: 0.85)),
            const SizedBox(width: 10),
            if (hasDays)
              Text(
                daysStr,
                style: TextStyle(
                  fontSize: compact ? 18 : 22,
                  fontWeight: FontWeight.w800,
                  color: AppColors.foggRed,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            Text(
              hmsStr,
              style: TextStyle(
                fontSize: compact ? 18 : 24,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
                color: AppColors.labelColor,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
