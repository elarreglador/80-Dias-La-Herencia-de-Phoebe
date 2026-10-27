import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:pf/domain/entities/fogg_city.dart';
import 'package:pf/domain/entities/fogg_leg.dart';
import 'package:pf/domain/entities/transport_mode.dart';
import 'package:pf/presentation/widgets/active_leg_fit.dart';

const _london = FoggCity(
  name: 'Londres',
  lat: 51.5072,
  lng: -0.1276,
  order: 0,
  timezone: 'UTC',
);
const _paris = FoggCity(
  name: 'París',
  lat: 48.8566,
  lng: 2.3522,
  order: 1,
  timezone: 'UTC',
);
const _fukuoka = FoggCity(
  name: 'Fukuoka',
  lat: 33.5904,
  lng: 130.4017,
  order: 0,
  timezone: 'UTC',
);
const _vancouver = FoggCity(
  name: 'Vancouver',
  lat: 49.2827,
  lng: -123.1207,
  order: 1,
  timezone: 'UTC',
);

FoggLeg _leg(FoggCity from, FoggCity to) => FoggLeg(
      from: from,
      to: to,
      transport: TransportMode.ship,
      departureUtc: DateTime.utc(2026, 1, 1),
      arrivalUtc: DateTime.utc(2026, 1, 2),
      price: 100,
    );

MapCamera _camera({Size size = const Size(800, 600)}) => MapCamera(
      crs: const Epsg3857(),
      center: const LatLng(0, 0),
      zoom: 3,
      rotation: 0,
      nonRotatedSize: size,
      minZoom: 2,
      maxZoom: 18,
    );

void main() {
  group('activeLegBounds', () {
    test('par normal — bounds contiguos con orden correcto', () {
      final bounds = activeLegBounds(_leg(_london, _paris));
      expect(bounds.west, -0.1276);
      expect(bounds.east, 2.3522);
      expect(bounds.south, 48.8566);
      expect(bounds.north, 51.5072);
    });

    test('invirtiendo from/to — mismos bounds (orden irrelevante)', () {
      final bounds = activeLegBounds(_leg(_paris, _london));
      expect(bounds.west, -0.1276);
      expect(bounds.east, 2.3522);
      expect(bounds.south, 48.8566);
      expect(bounds.north, 51.5072);
    });

    test('cruza antimeridiano — span crudo > 180°', () {
      final bounds = activeLegBounds(_leg(_fukuoka, _vancouver));
      expect(bounds.west, -123.1207);
      expect(bounds.east, 130.4017);
      expect(bounds.east - bounds.west, greaterThan(180));
    });
  });

  group('fitActiveLeg', () {
    test('tramo normal — cámara encuadrada con zoom en [2, 18]', () {
      final fitted = fitActiveLeg(_camera(), _leg(_london, _paris));
      expect(fitted, isNotNull);
      expect(fitted!.zoom, greaterThanOrEqualTo(2.0));
      expect(fitted.zoom, lessThanOrEqualTo(18.0));
      // Centrado en el punto medio aproximado del tramo.
      expect(fitted.center.latitude, closeTo(50.18, 0.5));
      expect(fitted.center.longitude, closeTo(1.11, 0.5));
    });

    test('tramo que cruza antimeridiano en viewport estrecho — null', () {
      // 400 px a zoom 2 caben ~140°; el tramo ocupa ~253° crudos.
      final fitted = fitActiveLeg(
        _camera(size: const Size(400, 600)),
        _leg(_fukuoka, _vancouver),
      );
      expect(fitted, isNull);
    });

    test('tramo que cruza antimeridiano en viewport ancho — sí cabe', () {
      // 1600 px a zoom 2 caben ~562° > 253°.
      final fitted = fitActiveLeg(
        _camera(size: const Size(1600, 600)),
        _leg(_fukuoka, _vancouver),
      );
      expect(fitted, isNotNull);
      expect(fitted!.zoom, greaterThanOrEqualTo(2.0));
      expect(fitted.zoom, lessThanOrEqualTo(18.0));
    });

    test('tramo muy corto — el zoom queda recortado a 18', () {
      const near1 = FoggCity(name: 'A', lat: 0, lng: 0, order: 0);
      const near2 = FoggCity(name: 'B', lat: 0.001, lng: 0.001, order: 1);
      final fitted = fitActiveLeg(_camera(), _leg(near1, near2));
      expect(fitted, isNotNull);
      expect(fitted!.zoom, 18.0);
    });
  });
}
