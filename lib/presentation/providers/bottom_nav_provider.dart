import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Índice seleccionado de la botonera inferior. 0 = Mapa.
final bottomNavIndexProvider = StateProvider<int>((ref) => 0);

/// Destinos constantes — orden fijo, usado por FoggBottomNav y MainScaffold.
/// 5 pestañas: Mapa | Diario | Fogg (central dinámico) | Presupuesto | Ruta
/// El central (índice 2) cambia icono según FoggStatus (viajando vs en destino).
const bottomNavDestinations = [
  (
    label: 'Mapa',
    iconOutlined: Icons.map_outlined,
    iconFilled: Icons.map,
  ),
  (
    label: 'Diario',
    iconOutlined: Icons.menu_book_outlined,
    iconFilled: Icons.menu_book,
  ),
  (
    label: 'Fogg',
    iconOutlined: Icons.location_on_outlined,
    iconFilled: Icons.location_on,
  ),
  (
    label: 'Presupuesto',
    iconOutlined: Icons.account_balance_wallet_outlined,
    iconFilled: Icons.account_balance_wallet,
  ),
  (
    label: 'Ruta',
    iconOutlined: Icons.route_outlined,
    iconFilled: Icons.route,
  ),
];
