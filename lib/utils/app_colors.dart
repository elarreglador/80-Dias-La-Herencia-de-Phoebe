import 'package:flutter/material.dart';

/// Design Tokens — colores desacoplados del dominio.
/// Estética minimalista intercambiable (futuro victoriano) per `AGENTS.md`.
class AppColors {
  const AppColors._();

  /// Overlay hemisferio nocturno — terminador solar.
  /// `#000511` con alpha 0.45, por debajo de ruta (`_foggRed`) y marcadores.
  /// Uso: `AppColors.nightOverlay` ya incluye alpha (exacto 0.45 vía withValues).
  static final nightOverlay = const Color(0xFF000511).withValues(alpha: 0.45);

  /// Valor const aproximado para contextos `const` (0x73 ≈ 0.451).
  static const nightOverlayConst = Color(0x73000511);

  // Tokens existentes migrados progresivamente (no romper spec actual):
  static const foggRed = Color(0xFFC0392B);
  static const labelColor = Color(0xFF1A1A1A);
  static const offlineBg = Color(0xFFF5F0E8);
  static const offlineTextColor = Color(0xFF6B6B6B);

  /// Tokens M3 — usados por FoggAppBar y FoggBottomNav.
  static const surface = Color(0xFFFEF7FF);
  static const surfaceVariant = Color(0xFFF3EDF7);

  // --- Paleta de rutas (SPEC 016) — mismos valores que el visor dev ---

  /// Barco.
  static const routeShip = Color(0xFF1E88E5);

  /// Coche.
  static const routeCar = Color(0xFFF9A825);

  /// Tren.
  static const routeTrain = Color(0xFF6A1B9A);

  /// Rutas candidatas — se usa con alpha 0.35.
  static const routeCandidate = Color(0xFF9E9E9E);
}
