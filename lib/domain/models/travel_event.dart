import '../entities/fogg_leg.dart';
import 'fatigue.dart';

sealed class TravelEvent {
  const TravelEvent();

  Object applyTo(Object target);
}

class DelayEvent extends TravelEvent {
  const DelayEvent({required this.hours});

  final double hours;

  @override
  Object applyTo(Object target) {
    if (target is! FoggLeg) {
      throw ArgumentError('DelayEvent.applyTo expects a FoggLeg');
    }
    return applyToLeg(target);
  }

  FoggLeg applyToLeg(FoggLeg leg) {
    return FoggLeg(
      from: leg.from,
      to: leg.to,
      transport: leg.transport,
      departureUtc: leg.departureUtc,
      arrivalUtc: leg.arrivalUtc.add(Duration(minutes: (hours * 60).round())),
      price: leg.price,
      sleeper: leg.sleeper,
    );
  }
}

class StormEvent extends TravelEvent {
  const StormEvent({required this.severity, required this.extraFatigue});

  final int severity;
  final double extraFatigue;

  @override
  Object applyTo(Object target) {
    if (target is! Fatigue) {
      throw ArgumentError('StormEvent.applyTo expects a Fatigue');
    }
    return applyToFatigue(target);
  }

  Fatigue applyToFatigue(Fatigue fatigue) => fatigue.drain(extraFatigue);
}
