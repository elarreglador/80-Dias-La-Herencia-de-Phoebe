import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pf/services/city_catalog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CityCatalog', () {
    test('carga el asset real y resuelve todas sus ciudades', () async {
      final raw = await rootBundle.loadString(CityCatalog.assetPath);
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final cities = decoded['cities'] as List;

      final catalog = await CityCatalog.load(rootBundle);
      expect(catalog.length, cities.length);
      expect(catalog.length, greaterThan(200));
    });

    test('resuelve una ciudad con sus coordenadas y timezone IANA', () async {
      final catalog = await CityCatalog.load(rootBundle);
      final londres = catalog.byName('Londres');
      expect(londres, isNotNull);
      expect(londres!.name, 'Londres');
      expect(londres.lat, closeTo(51.50853, 1e-5));
      expect(londres.lng, closeTo(-0.12574, 1e-5));
      expect(londres.timezone, 'Europe/London');
      expect(londres.timezone, isNot('UTC'));
    });

    test('normaliza: sin acentos, sin distinguir mayúsculas', () async {
      final catalog = await CityCatalog.load(rootBundle);
      final paris = catalog.byName('París');
      expect(paris, isNotNull);
      expect(catalog.byName('paris'), paris);
      expect(catalog.byName('PARIS'), paris);
      expect(catalog.byName('  París  '), paris);
      // Con diacríticos poco comunes (Latin Extended-A).
      expect(catalog.byName('Kaesŏng'), isNotNull);
      expect(catalog.byName('Wonsan'), isNotNull);
      // Con espacios y mayúsculas.
      expect(catalog.byName('san luis potosí'), isNotNull);
    });

    test('la ciudad desconocida devuelve null', () async {
      final catalog = await CityCatalog.load(rootBundle);
      expect(catalog.byName('Atlántida Imaginaria'), isNull);
      expect(catalog.byName(''), isNull);
    });

    test('el orden es el índice en el array del fichero', () async {
      final raw = await rootBundle.loadString(CityCatalog.assetPath);
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final cities = decoded['cities'] as List;

      final catalog = await CityCatalog.load(rootBundle);
      for (var i = 0; i < cities.length; i += 37) {
        final entry = cities[i] as Map<String, dynamic>;
        final city = catalog.byName(entry['name'] as String);
        expect(city, isNotNull);
        expect(city!.order, i);
      }
    });
  });
}
