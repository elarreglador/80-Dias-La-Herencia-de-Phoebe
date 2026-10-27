import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../domain/entities/fogg_status.dart';
import '../../utils/app_colors.dart';
import '../providers/fogg_position_provider.dart';
import '../providers/game_notifier.dart';
import '../providers/map_focus_provider.dart';
import '../providers/route_catalog_provider.dart';
import '../providers/sun_terminator_provider.dart';
import 'map_controls.dart';
import 'map_crs.dart';
import 'map_route_layer.dart';

export 'map_crs.dart';

/// Colores según spec.
const _offlineBg = Color(0xFFF5F0E8);
const _offlineTextColor = Color(0xFF6B6B6B);

/// Tile URL inyectado vía --dart-define, fallback OSM.
const _mapTileUrl = String.fromEnvironment(
  'MAP_TILE_URL',
  defaultValue: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
);

/// Widget reutilizable de mapamundi Fogg — Mercator EPSG:3857 con OSM.
///
/// Dibuja el trayecto real de Phoebe: el tramo activo (lo recorrido sólido,
/// lo pendiente discontinuo, ambos en el color del modo), el historial de
/// tramos ya recorridos y —solo cuando Phoebe está en una ciudad y aún no
/// ha elegido trayecto— las rutas candidatas en gris.
class WorldMapWidget extends ConsumerStatefulWidget {
  const WorldMapWidget({
    super.key,
    this.foggPosition,
    this.height,
    this.padding,
    this.initialZoom = 3.0,
  });

  /// Posición de Phoebe — si es null se usa la posición derivada de la partida.
  /// Si se pasa explícitamente, tiene prioridad sobre el provider.
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

  /// Callbacks estables — `MapOptions` compara por identidad los callbacks,
  /// así que recrearlos en cada build invalidaría las opciones del mapa
  /// (y con ellas la cámara).
  late final void Function() _onMapReadyCallback;
  late final void Function(MapCamera camera, bool hasGesture)
      _onPositionChangedCallback;

  /// El mapa **no** sigue a Phoebe (decisión de la SPEC 016); de eso se
  /// encarga el botón «Centrar en Phoebe».

  bool _tileError = false;
  bool _mapReady = false;
  MapFocusRequest? _pendingFocus;

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    _onMapReadyCallback = _handleMapReady;
    _onPositionChangedCallback = _handlePositionChanged;
  }

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  void _onZoomChanged(double newZoom) {
    ref.read(mapZoomProvider.notifier).state = newZoom;
    setState(() {});
  }

  /// El mapa ya está listo — sincroniza el zoom y aplica el foco pendiente.
  void _handleMapReady() {
    _mapReady = true;
    // sincroniza zoom provider al iniciar
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(mapZoomProvider.notifier).state = _mapController.camera.zoom;
      // Procesa foco pendiente (chincheta pulsada antes de que el mapa estuviera listo)
      if (_pendingFocus != null) {
        final req = _pendingFocus!;
        _pendingFocus = null;
        // PostFrame para asegurar que controller esté estable
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _animateTo(LatLng(req.city.lat, req.city.lng), req.zoom);
        });
      }
    });
  }

  void _handlePositionChanged(MapCamera camera, bool hasGesture) {
    if (hasGesture) {
      _onZoomChanged(camera.zoom);
    }
  }

  void _handleMapFocus(MapFocusRequest req) {
    final target = LatLng(req.city.lat, req.city.lng);
    if (!_mapReady) {
      _pendingFocus = req;
      return;
    }
    _animateTo(target, req.zoom);
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
      // Sincroniza zoom provider también en animaciones programáticas
      if (mounted) ref.read(mapZoomProvider.notifier).state = zoom;
      HapticFeedback.lightImpact();
    });
  }

  @override
  Widget build(BuildContext context) {
    // Escucha peticiones de foco desde la pantalla de Fogg (chincheta → mapa).
    // Se registra en cada build; Riverpod gestiona la suscripción.
    ref.listen<MapFocusRequest?>(mapFocusProvider, (prev, next) {
      if (next != null) _handleMapFocus(next);
    });

    final status = ref.watch(gameNotifierProvider);
    final activeLeg = status is FoggTraveling ? status.leg : null;
    final now = ref.watch(timeEngineProvider).now();
    final providerPos = ref.watch(foggPositionProvider);
    final effectiveFoggPos = widget.foggPosition ?? providerPos;
    final nightPolygons = ref.watch(sunTerminatorProvider);
    final cityCatalog = ref.watch(cityCatalogProvider).valueOrNull;
    final polylines = buildRoutePolylines(
      status: status,
      now: now,
      completedLegs: ref.read(gameSessionProvider).completedLegs,
    );
    final legMarkers = buildLegMarkers(status: status, catalog: cityCatalog);

    // Si TileLayer reporta error, mostrar overlay offline sin bloquear UI
    final mapContent = FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        crs: const Epsg3857NoRepeat(),
        initialCenter: worldCenter,
        initialZoom: widget.initialZoom,
        initialRotation: 0.0,
        interactionOptions: const InteractionOptions(
          flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
        ),
        cameraConstraint: ContainWithFallback(worldBounds),
        minZoom: 2.0,
        maxZoom: 18.0,
        backgroundColor: _offlineBg,
        onMapReady: _onMapReadyCallback,
        onPositionChanged: _onPositionChangedCallback,
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
          polylines: polylines,
          drawInSingleWorld: true,
        ),
        MarkerLayer(markers: legMarkers),
        // Marcador distintivo de Phoebe Fogg (sobre la ciudad actual) — aclara el centrado
        if (effectiveFoggPos != null)
          MarkerLayer(
            markers: [
              Marker(
                point: effectiveFoggPos,
                width: 14,
                height: 28,
                alignment: Alignment.center,
                child: Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.foggRed, width: 1.5),
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
                      width: 4,
                      height: 4,
                      decoration: const BoxDecoration(
                        color: AppColors.foggRed,
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
              activeLeg: activeLeg,
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