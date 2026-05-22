import 'package:flutter/material.dart' hide Image;
import 'package:flutter/services.dart' show PlatformException;
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mbx;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:splitway_core/splitway_core.dart';
import 'package:splitway_mobile/l10n/app_localizations.dart';

import '../../features/editor/draft_segment.dart';
import 'route_map_painter.dart';
import 'sector_segments.dart';

enum MapStyle {
  outdoors,
  satelliteStreets,
  dark;

  String get uri => switch (this) {
        MapStyle.outdoors => mbx.MapboxStyles.OUTDOORS,
        MapStyle.satelliteStreets => mbx.MapboxStyles.SATELLITE_STREETS,
        MapStyle.dark => mbx.MapboxStyles.DARK,
      };

  IconData get icon => switch (this) {
        MapStyle.outdoors => Icons.terrain,
        MapStyle.satelliteStreets => Icons.satellite_alt,
        MapStyle.dark => Icons.dark_mode,
      };

  String label(AppLocalizations l) => switch (this) {
        MapStyle.outdoors => l.mapStyleOutdoors,
        MapStyle.satelliteStreets => l.mapStyleSatelliteStreets,
        MapStyle.dark => l.mapStyleDark,
      };
}

const _kMapStyleKey = 'splitway_map_style';

/// A notifier that always fires, even when set to the same value.
/// [ValueNotifier] silently ignores duplicate values, which breaks
/// "center on me" buttons that re-fly to the current position.
class FlyToNotifier extends ChangeNotifier {
  GeoPoint? _target;
  GeoPoint? get target => _target;

