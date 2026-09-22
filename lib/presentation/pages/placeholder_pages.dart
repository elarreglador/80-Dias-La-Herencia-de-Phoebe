import 'package:flutter/material.dart';

import '../../utils/app_colors.dart';

/// Placeholder Diario — sin lógica, solo Icon + Text.
class DiaryPlaceholder extends StatelessWidget {
  const DiaryPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Pestaña Diario',
      child: Center(
        key: const ValueKey('placeholder-diary'),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.menu_book_outlined,
              size: 48,
              color: AppColors.foggRed.withValues(alpha: 0.6),
            ),
            const SizedBox(height: 12),
            const Text(
              'Próximamente — Diario de Phoebe',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppColors.labelColor,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Las cartas de Phoebe aparecerán aquí al amanecer.',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w400,
                color: AppColors.labelColor.withValues(alpha: 0.7),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

/// Placeholder Presupuesto — sin lógica.
class BudgetPlaceholder extends StatelessWidget {
  const BudgetPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Pestaña Presupuesto',
      child: Center(
        key: const ValueKey('placeholder-budget'),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.account_balance_wallet_outlined,
              size: 48,
              color: AppColors.foggRed.withValues(alpha: 0.6),
            ),
            const SizedBox(height: 12),
            const Text(
              'Próximamente — Presupuesto',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppColors.labelColor,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'El Ledger de 1.000.000 € y su gráfica estarán aquí.',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w400,
                color: AppColors.labelColor.withValues(alpha: 0.7),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

/// Placeholder Ruta — sin lógica.
class RoutePlaceholder extends StatelessWidget {
  const RoutePlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Pestaña Ruta',
      child: Center(
        key: const ValueKey('placeholder-route'),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.route_outlined,
              size: 48,
              color: AppColors.foggRed.withValues(alpha: 0.6),
            ),
            const SizedBox(height: 12),
            const Text(
              'Próximamente — Ruta',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppColors.labelColor,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'La lista de ciudades Fogg hacia el este se mostrará aquí.',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w400,
                color: AppColors.labelColor.withValues(alpha: 0.7),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
