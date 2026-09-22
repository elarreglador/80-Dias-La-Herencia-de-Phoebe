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
}