  void flyTo(GeoPoint point) {
    _target = point;
    notifyListeners();
  }
}

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
  final FlyToNotifier? flyToNotifier;
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
  bool _isRendering = false;
  bool _renderPending = false;
  MapStyle _mapStyle = MapStyle.outdoors;
  bool _styleMenuOpen = false;

  @override
  void initState() {
    super.initState();
    widget.flyToNotifier?.addListener(_onFlyToChanged);
    _loadMapStyle();
  }

  Future<void> _loadMapStyle() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_kMapStyleKey);
    if (stored != null && mounted) {
      final parsed = MapStyle.values.where((s) => s.name == stored);
      if (parsed.isNotEmpty) {
        setState(() => _mapStyle = parsed.first);
        final map = _map;
        if (map != null) {
          await map.loadStyleURI(_mapStyle.uri);
          await _recreateManagers();
          await _renderAnnotations();
        }
      }
    }
  }

  Future<void> _switchStyle(MapStyle style) async {
    if (style == _mapStyle) {
      setState(() => _styleMenuOpen = false);
      return;
    }
    setState(() {
      _mapStyle = style;
      _styleMenuOpen = false;
    });
    SharedPreferences.getInstance().then((p) => p.setString(_kMapStyleKey, style.name));
    final map = _map;
    if (map == null) return;
    await map.loadStyleURI(style.uri);
    await _recreateManagers();
    await _renderAnnotations();
  }

  Future<void> _recreateManagers() async {
    final map = _map;
    if (map == null) return;
    _lineManager = await map.annotations.createPolylineAnnotationManager();
    _circleManager = await map.annotations.createCircleAnnotationManager();
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
    final target = widget.flyToNotifier?.target;
    if (target == null || _map == null || !mounted) return;
    _map!.flyTo(
      mbx.CameraOptions(
        center: mbx.Point(
          coordinates: mbx.Position(target.longitude, target.latitude),
        ),
        zoom: 15,
      ),
      mbx.MapAnimationOptions(duration: 800),
    ).catchError((_) {
      // Map channel torn down — ignore silently.
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.useMapbox) {
      return _buildPainterFallback();
    }
    final mapWidget = mbx.MapWidget(
      key: const ValueKey('splitway-mapbox'),
      styleUri: widget.styleUri ?? _mapStyle.uri,
      onMapCreated: _onMapCreated,
    );

    final showStyleButton = widget.interactive && widget.useMapbox;

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
        if (_styleMenuOpen)
          Positioned.fill(
            child: GestureDetector(
              onTap: () => setState(() => _styleMenuOpen = false),
              behavior: HitTestBehavior.opaque,
              child: const SizedBox.expand(),
            ),
          ),
        if (showStyleButton && _styleMenuOpen)
          Positioned(
            top: 8,
            right: 8,
            child: _buildStyleMenu(context),
          ),
        if (showStyleButton && !_styleMenuOpen)
          Positioned(
            top: 8,
            right: 8,
            child: _buildLayersButton(context),
          ),
      ],
    );
  }

  Widget _buildLayersButton(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Material(
      elevation: 4,
      shape: const CircleBorder(),
      color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.9),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: () => setState(() => _styleMenuOpen = true),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Tooltip(
            message: l.mapStyleLayersTooltip,
            child: Icon(
              Icons.layers,
              size: 22,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStyleMenu(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      elevation: 6,
      borderRadius: BorderRadius.circular(12),
      color: colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: IntrinsicWidth(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final style in MapStyle.values)
                _buildStyleOption(context, l, colorScheme, style),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStyleOption(
    BuildContext context,
    AppLocalizations l,
    ColorScheme colorScheme,
    MapStyle style,
  ) {
    final isSelected = style == _mapStyle;
    return InkWell(
      onTap: () => _switchStyle(style),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Icon(
              style.icon,
              size: 20,
              color: isSelected ? colorScheme.primary : colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 10),
            Text(
              style.label(l),
              style: TextStyle(
                fontSize: 14,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                color: isSelected ? colorScheme.primary : colorScheme.onSurface,
              ),
            ),
            const SizedBox(width: 16),
            if (isSelected)
              Icon(Icons.check, size: 18, color: colorScheme.primary),
          ],
        ),
      ),
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
    if (map == null || !mounted) return;
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
      if (!mounted) return;
      await map.flyTo(camera, mbx.MapAnimationOptions(duration: 800));
    } on PlatformException {
      // Map channel torn down — nothing to animate.
      return;
    } catch (_) {
      // cameraForCoordinateBounds failed (e.g. degenerate bounds).
      // Fallback: fly to the centre at a safe zoom level.
      if (!mounted) return;
      final centerLat = (minLat + maxLat) / 2;
      final centerLng = (minLng + maxLng) / 2;
      try {
        await map.flyTo(
          mbx.CameraOptions(
            center: mbx.Point(
                coordinates: mbx.Position(centerLng, centerLat)),
            zoom: 14,
          ),
          mbx.MapAnimationOptions(duration: 800),
        );
      } on PlatformException {
        // Channel gone — ignore silently.
      }
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
    // Coalesce rapid calls: if a render is already in progress, mark pending
    // and return. The in-progress render will re-run when it finishes.
    if (_isRendering) {
      _renderPending = true;
      return;
    }
    _isRendering = true;
    try {
      await _renderAnnotationsCore();
    } finally {
      _isRendering = false;
      // If a new render was requested while we were busy, run it now.
      if (_renderPending) {
        _renderPending = false;
        _renderAnnotations();
      }
    }
  }

  Future<void> _renderAnnotationsCore() async {
    final lineMgr = _lineManager;
    final circleMgr = _circleManager;
    if (lineMgr == null || circleMgr == null) return;

    try {
      await lineMgr.deleteAll();
      await circleMgr.deleteAll();
    } on PlatformException {
      // Map channel torn down (e.g. widget disposed mid-render). Bail out.
      return;
    }
    if (!mounted) return;

    final r = widget.route;
    if (r != null && r.path.isNotEmpty) {
      if (widget.showSectors && r.sectors.isNotEmpty) {
        // Draw each sector segment in a different color.
        final segments = computeSectorSegments(r.path, r.sectors);
        for (var i = 0; i < segments.length; i++) {
          if (segments[i].length < 2) continue;
          if (!mounted) return;
          try {
            await lineMgr.create(mbx.PolylineAnnotationOptions(
              geometry: _toLineString(segments[i]),
              lineColor: kSectorColors[i % kSectorColors.length].value,
              lineWidth: 4,
            ));
          } on PlatformException {
            return;
          }
        }
      } else {
        if (!mounted) return;
        try {
          await lineMgr.create(mbx.PolylineAnnotationOptions(
            geometry: _toLineString(r.path),
            lineColor: 0xFF1565C0,
            lineWidth: 4,
          ));
        } on PlatformException {
          return;
        }
      }
      if (widget.showSectors && r.sectors.isNotEmpty) {
        // Show sector boundary points as colored circles on the route.
        for (var i = 0; i < r.sectors.length; i++) {
          if (!mounted) return;
          final center = r.sectors[i].gate.center;
          try {
            await circleMgr.create(mbx.CircleAnnotationOptions(
              geometry: mbx.Point(
                  coordinates: mbx.Position(center.longitude, center.latitude)),
              circleColor: kSectorColors[(i + 1) % kSectorColors.length].value,
              circleRadius: 8,
              circleStrokeColor: 0xFFFFFFFF,
              circleStrokeWidth: 2,
            ));
          } on PlatformException {
            return;
          }
        }
      }
    }

    if (!mounted) return;
    if (widget.telemetry.length >= 2) {
      try {
        await lineMgr.create(mbx.PolylineAnnotationOptions(
          geometry: _toLineString(
            widget.telemetry.map((t) => t.location).toList(growable: false),
          ),
          lineColor: 0xFFE65100,
          lineWidth: 3,
          lineOpacity: 0.85,
        ));
      } on PlatformException {
        return;
      }
    }

    if (!mounted) return;
    // Draft segments: snapped = purple, freehand = orange.
    if (widget.draftSegments.isNotEmpty) {
      for (final seg in widget.draftSegments) {
        final rendered = seg.renderedPath;
        if (rendered.length < 2) continue;
        if (!mounted) return;
        final color = seg is FreehandSegment ? 0xFFEF6C00 : 0xFF6A1B9A;
        try {
          await lineMgr.create(mbx.PolylineAnnotationOptions(
            geometry: _toLineString(rendered),
            lineColor: color,
            lineWidth: 3,
          ));
        } on PlatformException {
          return;
        }
      }
    } else if (widget.draftPath.length >= 2) {
      // Backward compat: fall back to flat draftPath.
      try {
        await lineMgr.create(mbx.PolylineAnnotationOptions(
          geometry: _toLineString(widget.draftPath),
          lineColor: 0xFF6A1B9A,
          lineWidth: 3,
        ));
      } on PlatformException {
        return;
      }
    }
    // Draw circles only for the user-tapped waypoints, not for every point
    // in the snapped path (which can have thousands of points and would
    // saturate the Pigeon channel).
    for (final p in widget.draftWaypoints) {
      if (!mounted) return;
      try {
        await circleMgr.create(mbx.CircleAnnotationOptions(
          geometry: mbx.Point(
              coordinates: mbx.Position(p.longitude, p.latitude)),
          circleColor: 0xFF6A1B9A,
          circleRadius: 6,
        ));
      } on PlatformException {
        return;
      }
    }
    for (var i = 0; i < widget.draftSectorPoints.length; i++) {
      if (!mounted) return;
      final p = widget.draftSectorPoints[i];
      try {
        await circleMgr.create(mbx.CircleAnnotationOptions(
          geometry: mbx.Point(coordinates: mbx.Position(p.longitude, p.latitude)),
          circleColor: kSectorColors[i % kSectorColors.length].value,
          circleRadius: 8,
          circleStrokeColor: 0xFFFFFFFF,
          circleStrokeWidth: 2,
        ));
      } on PlatformException {
        return;
      }
    }

    if (!mounted) return;
    // User location dot.
    final userLoc = widget.userLocation;
    if (userLoc != null) {
      try {
        await circleMgr.create(mbx.CircleAnnotationOptions(
          geometry: mbx.Point(
              coordinates: mbx.Position(userLoc.longitude, userLoc.latitude)),
          circleColor: 0xFF2196F3,
          circleRadius: 10,
          circleStrokeColor: 0xFFFFFFFF,
          circleStrokeWidth: 3,
        ));
      } on PlatformException {
        return;
      }
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
