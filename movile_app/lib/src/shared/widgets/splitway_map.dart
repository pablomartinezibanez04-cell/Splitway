import 'package:flutter/material.dart' hide Image;
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mbx;
import 'package:splitway_core/splitway_core.dart';
import 'package:splitway_mobile/l10n/app_localizations.dart';

import '../../features/editor/draft_segment.dart';
import 'route_map_painter.dart';
import 'sector_segments.dart';

/// Wraps a real Mapbox `MapWidget` when [useMapbox] is true; otherwise falls
/// back to the iter 1 `RouteMapPainter`. The fallback keeps widget tests
/// working (no Mapbox SDK in test env) and lets the app boot without a
/// token configured.
///
/// Tap/long-press are reported with a [GeoPoint] in WGS84 (lat/lng).
class SplitwayMap extends StatefulWidget {
  const SplitwayMap({
    super.key,
    required this.useMapbox,
    this.route,
    this.telemetry = const [],
    this.draftPath = const [],
    this.draftWaypoints = const [],
    this.draftSectorPoints = const [],
    this.highlightSectorId,
    this.showSectors = false,
    this.userLocation,
    this.initialCenter,
    this.flyToNotifier,
    this.onTap,
    this.onLongPress,
    this.styleUri,
    this.interactive = true,
    this.freehandMode = false,
    this.draftSegments = const [],
    this.onFreehandStart,
    this.onFreehandPoint,
    this.onFreehandEnd,
  });

  final bool useMapbox;
  final RouteTemplate? route;
  final List<TelemetryPoint> telemetry;
  /// Road-snapped polyline shown during drawing (may have thousands of points).
  final List<GeoPoint> draftPath;
  /// User-tapped waypoints shown as circles during drawing (typically < 25).
  final List<GeoPoint> draftWaypoints;
  /// Snapped path vertices marking sector boundaries (shown as circles while drawing).
  final List<GeoPoint> draftSectorPoints;
  final String? highlightSectorId;
  /// When true, the saved route is drawn in per-sector colors instead of solid blue.
  final bool showSectors;
  /// Current user position shown as a blue dot on the map.
  final GeoPoint? userLocation;
  /// Initial camera center (e.g. user GPS location). Falls back to Madrid if null.
  final GeoPoint? initialCenter;
  /// When this notifier fires, the map flies to the given point.
  final ValueNotifier<GeoPoint?>? flyToNotifier;
  final ValueChanged<GeoPoint>? onTap;
  final ValueChanged<GeoPoint>? onLongPress;
  final String? styleUri;
  final bool interactive;
  final bool freehandMode;
  final List<DraftSegment> draftSegments;
  final VoidCallback? onFreehandStart;
  final ValueChanged<GeoPoint>? onFreehandPoint;
  final VoidCallback? onFreehandEnd;

  @override
  State<SplitwayMap> createState() => _SplitwayMapState();
}

class _SplitwayMapState extends State<SplitwayMap> {
  mbx.MapboxMap? _map;
  mbx.PolylineAnnotationManager? _lineManager;
  mbx.CircleAnnotationManager? _circleManager;
  final _activePointers = <int>{};
  bool _isFreehandStrokeActive = false;

  @override
  void initState() {
    super.initState();
    widget.flyToNotifier?.addListener(_onFlyToChanged);
  }

  @override
  void dispose() {
    widget.flyToNotifier?.removeListener(_onFlyToChanged);
    final map = _map;
    if (map != null) {
      map.removeInteraction('splitway-tap');
      map.removeInteraction('splitway-long-tap');
    }
    super.dispose();
  }

  void _onFlyToChanged() {
    final target = widget.flyToNotifier?.value;
    if (target == null || _map == null) return;
    _map!.flyTo(
      mbx.CameraOptions(
        center: mbx.Point(
          coordinates: mbx.Position(target.longitude, target.latitude),
        ),
        zoom: 15,
      ),
      mbx.MapAnimationOptions(duration: 800),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.useMapbox) {
      return _buildPainterFallback();
    }
    final mapWidget = mbx.MapWidget(
      key: const ValueKey('splitway-mapbox'),
      styleUri: widget.styleUri ?? mbx.MapboxStyles.OUTDOORS,
      onMapCreated: _onMapCreated,
    );

    return Stack(
      children: [
        mapWidget,
        if (widget.freehandMode)
          Positioned.fill(
            child: Listener(
              behavior: HitTestBehavior.translucent,
              onPointerDown: _onPointerDown,
              onPointerMove: _onPointerMove,
              onPointerUp: _onPointerUp,
              onPointerCancel: _onPointerCancel,
            ),
          ),
      ],
    );
  }

