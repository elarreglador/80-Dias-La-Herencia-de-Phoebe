import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pf/domain/entities/destination_option.dart';
import 'package:pf/domain/entities/fogg_city.dart';
import 'package:pf/domain/entities/transport_mode.dart';
import 'package:pf/domain/models/weather_impact.dart';
import 'package:pf/presentation/widgets/destination_card.dart';

const _lisboa = FoggCity(
  name: 'Lisboa',
  lat: 38.7167,
  lng: -9.1333,
  order: 1,
  timezone: 'Europe/Lisbon',
);

const _ship = VehicleOption(
  mode: TransportMode.ship,
  duration: Duration(hours: 18),
  price: 8200,
  sleeper: true,
);

const _train = VehicleOption(
  mode: TransportMode.train,
  duration: Duration(hours: 14, minutes: 30),
  price: 6400,
);

DestinationOption _option({VehicleOption? vehicle}) => DestinationOption(
      city: _lisboa,
      vehicles: vehicle == null ? const [_ship, _train] : [vehicle],
    );

class _Harness extends StatefulWidget {
  const _Harness({super.key, required this.option, this.expanded = false});

  final DestinationOption option;
  final bool expanded;

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  late bool expanded = widget.expanded;
  VehicleOption? selectedVehicle;
  final List<VehicleOption> started = [];

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: DestinationCard(
          option: widget.option,
          selected: expanded,
          selectedVehicle: selectedVehicle,
          onTap: () => setState(() => expanded = !expanded),
          onVehicleTap: (v) => setState(() => selectedVehicle = v),
          onStartTrip: (v) => started.add(v),
        ),
      ),
    );
  }
}

Future<GlobalKey<_HarnessState>> _pump(
  WidgetTester tester,
  DestinationOption option, {
  bool expanded = false,
}) async {
  final key = GlobalKey<_HarnessState>();
  await tester.pumpWidget(_Harness(key: key, option: option, expanded: expanded));
  await tester.pump();
  return key;
}

FilledButton _button(WidgetTester tester, String city, TransportMode mode) {
  return tester.widget<FilledButton>(
    find.byKey(ValueKey('start-trip-$city-${mode.name}')),
  );
}

void main() {
  testWidgets('colapsada muestra el nombre y solo los iconos, sin precio ni duración',
      (tester) async {
    await _pump(tester, _option());

    expect(find.text('Lisboa'), findsOneWidget);
    expect(find.byKey(const ValueKey('vehicle-icon-Lisboa-ship')), findsOneWidget);
    expect(find.byKey(const ValueKey('vehicle-icon-Lisboa-train')), findsOneWidget);

    expect(find.text('8200€'), findsNothing);
    expect(find.text('18h'), findsNothing);
    expect(find.text('Iniciar trayecto'), findsNothing);
  });

  testWidgets('los iconos van en la cabecera y la expansión se anima', (tester) async {
    await _pump(tester, _option());

    // Colapsada: iconos en la cabecera (a la altura del nombre), sin check.
    expect(find.byKey(const ValueKey('vehicle-icon-Lisboa-ship')), findsOneWidget);
    expect(find.byKey(const ValueKey('vehicle-icon-Lisboa-train')), findsOneWidget);
    expect(find.byIcon(Icons.check_circle), findsNothing);
    expect(find.byType(AnimatedSize), findsOneWidget);

    final collapsedBody = tester.getSize(find.byType(AnimatedSize)).height;

    // Tocar la tarjeta la expande con una transición de tamaño.
    await tester.tap(find.byType(DestinationCard));
    await tester.pumpAndSettle();

    final expandedBody = tester.getSize(find.byType(AnimatedSize)).height;
    expect(expandedBody, greaterThan(collapsedBody));
    expect(find.byIcon(Icons.check_circle), findsOneWidget);
    expect(find.text('Iniciar trayecto'), findsNWidgets(2));
  });

  testWidgets('expandida muestra precio, duración, sleeper y botones deshabilitados',
      (tester) async {
    await _pump(tester, _option(), expanded: true);

    expect(find.text('8200€'), findsOneWidget);
    expect(find.text(' · 18h'), findsOneWidget);
    expect(find.text('sleeper'), findsOneWidget);
    expect(find.text('Iniciar trayecto'), findsNWidgets(2));
    expect(_button(tester, 'Lisboa', TransportMode.ship).onPressed, isNull);
    expect(_button(tester, 'Lisboa', TransportMode.train).onPressed, isNull);
  });

  testWidgets('tocar un vehículo lo selecciona, habilita su botón y el botón inicia',
      (tester) async {
    final key = await _pump(tester, _option(), expanded: true);

    await tester.tap(find.byKey(const ValueKey('vehicle-row-Lisboa-train')));
    await tester.pump();

    expect(key.currentState!.selectedVehicle, _train);
    expect(_button(tester, 'Lisboa', TransportMode.train).onPressed, isNotNull);
    expect(_button(tester, 'Lisboa', TransportMode.ship).onPressed, isNull);

    await tester.tap(find.byKey(const ValueKey('start-trip-Lisboa-train')));
    await tester.pump();

    expect(key.currentState!.started, [_train]);
  });

  testWidgets('un vehículo cancelado por clima no es seleccionable y muestra el motivo',
      (tester) async {
    const cancelled = VehicleOption(
      mode: TransportMode.train,
      duration: Duration(hours: 14),
      price: 6400,
      weatherImpact: WeatherImpact(cancelled: true, reason: 'Tormenta'),
    );
    final key = await _pump(tester, _option(vehicle: cancelled), expanded: true);

    expect(find.text('Tormenta'), findsOneWidget);
    expect(_button(tester, 'Lisboa', TransportMode.train).onPressed, isNull);

    await tester.tap(find.byKey(const ValueKey('vehicle-row-Lisboa-train')));
    await tester.pump();

    expect(key.currentState!.selectedVehicle, isNull);
    expect(_button(tester, 'Lisboa', TransportMode.train).onPressed, isNull);
  });
}
