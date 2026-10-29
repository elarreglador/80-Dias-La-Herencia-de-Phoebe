import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/fatigue.dart';
import '../../utils/app_colors.dart';
import '../providers/game_notifier.dart';
import '../providers/sun_terminator_provider.dart';

/// Barra superior Fogg — AppBar M3 fija 64dp con título, fecha local y fatiga de Phoebe.
///
/// La fecha sigue el reloj de juego (`currentUtcProvider`), acelerado en debug.
class FoggAppBar extends ConsumerWidget implements PreferredSizeWidget {
  const FoggAppBar({super.key});

  static const _height = 64.0;

  /// Formato manual sin `intl` — evita nueva dependencia.
  /// `21 sep 2026` estilo minimalista.
  static String _formatLocalDate(DateTime now) {
    const months = [
      'ene', 'feb', 'mar', 'abr', 'may', 'jun',
      'jul', 'ago', 'sep', 'oct', 'nov', 'dic',
    ];
    final m = months[now.month - 1];
    return '${now.day} $m ${now.year}';
  }

  static ({String label, Color color}) _fatigueInfo(double value) {
    if (value > 75.0) {
      return (label: 'Descansada', color: Colors.green);
    } else if (value > 50.0) {
      return (label: 'Fatiga ligera', color: Colors.blue);
    } else if (value > 20.0) {
      return (label: 'Cansada', color: Colors.amber);
    } else if (value > 1.0) {
      return (label: 'Extenuada', color: Colors.orange);
    } else {
      return (label: 'Agotada', color: Colors.red);
    }
  }

  @override
  Size get preferredSize => const Size.fromHeight(_height);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Fatigue fatigue = const Fatigue();
    try {
      fatigue = ref.watch(gameNotifierProvider.select((status) => status.fatigue));
    } catch (_) {}
    final fatigueInfo = _fatigueInfo(fatigue.value);

    final now =
        (ref.watch(currentUtcProvider).value ?? DateTime.now().toUtc())
            .toLocal();
    final subtitle = _formatLocalDate(now);

    return AppBar(
      backgroundColor: AppColors.surface,
      foregroundColor: AppColors.labelColor,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: true,
      toolbarHeight: _height,
      title: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            '80 Días — La Herencia de Phoebe',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppColors.labelColor,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 1),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w400,
              color: AppColors.labelColor.withValues(alpha: 0.7),
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 1),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                fatigueInfo.label,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                  color: fatigueInfo.color,
                ),
              ),
              const SizedBox(width: 6),
              SizedBox(
                width: 60,
                height: 2,
                child: Stack(
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        color: fatigueInfo.color.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(1),
                      ),
                    ),
                    FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: (fatigue.value / 100.0).clamp(0.0, 1.0),
                      child: Container(
                        decoration: BoxDecoration(
                          color: fatigueInfo.color,
                          borderRadius: BorderRadius.circular(1),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
