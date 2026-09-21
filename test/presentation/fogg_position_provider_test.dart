import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:pf/presentation/providers/fogg_position_provider.dart';

void main() {
  test('foggPositionProvider inicia en Londres', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final pos = container.read(foggPositionProvider);
    expect(pos, isNotNull);
    expect(pos!.latitude, 51.5072);
    expect(pos.longitude, -0.1276);
  });

  test('mapZoomProvider inicia en 3.0', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(container.read(mapZoomProvider), 3.0);
  });

  test('providers permiten actualizar foggPosition', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    const tokio = LatLng(35.6762, 139.6503);
    container.read(foggPositionProvider.notifier).state = tokio;
    expect(container.read(foggPositionProvider), tokio);
  });
}
