import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../domain/entities/fogg_route.dart';
import '../../utils/app_colors.dart';
import '../providers/fogg_position_provider.dart';
import '../providers/sun_terminator_provider.dart';
import 'map_controls.dart';

/// Colores según spec.
const _foggRed = Color(0xFFC0392B);
const _labelColor = Color(0xFF1A1A1A);
const _offlineBg = Color(0xFFF5F0E8);
const _offlineTextColor = Color(0xFF6B6B6B);

/// Tile URL inyectado vía --dart-define, fallback OSM.
const _mapTileUrl = String.fromEnvironment(
  'MAP_TILE_URL',
  defaultValue: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
);

/// Límites mundiales — usados para contener la cámara sin salto antimeridiano.
final _worldBounds = LatLngBounds(
  const LatLng(-90, -180),
  const LatLng(90, 180),
);

/// Contención híbrida: intenta `contain` (bordes dentro del mundo) y si
/// el zoom es tan bajo que el mundo cabe entero en el viewport (`contain`
/// devuelve null), cae a `containCenter` que siempre sujeta el centro.
/// Así, por mucho que se arrastre horizontalmente, el mapa se detiene en
/// el borde en lugar de saltar al otro extremo del antimeridiano.
class _ContainWithFallback extends CameraConstraint {
  const _ContainWithFallback(this.bounds);
  final LatLngBounds bounds;

  @override
  MapCamera? constrain(MapCamera camera) {
    final contain = CameraConstraint.contain(bounds: bounds).constrain(camera);
    if (contain != null) return contain;
    return CameraConstraint.containCenter(bounds: bounds).constrain(camera);
  }

  @override
  bool operator ==(Object other) => other is _ContainWithFallback && other.bounds == bounds;

  @override
  int get hashCode => bounds.hashCode;

  @override
  String toString() => 'ContainWithFallback(bounds: $bounds) — wraps ContainCamera';
}

/// CRS Mercator sin repetición horizontal — mundo finito.
/// `Epsg3857` por defecto tiene `replicatesWorldLongitude==true` y envuelve
/// el mapa infinitamente (arrastrar más allá de 180 reaparece en -180).
/// Sobrescribiendo a `false`, el mapa se detiene en el antimeridiano y
/// muestra el `backgroundColor` más allá, sin salto.
@immutable
class Epsg3857NoRepeat extends Epsg3857 {
  const Epsg3857NoRepeat();
  @override
  bool get replicatesWorldLongitude => false;
}

/// Widget reutilizable de mapamundi Fogg — Mercator EPSG:3857 con OSM.
/// Acepta [route], [foggPosition] y constraints parametrizables.
class WorldMapWidget extends ConsumerStatefulWidget {
  const WorldMapWidget({
    super.key,
    this.route = mockFoggRoute,
    this.foggPosition,
    this.height,
    this.padding,
    this.initialZoom = 3.0,
  });

  /// Ruta a dibujar. Por defecto [mockFoggRoute].
  final FoggRoute route;

  /// Posición de Phoebe — si es null se usa fallback primera ciudad.
  /// Si se pasa explícitamente, tiene prioridad sobre provider.
  final LatLng? foggPosition;

  /// Altura fija opcional. Si es null y no hay constraints padre, usa 400.
  final double? height;

  /// Padding opcional alrededor del mapa.
  final EdgeInsets? padding;

  /// Zoom inicial si no hay provider.
  final double initialZoom;

  @override
  ConsumerState<WorldMapWidget> createState() => _WorldMapWidgetState();
}

