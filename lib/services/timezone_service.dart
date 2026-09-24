import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz_data;

/// Servicio de zona horaria civil DST-correcta para Phoebe Fogg.
///
/// Deriva el offset numérico `-7/+2` a partir de IANA (`Europe/Paris`,
/// `America/Los_Angeles`…) para una fecha UTC concreta, respetando
/// cambios de horario de cada país. No persiste offset; lo calcula.
///
/// Uso:
/// ```dart
/// TimezoneService.init(); // una vez en main()
/// final offset = TimezoneService.offsetAt(DateTime.utc(2026,7,15), 'Europe/Paris'); // +02:00
/// final local = TimezoneService.toLocal(DateTime.now().toUtc(), 'Asia/Tokyo');
/// ```
class TimezoneService {
  static bool _initialized = false;

  /// Inicializa la base de datos tz. Idempotente.
  static void init() {
    if (_initialized) return;
    tz_data.initializeTimeZones();
    _initialized = true;
  }

  /// Garantiza inicialización y devuelve [Location] para [iana].
  /// Si [iana] no existe (p.ej. `Etc/GMT`), cae a UTC.
  static tz.Location _locationFor(String iana) {
    init();
    try {
      return tz.getLocation(iana);
    } catch (_) {
      // Fallback Etc/GMT±X o UTC
      try {
        if (iana.startsWith('Etc/GMT')) return tz.getLocation(iana);
      } catch (_) {}
      return tz.UTC;
    }
  }

  /// Offset DST-correcto para [utc] en [iana].
  /// Ej. Paris 2026-01-15 → +01:00, 2026-07-15 → +02:00.
  static Duration offsetAt(DateTime utc, String iana) {
    assert(utc.isUtc, 'offsetAt requiere DateTime.utc');
    final loc = _locationFor(iana);
    final tzDate = tz.TZDateTime.from(utc, loc);
    return tzDate.timeZoneOffset;
  }

  /// Convierte [utc] a hora civil local en [iana].
  static DateTime toLocal(DateTime utc, String iana) {
    assert(utc.isUtc, 'toLocal requiere DateTime.utc');
    return utc.add(offsetAt(utc, iana));
  }

  /// Formatea [offset] como `+02:00` / `-07:00` / `+05:30`.
  static String formatOffset(Duration offset) {
    final sign = offset.isNegative ? '-' : '+';
    final absMinutes = offset.inMinutes.abs();
    final hours = (absMinutes ~/ 60).toString().padLeft(2, '0');
    final minutes = (absMinutes % 60).toString().padLeft(2, '0');
    return '$sign$hours:$minutes';
  }

  /// Atajo: offset formateado para [utc] en [iana].
  static String formatOffsetAt(DateTime utc, String iana) =>
      formatOffset(offsetAt(utc, iana));

  /// Hora civil formateada `HH:mm` para [utc] en [iana].
  static String formatLocalTime(DateTime utc, String iana) {
    final local = toLocal(utc, iana);
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }

  /// Indica si [utc] cae en horario de verano para [iana].
  static bool isDst(DateTime utc, String iana) {
    final loc = _locationFor(iana);
    final tzDate = tz.TZDateTime.from(utc, loc);
    // timeZoneOffset cambia en DST; comparar con offset estándar es complejo.
    // Aproximación: si offset != offset en enero, es DST (hemisferio norte).
    // Para genérico, delega a tz: si hay DST, el nombre cambia (CEST vs CET).
    // Simplificamos: no hay API directa; usamos heurística de 2 fechas.
    // Si el offset en utc difiere del offset en 2026-01-15, asumimos DST.
    final jan = tz.TZDateTime.from(DateTime.utc(utc.year, 1, 15), loc);
    return tzDate.timeZoneOffset != jan.timeZoneOffset;
  }
}
