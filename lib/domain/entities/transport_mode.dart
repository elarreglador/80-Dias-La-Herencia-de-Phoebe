import 'package:flutter/material.dart';

/// Modos de transporte Fogg — lista cerrada, sin avión (invariante).
/// Estética ficticia por ahora; precios y duraciones mock.
enum TransportMode {
  train,
  ship,
  car,
  balloon,
  horse,
  camel,
  foot,
  motorcycle;

  /// Etiqueta humana en castellano (narrativa).
  String get label {
    switch (this) {
      case TransportMode.train:
        return 'Tren';
      case TransportMode.ship:
        return 'Barco';
      case TransportMode.car:
        return 'Coche';
      case TransportMode.balloon:
        return 'Globo';
      case TransportMode.horse:
        return 'Caballo';
      case TransportMode.camel:
        return 'Camello';
      case TransportMode.foot:
        return 'A pie';
      case TransportMode.motorcycle:
        return 'Moto';
    }
  }

  /// Icono Material asociado — sin avión.
  IconData get icon {
    switch (this) {
      case TransportMode.train:
        return Icons.train;
      case TransportMode.ship:
        return Icons.directions_boat;
      case TransportMode.car:
        return Icons.directions_car;
      case TransportMode.balloon:
        return Icons.air; // globo — Material no tiene hot_air_balloon estable
      case TransportMode.horse:
        return Icons.pets; // caballo genérico
      case TransportMode.camel:
        return Icons.pets; // camello — fallback pets (distinguible por label)
      case TransportMode.foot:
        return Icons.directions_walk;
      case TransportMode.motorcycle:
        return Icons.two_wheeler;
    }
  }

  /// Icono outlined para estados no seleccionados (si existe).
  IconData get iconOutlined {
    switch (this) {
      case TransportMode.train:
        return Icons.train_outlined;
      case TransportMode.ship:
        return Icons.directions_boat_outlined;
      case TransportMode.car:
        return Icons.directions_car_outlined;
      case TransportMode.balloon:
        return Icons.air_outlined;
      case TransportMode.horse:
        return Icons.pets_outlined;
      case TransportMode.camel:
        return Icons.pets_outlined;
      case TransportMode.foot:
        return Icons.directions_walk_outlined;
      case TransportMode.motorcycle:
        return Icons.two_wheeler_outlined;
    }
  }
}
