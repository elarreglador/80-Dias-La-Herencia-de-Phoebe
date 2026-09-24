import 'package:flutter_test/flutter_test.dart';
import 'package:pf/services/timezone_service.dart';

void main() {
  group('TimezoneService — hora civil DST-correcta', () {
    test('Europe/Paris invierno +01:00 verano +02:00', () {
      expect(TimezoneService.formatOffsetAt(DateTime.utc(2026, 1, 15), 'Europe/Paris'), '+01:00');
      expect(TimezoneService.formatOffsetAt(DateTime.utc(2026, 7, 15), 'Europe/Paris'), '+02:00');
    });
    test('America/New_York -05:00 / -04:00', () {
      expect(TimezoneService.formatOffsetAt(DateTime.utc(2026, 1, 15), 'America/New_York'), '-05:00');
      expect(TimezoneService.formatOffsetAt(DateTime.utc(2026, 7, 15), 'America/New_York'), '-04:00');
    });
    test('America/Los_Angeles -08:00 / -07:00', () {
      expect(TimezoneService.formatOffsetAt(DateTime.utc(2026, 1, 15), 'America/Los_Angeles'), '-08:00');
      expect(TimezoneService.formatOffsetAt(DateTime.utc(2026, 7, 15), 'America/Los_Angeles'), '-07:00');
    });
    test('Asia/Kolkata sin DST +05:30', () {
      expect(TimezoneService.formatOffsetAt(DateTime.utc(2026, 7, 15), 'Asia/Kolkata'), '+05:30');
      expect(TimezoneService.formatOffsetAt(DateTime.utc(2026, 1, 15), 'Asia/Kolkata'), '+05:30');
    });
    test('Asia/Tokyo +09:00', () {
      expect(TimezoneService.formatOffsetAt(DateTime.utc(2026, 7, 15), 'Asia/Tokyo'), '+09:00');
    });
    test('Europe/London +00:00 / +01:00', () {
      expect(TimezoneService.formatOffsetAt(DateTime.utc(2026, 1, 15), 'Europe/London'), '+00:00');
      expect(TimezoneService.formatOffsetAt(DateTime.utc(2026, 7, 15), 'Europe/London'), '+01:00');
    });
    test('Transición DST EU 2026-03-29', () {
      expect(TimezoneService.formatOffsetAt(DateTime.utc(2026, 3, 29, 0, 59), 'Europe/Paris'), '+01:00');
      expect(TimezoneService.formatOffsetAt(DateTime.utc(2026, 3, 29, 1, 0), 'Europe/Paris'), '+02:00');
    });
    test('toLocal convierte correctamente', () {
      final utc = DateTime.utc(2026, 7, 15, 12, 0);
      final parisLocal = TimezoneService.toLocal(utc, 'Europe/Paris');
      expect(parisLocal.hour, 14); // 12 UTC +2
      final nyLocal = TimezoneService.toLocal(utc, 'America/New_York');
      expect(nyLocal.hour, 8); // 12 UTC -4
    });
  });
}
