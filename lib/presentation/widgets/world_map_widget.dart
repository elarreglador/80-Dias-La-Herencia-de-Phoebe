import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../domain/entities/fogg_city.dart';
import '../../domain/entities/fogg_status.dart';
import '../../domain/entities/transport_mode.dart';
import '../../domain/models/route_path.dart';
import '../../services/city_catalog.dart';
import '../../utils/app_colors.dart';
import '../providers/fogg_position_provider.dart';
import '../providers/game_notifier.dart';
import '../providers/map_focus_provider.dart';
import '../providers/route_catalog_provider.dart';
import '../providers/sun_terminator_provider.dart';
import 'map_controls.dart';

/// Colores según spec.
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

  /// Centro inicial del mapa — el centro del mundo (primo meridiano).
  ///
  /// Es el único centro que siempre satisface la constraint de contención
  /// a cualquier zoom: con el viewport más ancho que el mundo, `contain`
  /// devuelve `null` y entra el `containCenter` de reserva.
  ///
  /// El mapa **no** sigue a Phoebe (decisión de la SPEC 016); de eso se
  /// encarga el botón «Centrar en Phoebe».
  static const LatLng _worldCenter = LatLng(0, 0);

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

  /// Color del trazado según el modo de transporte.
  static Color _routeColor(TransportMode mode) => switch (mode) {
        TransportMode.ship => AppColors.routeShip,
        TransportMode.train => AppColors.routeTrain,
        TransportMode.car => AppColors.routeCar,
        TransportMode.foot => AppColors.routeFoot,
        _ => AppColors.routeFoot,
      };

  /// Polilíneas del mapa — historial, tramo activo y candidatas.
  List<Polyline> _buildPolylines(FoggStatus status, DateTime now) {
    final polylines = <Polyline>[];

    // Historial — cada tramo ya recorrido en el color de su modo, 2 px.
    for (final leg in ref.read(gameSessionProvider).completedLegs) {
      final path = leg.path;
      if (path == null) continue;
      final color = _routeColor(leg.transport);
      for (final segment in path.renderSegments()) {
        polylines.add(Polyline(
          points: segment,
          color: color,
          strokeWidth: 2.0,
        ));
      }
    }

    switch (status) {
      case FoggTraveling(leg: final leg):
        final path = leg.path;
        if (path == null) break;
        final color = _routeColor(leg.transport);
        final parts = path.splitAt(leg.progressAt(now));
        // Parte recorrida — sólida, 4 px.
        for (final segment in RoutePath.splitAtAntimeridian(parts.traveled)) {
          polylines.add(Polyline(
            points: segment,
            color: color,
            strokeWidth: 4.0,
          ));
        }
        // Parte pendiente — discontinua, 4 px.
        for (final segment in RoutePath.splitAtAntimeridian(parts.pending)) {
          polylines.add(Polyline(
            points: segment,
            color: color,
            strokeWidth: 4.0,
            pattern: StrokePattern.dashed(segments: const [12, 8]),
          ));
        }
      case FoggArrived(options: final options):
        // Candidatas — solo en ciudad y sin trayecto elegido.
        for (final option in options) {
          for (final vehicle in option.vehicles) {
            final route = vehicle.route;
            if (route == null) continue;
            final path = RoutePath.fromGeometry(route.geometry);
            if (path == null) continue;
            for (final segment in path.renderSegments()) {
              polylines.add(Polyline(
                points: segment,
                color: AppColors.routeCandidate.withValues(alpha: 0.35),
                strokeWidth: 2.0,
              ));
            }
          }
        }
    }

    return polylines;
  }

  /// Marcadores del tramo activo — origen y destino.
  List<Marker> _buildLegMarkers(FoggStatus status, CityCatalog? catalog) {
    switch (status) {
      case FoggTraveling(leg: final leg):
        return [
          _cityMarker(_canonical(leg.from, catalog)),
          _cityMarker(_canonical(leg.to, catalog)),
        ];
      case FoggArrived():
        return const [];
    }
  }

  /// Ciudad canónica del catálogo — las coordenadas reales del city catalog
  /// mandan sobre las de la partida, para que el marcador caiga exacto
  /// sobre el vértice de la ruta.
  static FoggCity _canonical(FoggCity city, CityCatalog? catalog) =>
      catalog?.byName(city.name) ?? city;

  /// Marcador de ciudad — punto rojo con etiqueta.
  Marker _cityMarker(FoggCity city) {
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
              color: AppColors.foggRed,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
            ),
          ),
          // Label 22px por encima del punto (dy -22) + halo blanco 0.6
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
  }

  @override
  Widget build(BuildContext context) {
    // Escucha peticiones de foco desde la pantalla de Fogg (chincheta → mapa).
    // Se registra en cada build; Riverpod gestiona la suscripción.
    ref.listen<MapFocusRequest?>(mapFocusProvider, (prev, next) {
      if (next != null) _handleMapFocus(next);
    });

    final status = ref.watch(gameNotifierProvider);
    final now = ref.watch(timeEngineProvider).now();
    final providerPos = ref.watch(foggPositionProvider);
    final effectiveFoggPos = widget.foggPosition ?? providerPos;
    final nightPolygons = ref.watch(sunTerminatorProvider);
    final cityCatalog = ref.watch(cityCatalogProvider).valueOrNull;
    final polylines = _buildPolylines(status, now);
    final legMarkers = _buildLegMarkers(status, cityCatalog);

    // Si TileLayer reporta error, mostrar overlay offline sin bloquear UI
    final mapContent = FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        crs: const Epsg3857NoRepeat(),
        initialCenter: _worldCenter,
        initialZoom: widget.initialZoom,
        initialRotation: 0.0,
        interactionOptions: const InteractionOptions(
          flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
        ),
        cameraConstraint: _ContainWithFallback(_worldBounds),
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
                width: 28,
                height: 28,
                alignment: Alignment.center,
                child: Container(
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.foggRed, width: 3),
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