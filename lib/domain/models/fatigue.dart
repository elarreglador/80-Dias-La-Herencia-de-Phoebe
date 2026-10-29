class Fatigue {
  const Fatigue({this.value = 100.0});

  final double value; // 0..100

  /// Tasa de drenaje (puntos por hora) al esperar en ciudad sin descanso.
  static const double cityDrainRate = 3.0;

  /// Tasa de recuperación (puntos por hora) en tramo con sleeper.
  static const double sleeperRecoverRate = 10.0;

  /// Tasa de recuperación (puntos por hora) en descanso en hotel.
  static const double hotelRecoverRate = 12.5;

  /// Tasa de drenaje (puntos por hora) en coche (sleeper == false).
  static const double carDrainRate = 8.0;

  /// Tasa de drenaje genérica (puntos por hora) en modos sin sleeper (mocks).
  static const double genericDrainRate = 5.0;

  bool get mustSleep => value <= 0.0;

  Fatigue drain(double amount) =>
      Fatigue(value: (value - amount).clamp(0.0, 100.0));

  Fatigue recover(double amount) =>
      Fatigue(value: (value + amount).clamp(0.0, 100.0));
}
