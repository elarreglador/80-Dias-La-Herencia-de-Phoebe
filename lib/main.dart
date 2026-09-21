import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'domain/entities/fogg_route.dart';
import 'presentation/widgets/world_map_widget.dart';

void main() {
  runApp(const ProviderScope(child: MyApp()));
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Phoebe Fogg — Mapamundi'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: const Padding(
        padding: EdgeInsets.all(16),
        child: WorldMapWidget(
          route: mockFoggRoute,
          height: 500,
        ),
      ),
    );
  }
}
