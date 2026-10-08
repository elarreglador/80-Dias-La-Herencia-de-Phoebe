import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Regla de excepción de SPEC 008: una ciudad se acepta si su `Decisión`
/// (minúsculas y sin acentos) empieza por `excepcion`.
String _normalize(String value) {
  const table = <String, String>{
    'á': 'a', 'à': 'a', 'ä': 'a', 'â': 'a',
    'é': 'e', 'è': 'e', 'ë': 'e', 'ê': 'e',
    'í': 'i', 'ì': 'i', 'ï': 'i', 'î': 'i',
    'ó': 'o', 'ò': 'o', 'ö': 'o', 'ô': 'o',
    'ú': 'u', 'ù': 'u', 'ü': 'u', 'û': 'u',
    'ñ': 'n', 'ç': 'c',
  };
  final buffer = StringBuffer();
  for (final ch in value.toLowerCase().split('')) {
    buffer.write(table[ch] ?? ch);
  }
  return buffer.toString();
}

bool _isException(String decision) =>
    _normalize(decision).startsWith('excepcion');

/// Columna `Decisión` del informe, indexada por ciudad.
///
/// El parser lee por cabecera de columna (no por posición): si la tabla
/// cambia de columnas, las decisiones no se pierden. Mismo criterio que
/// `read_decisions` de `tools/route_coverage.py`.
Map<String, String> _readDecisions(File report) {
  if (!report.existsSync()) return {};
  final decisions = <String, String>{};
  var nameIdx = -1;
  var decisionIdx = -1;
  for (final line in report.readAsLinesSync()) {
    final trimmed = line.trim();
    if (!trimmed.startsWith('|')) continue;
    final body = trimmed.substring(
      1,
      trimmed.length - (trimmed.endsWith('|') ? 1 : 0),
    );
    final cells = body.split('|').map((c) => c.trim()).toList();
    if (nameIdx < 0 || decisionIdx < 0) {
      final normalized = cells.map(_normalize).toList();
      if (normalized.contains('ciudad') && normalized.contains('decision')) {
        nameIdx = normalized.indexOf('ciudad');
        decisionIdx = normalized.indexOf('decision');
      }
      continue;
    }
    if (cells.every((c) => c.isEmpty || c == '-')) continue;
    if (cells.length <= (nameIdx > decisionIdx ? nameIdx : decisionIdx)) {
      continue; // fila mal formada
    }
    decisions[cells[nameIdx]] = cells[decisionIdx];
  }
  return decisions;
}

List<dynamic> _routesOf(String path) {
  final data =
      jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;
  return (data['routes'] as List<dynamic>?) ?? const [];
}

void main() {
  test('la regla excepcion* admite "Excepción — motivo" y rechaza texto libre',
      () {
    expect(_isException('excepción — isla sin red'), isTrue);
    expect(_isException('Excepcion sin puerto'), isTrue);
    expect(_isException('pendiente'), isFalse);
    expect(_isException(''), isFalse);
  });

  test('toda ciudad de locations.json tiene salida y entrada, o excepción',
      () {
    final locations = jsonDecode(
      File('assets/data/locations.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final cities = (locations['cities'] as List<dynamic>)
        .map((c) => (c as Map<String, dynamic>)['name'] as String);

    final outbound = <String>{};
    final inbound = <String>{};
    for (final route in [
      ..._routesOf('assets/data/sea_routes.json'),
      ..._routesOf('assets/data/car_routes.json'),
    ]) {
      final r = route as Map<String, dynamic>;
      final origin = r['origin'] as String?;
      final destination = r['destination'] as String?;
      if (origin != null) outbound.add(origin);
      if (destination != null) inbound.add(destination);
    }

    final decisions =
        _readDecisions(File('docs/ciudades-sin-rutas.md'));
    final pending = [
      for (final name in cities)
        if (!outbound.contains(name) || !inbound.contains(name))
          if (!_isException(decisions[name] ?? '')) name,
    ]..sort();

    expect(
      pending,
      isEmpty,
      reason: 'Ciudades sin cobertura (sin salida o sin entrada) y sin '
          '`excepción` en docs/ciudades-sin-rutas.md '
          '(${pending.length}): ${pending.join(', ')}',
    );
  });
}
