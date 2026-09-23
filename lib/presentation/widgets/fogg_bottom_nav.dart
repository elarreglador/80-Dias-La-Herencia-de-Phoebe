import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/fogg_status.dart';
import '../../utils/app_colors.dart';
import '../providers/bottom_nav_provider.dart';
import '../providers/fogg_status_provider.dart';

/// Botonera inferior Fogg — NavigationBar M3 con 5 destinos.
/// Índice 2 (Fogg) es dinámico: tren si viaja, pin si está en destino.
///
/// Envuelta en SafeArea(bottom:true) para respetar gestos sistema ◻ ○ △.
class FoggBottomNav extends ConsumerWidget {
  const FoggBottomNav({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedIndex = ref.watch(bottomNavIndexProvider);
    final foggStatus = ref.watch(foggStatusProvider);
    final isTraveling = foggStatus is FoggTraveling;

    return SafeArea(
      top: false,
      bottom: true,
      child: NavigationBar(
        selectedIndex: selectedIndex,
        onDestinationSelected: (index) {
          // Validación clamp en release, assert en debug
          assert(
            index >= 0 && index < bottomNavDestinations.length,
            'bottomNavIndex fuera de rango 0..${bottomNavDestinations.length - 1}',
          );
          final clamped = index.clamp(0, bottomNavDestinations.length - 1);
          ref.read(bottomNavIndexProvider.notifier).state = clamped;
          HapticFeedback.lightImpact();
        },
        height: 80,
        elevation: 3,
        backgroundColor: AppColors.surface,
        indicatorColor: AppColors.foggRed.withValues(alpha: 0.12),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        destinations: [
          for (var i = 0; i < bottomNavDestinations.length; i++)
            NavigationDestination(
              icon: Icon(_iconFor(i, isTraveling, filled: false)),
              selectedIcon: Icon(_iconFor(i, isTraveling, filled: true)),
              label: bottomNavDestinations[i].label,
            ),
        ],
      ),
    );
  }

  IconData _iconFor(int index, bool isTraveling, {required bool filled}) {
    // Índice 2 = Fogg central dinámico
    if (index == 2) {
      if (isTraveling) {
        return filled ? Icons.train : Icons.train_outlined;
      } else {
        return filled ? Icons.location_on : Icons.location_on_outlined;
      }
    }
    return filled ? bottomNavDestinations[index].iconFilled : bottomNavDestinations[index].iconOutlined;
  }
}
