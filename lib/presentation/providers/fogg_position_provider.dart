import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

/// Posición actual de Phoebe Fogg — leída por el botón centrar.
/// Inicialmente Londres (order 0). Futuro: StreamProvider conectado a PositionService.
final foggPositionProvider = StateProvider<LatLng?>((ref) => const LatLng(51.5072, -0.1276));

/// Zoom actual del mapa — sincronizado con MapController.
final mapZoomProvider = StateProvider<double>((ref) => 3.0);
