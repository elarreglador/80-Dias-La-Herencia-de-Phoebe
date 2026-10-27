/// Zonas geográficas para el precio base del km ferroviario.
enum GeoZone {
  europeDeveloped,
  northAmerica,
  asiaDeveloped,
  asiaDeveloping,
  oceania,
  africa,
  southAmerica,
  middleEast,
}

/// Precio del billete de tren — base por zona × multiplicador del país.
///
/// El base refleja el coste de infraestructura de la zona; el multiplicador,
/// el nivel económico del país de llegada. Fuentes del base:
/// traintrackings.com (2025), T&E Ranking (2024), Pedestrian Observations (2024).
class RailPricing {
  const RailPricing._();

  /// Precio base en €/km por zona (2ª clase intercity, tarifa publicada media).
  static const basePricePerKm = <GeoZone, double>{
    GeoZone.europeDeveloped: 0.15,
    GeoZone.northAmerica: 0.16,
    GeoZone.asiaDeveloped: 0.18, // Japón
    GeoZone.asiaDeveloping: 0.06, // China, India, SE asiático
    GeoZone.oceania: 0.11,
    GeoZone.africa: 0.05, // estimación
    GeoZone.southAmerica: 0.08, // estimación
    GeoZone.middleEast: 0.07, // estimación
  };

  /// Prefijos de `America/` que corresponden a EE.UU. y Canadá.
  static const _northAmerica = <String>{
    'Anchorage', 'Chicago', 'Denver', 'Detroit', 'Goose_Bay', 'Inuvik',
    'Los_Angeles', 'New_York', 'Phoenix', 'Regina', 'St_Johns', 'Toronto',
    'Vancouver', 'Winnipeg', 'Yakutat', 'Edmonton',
  };

  /// Golfo y Levante — se separan del resto de `Asia/`.
  static const _middleEast = <String>{
    'Asia/Aden', 'Asia/Baghdad', 'Asia/Dubai', 'Asia/Jerusalem',
    'Asia/Muscat', 'Asia/Riyadh', 'Asia/Tehran',
  };

  /// Asia desarrollada — Japón, Corea del Sur, Taiwán y Singapur.
  static const _asiaDeveloped = <String>{
    'Asia/Tokyo', 'Asia/Seoul', 'Asia/Taipei', 'Asia/Singapore',
  };

  /// Deriva la zona del huso IANA (prefijo de región + país).
  static GeoZone zoneForTimezone(String tz) {
    if (tz.startsWith('Europe/')) return GeoZone.europeDeveloped;
    if (tz.startsWith('Africa/')) return GeoZone.africa;
    if (tz.startsWith('Australia/') || tz.startsWith('Pacific/')) {
      return GeoZone.oceania;
    }
    if (tz.startsWith('Atlantic/')) {
      if (tz == 'Atlantic/St_Helena') return GeoZone.africa;
      return GeoZone.europeDeveloped; // Atlántico europeo (Feroe, Azores…)
    }
    if (tz.startsWith('America/')) {
      // 'America/Argentina/Cordoba' → 'Argentina' (Sudamérica) por prefijo.
      final region = tz.split('/')[1];
      return _northAmerica.contains(region)
          ? GeoZone.northAmerica
          : GeoZone.southAmerica;
    }
    if (tz.startsWith('Asia/')) {
      if (_middleEast.contains(tz)) return GeoZone.middleEast;
      if (_asiaDeveloped.contains(tz)) return GeoZone.asiaDeveloped;
      return GeoZone.asiaDeveloping;
    }
    // Huso genérico (UTC, etc.): el juego arranca en Europa.
    return GeoZone.europeDeveloped;
  }

