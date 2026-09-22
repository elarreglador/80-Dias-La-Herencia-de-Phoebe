import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'domain/entities/fogg_route.dart';
import 'presentation/providers/sun_terminator_provider.dart';
import 'presentation/widgets/world_map_widget.dart';

/// Solsticio forzado para verificación visual (zoom 2, mapa a pantalla completa).
/// Cambiar a `null` para volver a tiempo real.
DateTime? _forcedSolsticeUtc = DateTime.utc(2026, 6, 21, 12, 0, 0);

void main() {
  final overrides = <Override>[];
  if (_forcedSolsticeUtc != null) {
    overrides.add(
      currentUtcProvider.overrideWith((ref) => Stream.value(_forcedSolsticeUtc!)),
    );
  }
  runApp(ProviderScope(overrides: overrides, child: const MyApp()));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '80 Días — La Herencia de Phoebe',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFC0392B)),
        useMaterial3: true,
      ),
      home: const FoggHomePage(),
    );
  }
}

class FoggHomePage extends StatelessWidget {
  const FoggHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      // Sin AppBar — mapa a pantalla completa, máximo terreno visible
      body: WorldMapWidget(
        route: mockFoggRoute,
        initialZoom: 2.0,
      ),
    );
  }
}
