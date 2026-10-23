import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pf/domain/entities/fogg_city.dart';
import 'package:pf/presentation/providers/bottom_nav_provider.dart';
import 'package:pf/presentation/providers/map_focus_provider.dart';
import 'package:pf/presentation/providers/time_engine_provider.dart';
import 'package:pf/presentation/widgets/city_info_card.dart';
import 'package:pf/services/time_engine.dart';
import 'package:pf/services/timezone_service.dart';

const _tokyo = FoggCity(
  name: 'Tokio',
  lat: 35.6762,
  lng: 139.6503,
  order: 4,
  timezone: 'Asia/Tokyo',
);

void main() {
  setUpAll(TimezoneService.init);

  TimeEngine fixedClock() => TimeEngine(
        startUtc: DateTime.utc(2026, 1, 15, 5),
        timeScale: 1.0,
        clock: () => DateTime.utc(2026, 1, 15, 5),
      );

  testWidgets('muestra la hora local IANA de la ciudad y su nombre', (tester) async {
    final container = ProviderContainer(
      overrides: [timeEngineProvider.overrideWithValue(fixedClock())],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(body: CityInfoCard(city: _tokyo)),
        ),
      ),
    );
    await tester.pump();

    // 05:00 UTC en Asia/Tokyo (UTC+9) → 14:00, nunca la hora UTC.
    expect(find.text('14:00'), findsOneWidget);
    expect(find.text('05:00'), findsNothing);
    expect(find.text('Tokio'), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);
  });

  testWidgets('el pin abre el mapa con zoom medio y cambia a la pestaña Mapa',
      (tester) async {
    final container = ProviderContainer(
      overrides: [timeEngineProvider.overrideWithValue(fixedClock())],
    );
    addTearDown(container.dispose);
    container.read(bottomNavIndexProvider.notifier).state = 3;

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(body: CityInfoCard(city: _tokyo)),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byIcon(Icons.location_on));
    await tester.pump();

    final request = container.read(mapFocusProvider);
    expect(request, isNotNull);
    expect(request!.city, _tokyo);
    expect(request.zoom, 7.0);
    expect(container.read(bottomNavIndexProvider), 0);
  });
}