  @override
  void didUpdateWidget(covariant SplitwayMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.flyToNotifier != widget.flyToNotifier) {
      oldWidget.flyToNotifier?.removeListener(_onFlyToChanged);
      widget.flyToNotifier?.addListener(_onFlyToChanged);
    }
    if (!widget.useMapbox) return;

    if (oldWidget.freehandMode != widget.freehandMode) {
      _updateGesturesForFreehand();
    }

    final routeChanged = oldWidget.route != widget.route;
    final annotationsChanged = routeChanged ||
        oldWidget.telemetry.length != widget.telemetry.length ||
        oldWidget.userLocation != widget.userLocation ||
        oldWidget.draftPath.length != widget.draftPath.length ||
        oldWidget.draftWaypoints.length != widget.draftWaypoints.length ||
        oldWidget.draftSectorPoints.length != widget.draftSectorPoints.length ||
        oldWidget.highlightSectorId != widget.highlightSectorId ||
        oldWidget.showSectors != widget.showSectors ||
        oldWidget.draftSegments.length != widget.draftSegments.length ||
        oldWidget.freehandMode != widget.freehandMode;

    if (annotationsChanged) _renderAnnotations();

    // Fly to fit whenever the user selects a different route.
    if (routeChanged) _flyToFitRoute();
  }

  Widget _buildPainterFallback() {
    final route = widget.route;
    if (route == null) {
      return ColoredBox(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: Center(child: Text(AppLocalizations.of(context).mapNoRoute)),
      );
    }
    return CustomPaint(
      painter: RouteMapPainter(
        route: route,
        telemetry: widget.telemetry,
        highlightSectorId: widget.highlightSectorId,
        showSectors: widget.showSectors,
      ),
      child: const SizedBox.expand(),
    );
  }

  GeoPoint _focusPoint() {
    if (widget.route?.path.isNotEmpty ?? false) {
      return widget.route!.path.first;
    }
    if (widget.draftPath.isNotEmpty) return widget.draftPath.first;
    if (widget.initialCenter != null) return widget.initialCenter!;
    return const GeoPoint(latitude: 40.4168, longitude: -3.7038);
  }

  Future<void> _onMapCreated(mbx.MapboxMap map) async {
    _map = map;
    // Position camera immediately (no animation) to avoid a blank-map flash.
    final center = _focusPoint();
    await map.setCamera(mbx.CameraOptions(
      center: mbx.Point(
        coordinates: mbx.Position(center.longitude, center.latitude),
      ),
      zoom: 11,
    ));
    // Register tap / long-tap interactions via the non-deprecated API.
    if (widget.onTap != null) {
      map.addInteraction(
        mbx.TapInteraction.onMap(_handleTap),
        interactionID: 'splitway-tap',
      );
    }
    if (widget.onLongPress != null) {
      map.addInteraction(
        mbx.LongTapInteraction.onMap(_handleLongTap),
        interactionID: 'splitway-long-tap',
      );
    }
    if (!widget.interactive) {
      await map.gestures.updateSettings(mbx.GesturesSettings(
        scrollEnabled: false,
        rotateEnabled: false,
        pinchToZoomEnabled: false,
        doubleTapToZoomInEnabled: false,
        doubleTouchToZoomOutEnabled: false,
        quickZoomEnabled: false,
        pitchEnabled: false,
        pinchPanEnabled: false,
      ));
    }
    _lineManager = await map.annotations.createPolylineAnnotationManager();
    _circleManager = await map.annotations.createCircleAnnotationManager();
    await _updateGesturesForFreehand();
    await _renderAnnotations();
    await _flyToFitRoute();
  }

  Future<void> _updateGesturesForFreehand() async {
    final map = _map;
    if (map == null) return;
    if (widget.freehandMode) {
      await map.gestures.updateSettings(mbx.GesturesSettings(
        scrollEnabled: false,
        pinchToZoomEnabled: true,
        doubleTapToZoomInEnabled: true,
        doubleTouchToZoomOutEnabled: true,
        rotateEnabled: false,
        quickZoomEnabled: false,
        pitchEnabled: false,
        pinchPanEnabled: false,
      ));
    } else if (widget.interactive) {
      await map.gestures.updateSettings(mbx.GesturesSettings(
        scrollEnabled: true,
        pinchToZoomEnabled: true,
        doubleTapToZoomInEnabled: true,
        doubleTouchToZoomOutEnabled: true,
        rotateEnabled: true,
        quickZoomEnabled: true,
        pitchEnabled: true,
        pinchPanEnabled: true,
      ));
    }
  }

  Future<void> _flyToFitRoute() async {
    final map = _map;
    if (map == null) return;
    final geometry = _allGeometry();
    if (geometry.isEmpty) return;

    double minLat = geometry.first.latitude;
    double maxLat = minLat;
    double minLng = geometry.first.longitude;
    double maxLng = minLng;
    for (final p in geometry) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }

    // Use the SDK's own algorithm to compute the camera that fits the
    // bounding box. Padding of 80/60 dp gives a comfortable margin.
    final bounds = mbx.CoordinateBounds(
      southwest: mbx.Point(
          coordinates: mbx.Position(minLng, minLat)),
      northeast: mbx.Point(
          coordinates: mbx.Position(maxLng, maxLat)),
      infiniteBounds: false,
    );

    final padding = widget.interactive
        ? mbx.MbxEdgeInsets(top: 80, left: 60, bottom: 80, right: 60)
        : mbx.MbxEdgeInsets(top: 40, left: 30, bottom: 40, right: 30);

    try {
      final camera = await map.cameraForCoordinateBounds(
        bounds,
        padding,
        null,   // bearing
        null,   // pitch
        18.0,   // maxZoom — never closer than z18
        null,   // offset
      );
      await map.flyTo(camera, mbx.MapAnimationOptions(duration: 800));
    } catch (_) {
      // Fallback: fly to the centre at a safe zoom level.
      final centerLat = (minLat + maxLat) / 2;
      final centerLng = (minLng + maxLng) / 2;
      await map.flyTo(
        mbx.CameraOptions(
          center: mbx.Point(
              coordinates: mbx.Position(centerLng, centerLat)),
          zoom: 14,
        ),
        mbx.MapAnimationOptions(duration: 800),
      );
    }
  }

  List<GeoPoint> _allGeometry() {
    final all = <GeoPoint>[];
    final r = widget.route;
    if (r != null) {
      all.addAll(r.path);
      all
        ..add(r.startFinishGate.left)
        ..add(r.startFinishGate.right);
      for (final s in r.sectors) {
        all
          ..add(s.gate.left)
          ..add(s.gate.right);
      }
    }
    all.addAll(widget.draftPath);
    all.addAll(widget.draftSectorPoints);
    for (final t in widget.telemetry) {
      all.add(t.location);
    }
    return all;
  }

  Future<void> _renderAnnotations() async {
    final lineMgr = _lineManager;
    final circleMgr = _circleManager;
    if (lineMgr == null || circleMgr == null) return;

    await lineMgr.deleteAll();
    await circleMgr.deleteAll();

    final r = widget.route;
    if (r != null && r.path.isNotEmpty) {
      if (widget.showSectors && r.sectors.isNotEmpty) {
        // Draw each sector segment in a different color.
        final segments = computeSectorSegments(r.path, r.sectors);
        for (var i = 0; i < segments.length; i++) {
          if (segments[i].length < 2) continue;
          await lineMgr.create(mbx.PolylineAnnotationOptions(
            geometry: _toLineString(segments[i]),
            lineColor: kSectorColors[i % kSectorColors.length].value,
            lineWidth: 4,
          ));
        }
      } else {
        await lineMgr.create(mbx.PolylineAnnotationOptions(
          geometry: _toLineString(r.path),
          lineColor: 0xFF1565C0,
          lineWidth: 4,
        ));
      }
      if (widget.showSectors && r.sectors.isNotEmpty) {
        // Show sector boundary points as colored circles on the route.
        for (var i = 0; i < r.sectors.length; i++) {
          final center = r.sectors[i].gate.center;
          await circleMgr.create(mbx.CircleAnnotationOptions(
            geometry: mbx.Point(
                coordinates: mbx.Position(center.longitude, center.latitude)),
            circleColor: kSectorColors[(i + 1) % kSectorColors.length].value,
            circleRadius: 8,
            circleStrokeColor: 0xFFFFFFFF,
            circleStrokeWidth: 2,
          ));
        }
      }
    }

    if (widget.telemetry.length >= 2) {
      await lineMgr.create(mbx.PolylineAnnotationOptions(
        geometry: _toLineString(
          widget.telemetry.map((t) => t.location).toList(growable: false),
        ),
        lineColor: 0xFFE65100,
        lineWidth: 3,
        lineOpacity: 0.85,
      ));
    }

    // Draft segments: snapped = purple, freehand = orange.
    if (widget.draftSegments.isNotEmpty) {
      for (final seg in widget.draftSegments) {
        final rendered = seg.renderedPath;
        if (rendered.length < 2) continue;
        final color = seg is FreehandSegment ? 0xFFEF6C00 : 0xFF6A1B9A;
        await lineMgr.create(mbx.PolylineAnnotationOptions(
          geometry: _toLineString(rendered),
          lineColor: color,
          lineWidth: 3,
        ));
      }
    } else if (widget.draftPath.length >= 2) {
      // Backward compat: fall back to flat draftPath.
      await lineMgr.create(mbx.PolylineAnnotationOptions(
        geometry: _toLineString(widget.draftPath),
        lineColor: 0xFF6A1B9A,
        lineWidth: 3,
      ));
    }
    // Draw circles only for the user-tapped waypoints, not for every point
    // in the snapped path (which can have thousands of points and would
    // saturate the Pigeon channel).
    for (final p in widget.draftWaypoints) {
      await circleMgr.create(mbx.CircleAnnotationOptions(
        geometry: mbx.Point(
            coordinates: mbx.Position(p.longitude, p.latitude)),
        circleColor: 0xFF6A1B9A,
        circleRadius: 6,
      ));
    }
    for (var i = 0; i < widget.draftSectorPoints.length; i++) {
      final p = widget.draftSectorPoints[i];
      await circleMgr.create(mbx.CircleAnnotationOptions(
        geometry: mbx.Point(coordinates: mbx.Position(p.longitude, p.latitude)),
        circleColor: kSectorColors[i % kSectorColors.length].value,
        circleRadius: 8,
        circleStrokeColor: 0xFFFFFFFF,
        circleStrokeWidth: 2,
      ));
    }

    // User location dot.
    final userLoc = widget.userLocation;
    if (userLoc != null) {
      await circleMgr.create(mbx.CircleAnnotationOptions(
        geometry: mbx.Point(
            coordinates: mbx.Position(userLoc.longitude, userLoc.latitude)),
        circleColor: 0xFF2196F3,
        circleRadius: 10,
        circleStrokeColor: 0xFFFFFFFF,
        circleStrokeWidth: 3,
      ));
    }
  }

  mbx.LineString _toLineString(List<GeoPoint> points) {
    return mbx.LineString(
      coordinates:
          points.map((p) => mbx.Position(p.longitude, p.latitude)).toList(),
    );
  }

  void _onPointerDown(PointerDownEvent event) {
    _activePointers.add(event.pointer);
    if (_activePointers.length == 1) {
      _isFreehandStrokeActive = true;
      widget.onFreehandStart?.call();
      _convertAndSendFreehandPoint(event.localPosition);
    } else if (_isFreehandStrokeActive) {
      _isFreehandStrokeActive = false;
      widget.onFreehandEnd?.call();
    }
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (_isFreehandStrokeActive && _activePointers.length == 1) {
      _convertAndSendFreehandPoint(event.localPosition);
    }
  }

  void _onPointerUp(PointerUpEvent event) {
    _activePointers.remove(event.pointer);
    if (_isFreehandStrokeActive && _activePointers.isEmpty) {
      _isFreehandStrokeActive = false;
      widget.onFreehandEnd?.call();
    }
  }

  void _onPointerCancel(PointerCancelEvent event) {
    _activePointers.remove(event.pointer);
    if (_isFreehandStrokeActive && _activePointers.isEmpty) {
      _isFreehandStrokeActive = false;
      widget.onFreehandEnd?.call();
    }
  }

  Future<void> _convertAndSendFreehandPoint(Offset screenPos) async {
    final map = _map;
    if (map == null) return;
    try {
      final point = await map.coordinateForPixel(mbx.ScreenCoordinate(
        x: screenPos.dx,
        y: screenPos.dy,
      ));
      final coords = point.coordinates;
      widget.onFreehandPoint?.call(GeoPoint(
        latitude: coords.lat.toDouble(),
        longitude: coords.lng.toDouble(),
      ));
    } catch (_) {
      // Conversion failed — skip this point.
    }
  }

  void _handleTap(mbx.MapContentGestureContext ctx) {
    final coords = ctx.point.coordinates;
    widget.onTap?.call(GeoPoint(
      latitude: coords.lat.toDouble(),
      longitude: coords.lng.toDouble(),
    ));
  }

  void _handleLongTap(mbx.MapContentGestureContext ctx) {
    final coords = ctx.point.coordinates;
    widget.onLongPress?.call(GeoPoint(
      latitude: coords.lat.toDouble(),
      longitude: coords.lng.toDouble(),
    ));
  }
}
