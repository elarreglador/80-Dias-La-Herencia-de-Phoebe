import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pf/domain/models/fatigue.dart';
import 'package:pf/presentation/widgets/hotel_rest_card.dart';

void main() {
  Future<void> pump(
    WidgetTester tester, {
    required bool isRestingAtHotel,
    required Fatigue fatigue,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HotelRestCard(
            onRestAtHotel: () {},
            hotelPrice: 90,
            fatigue: fatigue,
            isRestingAtHotel: isRestingAtHotel,
          ),
        ),
      ),
    );
  }

  testWidgets('HotelRestCard muestra icono, precio y mensaje de descanso', (tester) async {
    await pump(tester, isRestingAtHotel: false, fatigue: const Fatigue(value: 40));

    expect(find.byKey(const ValueKey('hotel-rest-card')), findsOneWidget);
    expect(find.text('Ir al Hotel a descansar'), findsOneWidget);
    expect(find.byIcon(Icons.hotel), findsOneWidget);
    expect(find.text('90€'), findsOneWidget);
    expect(find.textContaining('Descanso en hotel'), findsOneWidget);
  });

  testWidgets('HotelRestCard muestra el estado de descanso en curso', (tester) async {
    await pump(tester, isRestingAtHotel: true, fatigue: const Fatigue(value: 40));

    expect(find.text('Descansando en el hotel...'), findsOneWidget);
  });

  testWidgets('HotelRestCard muestra el mensaje de agotamiento cuando debe descansar',
      (tester) async {
    await pump(tester, isRestingAtHotel: false, fatigue: const Fatigue(value: 0));

    expect(find.textContaining('Phoebe está agotada'), findsOneWidget);
  });

  testWidgets('HotelRestCard invoca la accion al tocarla', (tester) async {
    var invoked = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HotelRestCard(
            onRestAtHotel: () => invoked = true,
            hotelPrice: 90,
            fatigue: const Fatigue(value: 40),
            isRestingAtHotel: false,
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('hotel-rest-card')));
    await tester.pump();

    expect(invoked, isTrue);
  });
}
