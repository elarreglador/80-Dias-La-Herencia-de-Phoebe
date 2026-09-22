import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pf/main.dart';

void main() {
  testWidgets('App carga con ProviderScope y muestra Phoebe Fogg', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: MyApp()));
    await tester.pumpAndSettle();
    // Título retirado para mapa a pantalla completa (lib/main.dart:43)
    // Verificar que la app carga sin AppBar y muestra el mapa
    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.byType(Scaffold), findsOneWidget);
    // WorldMapWidget debe estar presente (título ya no obligatorio)
    expect(find.textContaining('Phoebe Fogg'), findsNothing);
  });
}
