import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../domain/entities/fogg_leg.dart';
import '../providers/fogg_position_provider.dart';
import 'active_leg_fit.dart';

/// Columna + / − sin Positioned — usada dentro de MapControlsOverlay.
/// Mantiene clamp 2..18 con haptics y separación 12 dp.
class ZoomControlsColumn extends ConsumerWidget {
  const ZoomControlsColumn({
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

    return Column(
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
        const SizedBox(height: 12),
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
    );
  }
}

/// Wrapper legacy con Positioned — mantiene compatibilidad si se usa aislado.
/// Para la agrupación vertical use ZoomControlsColumn dentro de MapControlsOverlay.
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
    return Positioned(
      right: 16,
      bottom: 96,
      child: ZoomControlsColumn(
        mapController: mapController,
        onZoomChanged: onZoomChanged,
      ),
    );
  }
}

/// Botón centrar Phoebe sin Positioned — para agrupación vertical.
///
/// Con un trayecto en curso ([activeLeg] no nulo) encuadra el origen y el
/// destino del tramo; si no caben en pantalla (cruza el antimeridiano en un
/// viewport estrecho) cae al origen del tramo. Sin trayecto, centra en
/// Phoebe manteniendo el zoom actual.
class CenterFoggButtonCompact extends StatelessWidget {
  const CenterFoggButtonCompact({
    super.key,
    required this.mapController,
    required this.foggPosition,
    required this.onAnimate,
    this.activeLeg,
  });

  final MapController mapController;
  final LatLng? foggPosition;
  final void Function(LatLng target, double zoom) onAnimate;

  /// Tramo en curso — `null` si no hay trayecto en marcha.
  final FoggLeg? activeLeg;

  /// Padding del encuadre: los controles ocupan derecha + abajo.
  static const _fitPadding = EdgeInsets.fromLTRB(48, 48, 96, 96);

  void _snack(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _handlePressed(BuildContext context) {
    final leg = activeLeg;
    HapticFeedback.lightImpact();

    if (leg == null) {
      _snack(
        context,
        'Centrando en Phoebe — ${foggPosition!.latitude.toStringAsFixed(2)}, '
        '${foggPosition!.longitude.toStringAsFixed(2)} (la línea roja va hasta Tokio)',
      );
      onAnimate(foggPosition!, mapController.camera.zoom);
      return;
    }

    final fitted = fitActiveLeg(
      mapController.camera,
      leg,
      padding: _fitPadding,
    );
    if (fitted == null) {
      // No cabe a zoom >= 2 (tramo que cruza el antimeridiano) — fallback.
      _snack(
        context,
        'Trayecto no cabe en pantalla — centrando en el origen (${leg.from.name})',
      );
      onAnimate(LatLng(leg.from.lat, leg.from.lng), mapController.camera.zoom);
      return;
    }

    _snack(context, 'Encuadrando trayecto: ${leg.from.name} → ${leg.to.name}');
    onAnimate(fitted.center, fitted.zoom);
  }

  @override
  Widget build(BuildContext context) {
    final isDisabled = foggPosition == null;
    final message = isDisabled
        ? 'Posición no disponible'
        : activeLeg != null
            ? 'Encuadrar trayecto'
            : 'Centrar en Phoebe';
    return Tooltip(
      message: message,
      child: _ControlButton(
        icon: Icons.my_location,
        backgroundColor: const Color(0xFFC0392B),
        foregroundColor: Colors.white,
        iconSize: 24,
        onPressed: isDisabled ? null : () => _handlePressed(context),
      ),
    );
  }
}

/// Wrapper legacy con Positioned — mantiene compatibilidad.
class CenterFoggButton extends StatelessWidget {
  const CenterFoggButton({
    super.key,
    required this.mapController,
    required this.foggPosition,
    required this.onAnimate,
    this.activeLeg,
  });

  final MapController mapController;
  final LatLng? foggPosition;
  final void Function(LatLng target, double zoom) onAnimate;
  final FoggLeg? activeLeg;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      right: 16,
      bottom: 32,
      child: CenterFoggButtonCompact(
        mapController: mapController,
        foggPosition: foggPosition,
        onAnimate: onAnimate,
        activeLeg: activeLeg,
      ),
    );
  }
}

/// Botón OSM sin Positioned — para agrupación vertical.
class OpenInOsmButtonCompact extends StatelessWidget {
  const OpenInOsmButtonCompact({super.key, required this.mapController});

  final MapController mapController;

  Future<void> _openOsm() async {
    final center = mapController.camera.center;
    final zoom = mapController.camera.zoom;
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
    return _ControlButton(
      icon: Icons.open_in_new,
      onPressed: _openOsm,
    );
  }
}

/// Wrapper legacy con Positioned — mantiene compatibilidad.
class OpenInOsmButton extends StatelessWidget {
  const OpenInOsmButton({super.key, required this.mapController});

  final MapController mapController;

  Future<void> _openOsm() async {
    final center = mapController.camera.center;
    final zoom = mapController.camera.zoom;
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

/// Agrupación vertical — 4 botones con 12 dp, sin solape y con SafeArea externa.
/// Orden bottom→top visual dentro de Column: OSM arriba, Zoom medio, Center abajo.
/// El [SafeArea] se aplica en WorldMapWidget (right+bottom) para respetar ◻○△.
class MapControlsOverlay extends StatelessWidget {
  const MapControlsOverlay({
    super.key,
    required this.mapController,
    required this.foggPosition,
    required this.onAnimate,
    required this.onZoomChanged,
    this.activeLeg,
  });

  final MapController mapController;
  final LatLng? foggPosition;
  final void Function(LatLng target, double zoom) onAnimate;
  final ValueChanged<double> onZoomChanged;
  final FoggLeg? activeLeg;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        OpenInOsmButtonCompact(mapController: mapController),
        const SizedBox(height: 12),
        ZoomControlsColumn(
          mapController: mapController,
          onZoomChanged: onZoomChanged,
        ),
        const SizedBox(height: 12),
        CenterFoggButtonCompact(
          mapController: mapController,
          foggPosition: foggPosition,
          onAnimate: onAnimate,
          activeLeg: activeLeg,
        ),
      ],
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
