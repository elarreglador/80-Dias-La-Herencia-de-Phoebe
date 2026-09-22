import 'package:flutter/material.dart';

import '../../utils/app_colors.dart';

/// Barra superior Fogg — AppBar M3 fija 64dp con título y fecha local.
///
/// Sin acciones en MVP (trailing reservado para BudgetBadge futuro).
class FoggAppBar extends StatelessWidget implements PreferredSizeWidget {
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

  @override
  Size get preferredSize => const Size.fromHeight(_height);

  @override
  Widget build(BuildContext context) {
    final subtitle = _formatLocalDate(DateTime.now());

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
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.labelColor,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w400,
              color: AppColors.labelColor.withValues(alpha: 0.7),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
