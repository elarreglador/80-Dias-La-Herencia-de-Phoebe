import 'package:flutter/material.dart';

import '../../domain/entities/fogg_route.dart';
import '../widgets/world_map_widget.dart';

/// Pestaña Mapa — wrapper que embebe WorldMapWidget existente.
///
/// `IndexedStack` externo preserva el estado del MapController al cambiar pestaña.
/// El `Scaffold` raíz ya excluye `NavigationBar` (80dp) del `body`; por tanto
/// `WorldMapWidget` con `Positioned(right:16,bottom:16)+SafeArea` queda visible
/// sin padding adicional. `SafeArea(top:false,bottom:true)` interno + externo
/// maneja ◻ ○ △ y notch.
class MapTab extends StatelessWidget {
  const MapTab({super.key});

  @override
  Widget build(BuildContext context) {
    return const WorldMapWidget(
      route: mockFoggRoute,
      initialZoom: 2.0,
    );
  }
}
