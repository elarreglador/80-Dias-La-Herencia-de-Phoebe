import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pf/main.dart';

void main() {
  testWidgets('App carga con ProviderScope y muestra Phoebe Fogg', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: MyApp()));
    await tester.pumpAndSettle();
    expect(find.textContaining('Phoebe Fogg'), findsOneWidget);
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
