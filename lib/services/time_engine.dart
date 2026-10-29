import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../domain/models/fatigue.dart';
import 'timezone_service.dart';

typedef UtcClock = DateTime Function();

class TimeEngine {
  TimeEngine({
    required DateTime startUtc,
    double timeScale = 1.0,
    UtcClock? clock,
  })  : _gameStartUtc = startUtc.toUtc(),
        _timeScale = _clampScale(timeScale, kReleaseMode),
        _clock = clock ?? (() => DateTime.now().toUtc());

  final DateTime _gameStartUtc;
  final double _timeScale;
  final UtcClock _clock;
  DateTime _realStartUtc = DateTime.now().toUtc();

  // Para tests: si se inyecta clock, el ancla real se toma en la primera llamada.
  bool _anchored = false;

  static double _clampScale(double scale, bool release) {
    if (release) return 1.0;
    if (scale <= 0) return 1.0;
    return scale;
  }

  DateTime _realNow() => _clock();

  DateTime now() {
    if (!_anchored) {
      _realStartUtc = _realNow();
      _anchored = true;
    }
    final elapsedReal = _realNow().difference(_realStartUtc);
    final elapsedGame = Duration(
      microseconds: (elapsedReal.inMicroseconds * _timeScale).round(),
    );
    return _gameStartUtc.add(elapsedGame);
  }

  Stream<DateTime> clock() async* {
    yield now();
    // Evita Timer.periodic pendiente en tests (TestWidgetsFlutterBinding).
    final binding = WidgetsBinding.instance;
    final isTest = binding.runtimeType.toString().contains('Test');
    if (isTest) return;
    yield* Stream.periodic(const Duration(seconds: 1), (_) => now());
  }

  DateTime nextDeparture(DateTime arrivalUtc, {bool sleeper = false}) {
    final rest = sleeper
        ? const Duration(hours: 5)
        : const Duration(hours: 8);
    return arrivalUtc.toUtc().add(rest);
  }

  DateTime nextScheduledDeparture(
    DateTime arrivalUtc, {
    required String originTimezone,
    required int? departureHour,
    required int? departureMinute,
    bool sleeper = false,
  }) {
    final rest = sleeper
        ? const Duration(hours: 5)
        : const Duration(hours: 8);
    final earliest = arrivalUtc.toUtc().add(rest);

    if (departureHour == null || departureMinute == null) {
      return earliest;
    }

    final offset = TimezoneService.offsetAt(earliest, originTimezone);
    var candidateLocal = DateTime.utc(
      earliest.year,
      earliest.month,
      earliest.day,
      departureHour,
      departureMinute,
    );
    var candidateUtc = candidateLocal.subtract(offset);

    if (candidateUtc.isBefore(earliest)) {
      candidateLocal = candidateLocal.add(const Duration(days: 1));
      final approxUtc = candidateLocal.subtract(offset);
      final offset2 = TimezoneService.offsetAt(approxUtc, originTimezone);
      candidateUtc = candidateLocal.subtract(offset2);
    }

    return candidateUtc.toUtc();
  }

  Duration sleepNeeded(Fatigue fatigue, {required double rate}) {
    final missing = (100.0 - fatigue.value).clamp(0.0, 100.0);
    if (missing <= 0) return Duration.zero;
    final hours = (missing / rate).ceil().clamp(1, 8);
    return Duration(hours: hours);
  }
}
