import 'dart:async';
import 'dart:convert';
import "dart:io";

import 'package:flutter_test/flutter_test.dart';

import 'package:pf/services/weather_service.dart';

class _FakeHttpClientResponse implements HttpClientResponse {
  _FakeHttpClientResponse(this._body, this._status);
  final String _body;
  final int _status;

  @override
  int get statusCode => _status;

  @override
  StreamSubscription<List<int>> listen(void Function(List<int> event)? onData,
      {Function? onError, void Function()? onDone, bool? cancelOnError}) {
    return Stream<List<int>>.fromIterable([utf8.encode(_body)]).listen(onData,
        onError: onError, onDone: onDone, cancelOnError: cancelOnError);
  }

  @override
  Stream<S> transform<S>(StreamTransformer<List<int>, S> streamTransformer) {
    return streamTransformer.bind(this);
  }

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeHttpClientRequest implements HttpClientRequest {
  _FakeHttpClientRequest(this._response);
  final HttpClientResponse _response;

  @override
  Future<HttpClientResponse> close() async => _response;

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeHttpClient implements HttpClient {
  _FakeHttpClient(this._response);
  final HttpClientResponse _response;

  @override
  Future<HttpClientRequest> getUrl(Uri url) async =>
      _FakeHttpClientRequest(_response);

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('parsea respuesta Open-Meteo', () async {
    final body = jsonEncode({
      'hourly': {
        'time': ['2026-01-01T12:00', '2026-01-01T13:00'],
        'temperature_2m': [5.0, 6.0],
        'wind_speed_10m': [10.0, 20.0],
        'wind_direction_10m': [90.0, 180.0],
        'wind_gusts_10m': [15.0, 25.0],
        'visibility': [5000.0, 4000.0],
        'precipitation': [1.0, 2.0],
        'snowfall': [0.1, 0.2],
        'snow_depth': [0.01, 0.02],
        'weather_code': [0, 95],
      },
    });
    final resp = _FakeHttpClientResponse(body, 200);
    final client = _FakeHttpClient(resp);
    final service = WeatherService(client: client);
    final snap = await service.fetch(0, 0, DateTime.utc(2026, 1, 1, 12, 0));
    expect(snap.temperatureC, 5.0);
    expect(snap.windSpeedKmh, 10.0);
    expect(snap.weatherCode, 0);
  });

  test('fallback neutro si falla', () async {
    // Simulamos una respuesta con error HTTP 500 para forzar el fallo tras los reintentos
    final resp = _FakeHttpClientResponse('', 500);
    final client = _FakeHttpClient(resp);
    final service = WeatherService(client: client);

    // Ejecutamos la petición con coordenadas y fecha de prueba
    final snap = await service.fetch(0, 0, DateTime.utc(2026, 1, 1, 12, 0));

    // Verificamos que al fallar devuelva el snapshot neutro esperado
    expect(snap.timestampUtc, DateTime.utc(2026, 1, 1, 12, 0));
    expect(snap.temperatureC, isNull); // El snapshot neutro inicializa temperatureC como null
  }, timeout: const Timeout(Duration(seconds: 2))); // Evita bloqueos largos si reintenta con delays
}