class _WorldMapWidgetState extends ConsumerState<WorldMapWidget>
    with TickerProviderStateMixin {
  late final MapController _mapController;
  bool _tileError = false;

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
  }

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  /// Calcula labels visibles según colisión.
  /// Si zoom < 6 y distancia proyectada <40px, oculta mayor order.
  Set<int> _visibleLabelOrders(double zoom) {
    if (zoom >= 6) {
      return widget.route.cities.map((c) => c.order).toSet();
    }
    // Aproximación Mercator: distancia en px = delta * scale
    // scale = 256 * 2^zoom / 360  (grados lng -> px)
    final scale = 256 * (1 << zoom.toInt()) / 360.0;
    final visible = <int>{};
    for (final city in widget.route.cities) {
      bool collides = false;
      for (final otherOrder in visible) {
        final other = widget.route.cities.firstWhere((c) => c.order == otherOrder);
        // Factor lat para corrección coseno
        final avgLat = (city.lat + other.lat) / 2 * 3.14159 / 180;
        final cosLat = avgLat.abs() < 1.5 ? 1 : 0.5; // fallback simple
        // distancia aproximada
        final dx = (city.lng - other.lng).abs() * scale * cosLat;
        final dy = (city.lat - other.lat).abs() * scale;
        final dist = (dx * dx + dy * dy);
        // sqrt approximation: 40px threshold
        final distance = (dx * dx + dy * dy) > 0 ? _sqrt(dist) : 0;
        if (distance < 40) {
          collides = true;
          break;
        }
      }
      if (!collides) {
        visible.add(city.order);
      }
      // Si colisiona, no se añade → label oculto (mayor order)
    }
    return visible;
  }

  double _sqrt(double v) {
    // Newton simple — evita importar dart:math para mantener pureza
    if (v <= 0) return 0;
    double x = v / 2;
    for (var i = 0; i < 10; i++) {
      x = (x + v / x) / 2;
    }
    return x;
  }

  void _onZoomChanged(double newZoom) {
    ref.read(mapZoomProvider.notifier).state = newZoom;
    setState(() {});
  }

  /// Animación 600ms easeOut hacia [target].
  void _animateTo(LatLng target, double zoom) {
    final latTween = Tween<double>(
      begin: _mapController.camera.center.latitude,
      end: target.latitude,
    );
    final lngTween = Tween<double>(
      begin: _mapController.camera.center.longitude,
      end: target.longitude,
    );
    final zoomTween = Tween<double>(
      begin: _mapController.camera.zoom,
      end: zoom,
    );
    final controller = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    final curve = CurvedAnimation(parent: controller, curve: Curves.easeOut);
    controller.addListener(() {
      final lat = latTween.evaluate(curve);
      final lng = lngTween.evaluate(curve);
      final z = zoomTween.evaluate(curve);
      _mapController.move(LatLng(lat, lng), z);
    });
    controller.forward().whenComplete(() {
      controller.dispose();
      HapticFeedback.lightImpact();
    });
  }

  @override
  Widget build(BuildContext context) {
    final providerPos = ref.watch(foggPositionProvider);
    final effectiveFoggPos = widget.foggPosition ?? providerPos;
    final currentZoom = ref.watch(mapZoomProvider);
    final nightPolygons = ref.watch(sunTerminatorProvider);
    final center = effectiveFoggPos ??
        (widget.route.cities.isNotEmpty
            ? LatLng(widget.route.cities.first.lat, widget.route.cities.first.lng)
            : const LatLng(51.5072, -0.1276));

    final visibleOrders = _visibleLabelOrders(currentZoom);

    // Si TileLayer reporta error, mostrar overlay offline sin bloquear UI
    final mapContent = FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        crs: const Epsg3857NoRepeat(),
        initialCenter: center,
        initialZoom: widget.initialZoom,
        initialRotation: 0.0,
        interactionOptions: const InteractionOptions(
          flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
        ),
        cameraConstraint: _ContainWithFallback(_worldBounds),
        minZoom: 2.0,
        maxZoom: 18.0,
        backgroundColor: _offlineBg,
        onMapReady: () {
          // sincroniza zoom provider al iniciar
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              ref.read(mapZoomProvider.notifier).state = _mapController.camera.zoom;
            }
          });
        },
        onPositionChanged: (pos, hasGesture) {
          if (hasGesture) {
            _onZoomChanged(pos.zoom);
          }
        },
        // Crs por defecto es EPSG3857 Mercator — no necesita configuración.
      ),
      children: [
        TileLayer(
          urlTemplate: _mapTileUrl,
          fallbackUrl: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'eu.elarreglador.pf',
          maxZoom: 18,
          errorTileCallback: (tile, error, stack) {
            if (!_tileError && mounted) {
              setState(() => _tileError = true);
            }
          },
          // tileBuilder puede mostrar placeholder por tile, no necesario para spec
        ),
        // Capa día/noche — terminador solar curvo (spec 001) fix completo:
        // 1 polígono sinusoidal + clamp 85.05° o 2 rectángulos equinoccio split antimeridiano
        if (nightPolygons.isNotEmpty)
          PolygonLayer(
            polygons: nightPolygons
                .map(
                  (pts) => Polygon(
                    points: pts,
                    color: AppColors.nightOverlay,
                    borderColor: Colors.transparent,
                    borderStrokeWidth: 0,
                  ),
                )
                .toList(),
          ),
        PolylineLayer(
          polylines: widget.route.polylineSegments
              .map(
                (segment) => Polyline(
                  points: segment,
                  color: _foggRed.withValues(alpha: 0.95),
                  strokeWidth: 4.0,
                ),
              )
              .toList(),
          drawInSingleWorld: true,
        ),
        MarkerLayer(
          markers: widget.route.cities.map((city) {
            final showLabel = visibleOrders.contains(city.order);
            return Marker(
              point: LatLng(city.lat, city.lng),
              width: 80,
              height: 60,
              alignment: Alignment.center,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Punto rojo centrado exactamente en LatLng — la polyline pasa por aquí
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: _foggRed,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                  ),
                  // Label 22px por encima del punto (dy -22) + halo blanco 0.6
                  if (showLabel)
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.6),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            city.name,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: _labelColor,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            );
          }).toList(),
        ),
        // Marcador distintivo de Phoebe Fogg (sobre la ciudad actual) — aclara el centrado
        if (effectiveFoggPos != null)
          MarkerLayer(
            markers: [
              Marker(
                point: effectiveFoggPos,
                width: 28,
                height: 28,
                alignment: Alignment.center,
                child: Container(
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    border: Border.all(color: _foggRed, width: 3),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.2),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Center(
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: _foggRed,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        // Atribución con resguardo inferior para no quedar bajo ◻○△
        SafeArea(
          top: false,
          left: false,
          right: false,
          bottom: true,
          child: RichAttributionWidget(
            alignment: AttributionAlignment.bottomLeft,
            attributions: [
              TextSourceAttribution(
                '© OpenStreetMap contributors',
                onTap: () {},
              ),
            ],
          ),
        ),
      ],
    );

    // Stack con controles y overlay offline — agrupación vertical con SafeArea right+bottom
    final stack = Stack(
      children: [
        Positioned.fill(child: mapContent),
        if (_tileError)
          Positioned.fill(
            child: Container(
              color: _offlineBg,
              padding: const EdgeInsets.all(24),
              child: const Center(
                child: Text(
                  'No disponible',
                  style: TextStyle(fontSize: 14, color: _offlineTextColor),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
        // Controles agrupados verticalmente — 12 dp, sin solape, con resguardo ◻○△
        Positioned(
          right: 16,
          bottom: 16,
          child: SafeArea(
            top: false,
            left: false,
            right: true,
            bottom: true,
            child: MapControlsOverlay(
              mapController: _mapController,
              foggPosition: effectiveFoggPos,
              onAnimate: _animateTo,
              onZoomChanged: _onZoomChanged,
            ),
          ),
        ),
      ],
    );

    final padded = widget.padding != null
        ? Padding(padding: widget.padding!, child: stack)
        : stack;

    return LayoutBuilder(
      builder: (context, constraints) {
        final hasBoundedHeight = constraints.maxHeight.isFinite && constraints.maxHeight > 0;
        if (widget.height != null) {
          return SizedBox(height: widget.height, child: padded);
        }
        if (hasBoundedHeight) {
          return SizedBox.expand(child: padded);
        }
        // Fallback 400 como documentado
        return SizedBox(height: 400, child: padded);
      },
    );
  }
}