  /// Multiplicador económico relativo (base España = 1.0).
  /// Tabla semilla por huso IANA exacto; fallback 1.0 si no hay entrada.
  static const _countryMultiplier = <String, double>{
    // África
    'Africa/Abidjan': 0.30, 'Africa/Algiers': 0.40, 'Africa/Bamako': 0.25,
    'Africa/Brazzaville': 0.30, 'Africa/Cairo': 0.35, 'Africa/Casablanca': 0.45,
    'Africa/Dakar': 0.35, 'Africa/Dar_es_Salaam': 0.25, 'Africa/Gaborone': 0.50,
    'Africa/Harare': 0.25, 'Africa/Johannesburg': 0.55, 'Africa/Kampala': 0.25,
    'Africa/Khartoum': 0.20, 'Africa/Lagos': 0.35, 'Africa/Libreville': 0.40,
    'Africa/Luanda': 0.40, 'Africa/Lubumbashi': 0.20, 'Africa/Lusaka': 0.30,
    'Africa/Malabo': 0.35, 'Africa/Monrovia': 0.20, 'Africa/Nairobi': 0.35,
    'Africa/Ndjamena': 0.20, 'Africa/Niamey': 0.20, 'Africa/Nouakchott': 0.25,
    'Africa/Tripoli': 0.40, 'Africa/Windhoek': 0.45,
    // América del Norte
    'America/Anchorage': 1.10, 'America/Chicago': 1.10, 'America/Denver': 1.10,
    'America/Detroit': 1.10, 'America/Edmonton': 1.10, 'America/Goose_Bay': 1.10,
    'America/Inuvik': 1.10, 'America/Los_Angeles': 1.10, 'America/New_York': 1.10,
    'America/Phoenix': 1.10, 'America/Regina': 1.10, 'America/St_Johns': 1.10,
    'America/Toronto': 1.10, 'America/Vancouver': 1.10, 'America/Winnipeg': 1.10,
    'America/Yakutat': 1.10,
    // América Central, Caribe y Sudamérica
    'America/Argentina/Cordoba': 0.55, 'America/Bahia': 0.60,
    'America/Belem': 0.60, 'America/Bogota': 0.50, 'America/Cancun': 0.65,
    'America/Chihuahua': 0.65, 'America/Ciudad_Juarez': 0.65,
    'America/El_Salvador': 0.55, 'America/Fortaleza': 0.60,
    'America/Guatemala': 0.55, 'America/Guayaquil': 0.50, 'America/Guyana': 0.60,
    'America/La_Paz': 0.45, 'America/Lima': 0.55, 'America/Managua': 0.55,
    'America/Mazatlan': 0.65, 'America/Merida': 0.65, 'America/Mexico_City': 0.65,
    'America/Monterrey': 0.65, 'America/Panama': 0.55, 'America/Puerto_Rico': 0.90,
    'America/Sao_Paulo': 0.60, 'America/Tegucigalpa': 0.55,
    // Asia desarrollada
    'Asia/Tokyo': 1.20, 'Asia/Macau': 1.20,
    // Oriente Medio
    'Asia/Aden': 0.25, 'Asia/Baghdad': 0.40, 'Asia/Dubai': 0.90,
    'Asia/Jerusalem': 1.15, 'Asia/Muscat': 0.75, 'Asia/Riyadh': 0.75,
    'Asia/Tehran': 0.45,
    // Asia en desarrollo (resto)
    'Asia/Almaty': 0.55, 'Asia/Anadyr': 0.45, 'Asia/Aqtobe': 0.55,
    'Asia/Ashgabat': 0.60, 'Asia/Baku': 0.55, 'Asia/Bangkok': 0.50,
    'Asia/Chita': 0.45, 'Asia/Ho_Chi_Minh': 0.40, 'Asia/Irkutsk': 0.45,
    'Asia/Jakarta': 0.40, 'Asia/Jayapura': 0.40, 'Asia/Kabul': 0.25,
    'Asia/Kolkata': 0.30, 'Asia/Krasnoyarsk': 0.45, 'Asia/Kuala_Lumpur': 0.60,
    'Asia/Kuching': 0.60, 'Asia/Magadan': 0.45, 'Asia/Manila': 0.40,
    'Asia/Novosibirsk': 0.45, 'Asia/Omsk': 0.45, 'Asia/Pyongyang': 0.30,
    'Asia/Qyzylorda': 0.55, 'Asia/Samarkand': 0.45, 'Asia/Shanghai': 0.45,
    'Asia/Ulaanbaatar': 0.45, 'Asia/Urumqi': 0.45, 'Asia/Vladivostok': 0.45,
    'Asia/Yakutsk': 0.45, 'Asia/Yekaterinburg': 0.45,
    // Atlántico
    'Atlantic/Faroe': 1.10, 'Atlantic/St_Helena': 0.60,
    // Oceanía
    'Australia/Adelaide': 1.10, 'Australia/Brisbane': 1.10,
    'Australia/Darwin': 1.10, 'Australia/Hobart': 1.10,
    'Australia/Melbourne': 1.10, 'Australia/Perth': 1.10,
    'Australia/Sydney': 1.10, 'Pacific/Apia': 0.70, 'Pacific/Easter': 0.85,
    'Pacific/Fakaofo': 0.70, 'Pacific/Tahiti': 1.10,
    // Europa (base España = 1.0)
    'Europe/Madrid': 1.0, 'Europe/Amsterdam': 1.15, 'Europe/Berlin': 1.10,
    'Europe/Brussels': 1.10, 'Europe/Bucharest': 0.50, 'Europe/Helsinki': 1.15,
    'Europe/Istanbul': 0.55, 'Europe/Kyiv': 0.35, 'Europe/Lisbon': 0.85,
    'Europe/London': 1.15, 'Europe/Moscow': 0.45, 'Europe/Oslo': 1.30,
    'Europe/Paris': 1.10, 'Europe/Prague': 0.70, 'Europe/Riga': 0.65,
    'Europe/Rome': 1.05, 'Europe/Samara': 0.45, 'Europe/Saratov': 0.45,
    'Europe/Stockholm': 1.15, 'Europe/Tallinn': 0.75, 'Europe/Warsaw': 0.55,
    'Europe/Zagreb': 0.70,
  };

  static double countryMultiplierForTimezone(String tz) =>
      _countryMultiplier[tz] ?? 1.0;

  /// Precio final por km para un tramo concreto.
  static double pricePerKm({
    required GeoZone zone,
    required double countryMultiplier,
  }) =>
      basePricePerKm[zone]! * countryMultiplier;
}
