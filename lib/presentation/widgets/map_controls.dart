import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../providers/fogg_position_provider.dart';

/// Botones + / − sobre MapController — clamp 2..18 con haptics.
class ZoomControls extends ConsumerWidget {
  const ZoomControls({
    super.key,
    required this.mapController,
    required this.onZoomChanged,
  });

  final MapController mapController;
  final ValueChanged<double> onZoomChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentZoom = ref.watch(mapZoomProvider);
    final canZoomIn = currentZoom < 18.0;
    final canZoomOut = currentZoom > 2.0;

    return Positioned(
      right: 16,
      bottom: 96,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ControlButton(
            icon: Icons.add,
            onPressed: canZoomIn
                ? () {
                    final newZoom = (currentZoom + 1).clamp(2.0, 18.0);
                    mapController.move(mapController.camera.center, newZoom);
                    onZoomChanged(newZoom);
                    HapticFeedback.lightImpact();
                  }
                : null,
          ),
          const SizedBox(height: 8),
          _ControlButton(
            icon: Icons.remove,
            onPressed: canZoomOut
                ? () {
                    final newZoom = (currentZoom - 1).clamp(2.0, 18.0);
                    mapController.move(mapController.camera.center, newZoom);
                    onZoomChanged(newZoom);
                    HapticFeedback.lightImpact();
                  }
                : null,
          ),
        ],
      ),
    );
  }
}

/// Botón centrar Phoebe — anima 600ms easeOut a foggPosition.
class CenterFoggButton extends StatelessWidget {
  const CenterFoggButton({
    super.key,
    required this.mapController,
    required this.foggPosition,
    required this.onAnimate,
  });

  final MapController mapController;
  final LatLng? foggPosition;
  final void Function(LatLng target, double zoom) onAnimate;

  @override
  Widget build(BuildContext context) {
    final isDisabled = foggPosition == null;
    return Positioned(
      right: 16,
      bottom: 32,
      child: Tooltip(
        message: isDisabled ? 'Posición no disponible' : 'Centrar en Phoebe',
        child: _ControlButton(
          icon: Icons.my_location,
          backgroundColor: const Color(0xFFC0392B),
          foregroundColor: Colors.white,
          iconSize: 24,
          onPressed: isDisabled
              ? null
              : () {
                  final currentZoom = mapController.camera.zoom;
                  onAnimate(foggPosition!, currentZoom);
                },
        ),
      ),
    );
  }
}

/// Abre vista actual en OSM externa sin confirmación.
class OpenInOsmButton extends StatelessWidget {
  const OpenInOsmButton({super.key, required this.mapController});

  final MapController mapController;

  Future<void> _openOsm() async {
    final center = mapController.camera.center;
    final zoom = mapController.camera.zoom;
    // Redondea a 5 decimales según spec
    final lat = center.latitude.toStringAsFixed(5);
    final lng = center.longitude.toStringAsFixed(5);
    final z = zoom.toStringAsFixed(0);
    final uri = Uri.parse('https://www.openstreetmap.org/#map=$z/$lat/$lng');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      right: 16,
      bottom: 160,
      child: _ControlButton(
        icon: Icons.open_in_new,
        onPressed: _openOsm,
      ),
    );
  }
}

/// Botón base 48x48 rounded 12 bg white shadow 0 4 12 rgba(0,0,0,0.15)
class _ControlButton extends StatelessWidget {
  const _ControlButton({
    required this.icon,
    this.onPressed,
    this.backgroundColor = Colors.white,
    this.foregroundColor = Colors.black87,
    this.iconSize = 24,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final Color backgroundColor;
  final Color foregroundColor;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final isDisabled = onPressed == null;
    return Material(
      color: isDisabled ? Colors.grey.shade300 : backgroundColor,
      borderRadius: BorderRadius.circular(12),
      elevation: 4,
      shadowColor: Colors.black.withValues(alpha: 0.15),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          width: 48,
          height: 48,
          child: Icon(
            icon,
            size: iconSize,
            color: isDisabled ? Colors.grey : foregroundColor,
          ),
        ),
      ),
    );
  }
}
