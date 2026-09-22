import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/bottom_nav_provider.dart';
import '../widgets/fogg_app_bar.dart';
import '../widgets/fogg_bottom_nav.dart';
import 'map_tab.dart';
import 'placeholder_pages.dart';

/// Scaffold raíz — AppBar + IndexedStack + NavigationBar.
///
/// `ConsumerWidget` que lee `bottomNavIndexProvider` vía Riverpod.
/// `IndexedStack` preserva estado de WorldMapWidget (zoom, controller, terminador).
class MainScaffold extends ConsumerWidget {
  const MainScaffold({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedIndex = ref.watch(bottomNavIndexProvider);

    // Clamp en release para evitar crash si índice fuera de rango
    final safeIndex = selectedIndex.clamp(0, bottomNavDestinations.length - 1);

    return Scaffold(
      appBar: const FoggAppBar(),
      body: IndexedStack(
        index: safeIndex,
        children: const [
          MapTab(),
          DiaryPlaceholder(),
          BudgetPlaceholder(),
          RoutePlaceholder(),
        ],
      ),
      bottomNavigationBar: const FoggBottomNav(),
    );
  }
}
