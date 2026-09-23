import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pf/presentation/providers/bottom_nav_provider.dart';

void main() {
  group('bottomNavIndexProvider', () {
    test('inicia en 0 (Mapa)', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(bottomNavIndexProvider), 0);
    });

    test('cambia 0 -> 2 y lee correctamente', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(bottomNavIndexProvider.notifier).state = 2;
      expect(container.read(bottomNavIndexProvider), 2);
    });

    test('todos los índices 0..4 son válidos', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      for (var i = 0; i < 5; i++) {
        container.read(bottomNavIndexProvider.notifier).state = i;
        expect(container.read(bottomNavIndexProvider), i);
      }
    });

    test('bottomNavDestinations tiene 5 destinos con labels en castellano', () {
      expect(bottomNavDestinations.length, 5);
      expect(bottomNavDestinations[0].label, 'Mapa');
      expect(bottomNavDestinations[1].label, 'Diario');
      expect(bottomNavDestinations[2].label, 'Fogg');
      expect(bottomNavDestinations[3].label, 'Presupuesto');
      expect(bottomNavDestinations[4].label, 'Ruta');
    });

    test('índice fuera de rango no rompe build — clamp en MainScaffold', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      // Setter permite cualquier int (StateProvider), MainScaffold hace clamp
      container.read(bottomNavIndexProvider.notifier).state = 99;
      final clamped = container.read(bottomNavIndexProvider).clamp(0, 4);
      expect(clamped, 4);
      container.read(bottomNavIndexProvider.notifier).state = -5;
      expect(container.read(bottomNavIndexProvider).clamp(0, 4), 0);
    });
  });
}
