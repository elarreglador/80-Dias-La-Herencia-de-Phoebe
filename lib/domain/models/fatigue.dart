class Fatigue {
  const Fatigue({this.value = 100.0});

  final double value; // 0..100

  bool get mustSleep => value <= 0.0;

  Fatigue drain(double amount) =>
      Fatigue(value: (value - amount).clamp(0.0, 100.0));

  Fatigue recover(double amount) =>
      Fatigue(value: (value + amount).clamp(0.0, 100.0));
}
