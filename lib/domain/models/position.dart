import '../entities/fogg_city.dart';
import 'fatigue.dart';

class Position {
  const Position({
    required this.city,
    required this.utc,
    required this.budget,
    this.fatigue = const Fatigue(),
  });

  final FoggCity city;
  final DateTime utc;
  final int budget;
  final Fatigue fatigue;
}
