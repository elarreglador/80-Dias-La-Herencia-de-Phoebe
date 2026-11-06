import 'dart:math';

import 'package:flutter/material.dart';

import 'fatigue.dart';

enum RoadRestType {
  hotel,
  hostel,
  serviceArea,
  gasStation;

  String get label => switch (this) {
        RoadRestType.hotel => 'Hotel de carretera',
        RoadRestType.hostel => 'Hostel de carretera',
        RoadRestType.serviceArea => 'Área de servicio',
        RoadRestType.gasStation => 'Gasolinera',
      };

  double get recoveryRate => switch (this) {
        RoadRestType.hotel => Fatigue.hotelRecoverRate,
        RoadRestType.hostel => Fatigue.hotelRecoverRate,
        RoadRestType.serviceArea => Fatigue.carRestRecoverRate,
        RoadRestType.gasStation => Fatigue.carRestRecoverRate,
      };

  bool get isPaid => this == RoadRestType.hotel || this == RoadRestType.hostel;

  IconData get icon => switch (this) {
        RoadRestType.hotel => Icons.hotel,
        RoadRestType.hostel => Icons.bed,
        RoadRestType.serviceArea => Icons.local_parking,
        RoadRestType.gasStation => Icons.local_gas_station,
      };

  static RoadRestType roll({Random? random}) {
    final r = (random ?? Random()).nextInt(100);
    if (r < 20) return RoadRestType.hotel;
    if (r < 50) return RoadRestType.hostel;
    if (r < 65) return RoadRestType.serviceArea;
    return RoadRestType.gasStation;
  }
}
