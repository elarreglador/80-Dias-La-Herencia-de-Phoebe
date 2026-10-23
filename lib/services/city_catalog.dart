import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../domain/entities/fogg_city.dart';

/// Catálogo de ciudades — `assets/data/locations.json`.
///
/// Resuelve por nombre las coordenadas y la zona horaria IANA reales.
/// Los nombres se normalizan (NFD, sin diacríticos, sin distinguir
/// mayúsculas) para que "París" y "Paris" resuelvan a la misma ciudad.
class CityCatalog {
  CityCatalog._(this._byName, this._aliases, this.length);

  /// Ruta del asset con el catálogo de ciudades.
  static const String assetPath = 'assets/data/locations.json';

  /// Ciudades indexadas por nombre normalizado.
  final Map<String, FoggCity> _byName;

  /// Alias por nombre ascii normalizado (el nombre local manda).
  final Map<String, FoggCity> _aliases;

  /// Número de ciudades cargadas.
  final int length;

  /// Ciudad por nombre (normalización NFD, sin distinguir mayúsculas).
  FoggCity? byName(String name) {
    final key = _normalize(name);
    return _byName[key] ?? _aliases[key];
  }

  /// Carga el catálogo desde un [AssetBundle].
  static Future<CityCatalog> load(AssetBundle bundle) async {
    final raw = await bundle.loadString(assetPath);
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      return CityCatalog._(const {}, const {}, 0);
    }
    final cities = decoded['cities'];
    if (cities is! List) {
      return CityCatalog._(const {}, const {}, 0);
    }

    final byName = <String, FoggCity>{};
    final aliases = <String, FoggCity>{};
    var count = 0;
    for (var i = 0; i < cities.length; i++) {
      final item = cities[i];
      if (item is! Map<String, dynamic>) continue;
      final name = item['name'];
      final lat = item['lat'];
      final lng = item['lng'];
      if (name is! String || lat is! num || lng is! num) continue;
      final timezone = item['timezone'];
      final city = FoggCity(
        name: name,
        lat: lat.toDouble(),
        lng: lng.toDouble(),
        order: i,
        timezone: timezone is String && timezone.isNotEmpty ? timezone : 'UTC',
      );
      count++;

      // La clave primaria es el nombre local; si se repite, gana la primera.
      final key = _normalize(name);
      if (byName.containsKey(key)) {
        debugPrint('CityCatalog: nombre duplicado ignorado — "$key"');
        continue;
      }
      byName[key] = city;

      // El ascii hace de alias, pero nunca pisa un nombre local.
      final ascii = item['asciiname'];
      if (ascii is String && ascii.isNotEmpty) {
        final aliasKey = _normalize(ascii);
        if (!byName.containsKey(aliasKey) && !aliases.containsKey(aliasKey)) {
          aliases[aliasKey] = city;
        }
      }
    }

    return CityCatalog._(
      Map.unmodifiable(byName),
      Map.unmodifiable(aliases),
      count,
    );
  }

  /// Normaliza un nombre de ciudad: minúsculas y sin diacríticos.
  ///
  /// Equivalente a descomponer en NFD y retirar las marcas combinantes,
  /// resuelto con una tabla de equivalencias para el latín (Latin-1
  /// Supplement + Latin Extended-A) sin dependencias nuevas.
  static String _normalize(String value) {
    final lower = value.trim().toLowerCase();
    final buffer = StringBuffer();
    for (final rune in lower.runes) {
      if (rune >= 0x00C0 && rune <= 0x017F) {
        final base = _latinBaseTable[rune - 0x00C0];
        if (base != '.') {
          buffer.write(base);
          continue;
        }
      }
      buffer.writeCharCode(rune);
    }
    return buffer.toString();
  }

  /// Letras base ASCII para U+00C0..U+017F ('.' = sin equivalencia).
  static const String _latinBaseTable =
      'AAAAAA.CEEEEIIII.NOOOOO..UUUUY..aaaaaa.ceeeeiiii.nooooo..uuuuy.y'
      'AaAaAaCcCcCcCcDd..EeEeEeEeEeGgGgGgGgHh..IiIiIiIiI.IiJjKk.LlLlLlLl'
      '..NnNnNn...OoOoOo..RrRrRrSsSsSsSsTtTt..UuUuUuUuUuUuWwYyYZzZzZzs';
}
