import 'package:flutter/material.dart';
import 'package:splitway_core/splitway_core.dart';
import 'sector_segments.dart';

/// Iter 1 placeholder for Mapbox. Renders a route, gates and (optionally)
/// a session telemetry trace by projecting lat/lng to the canvas with
/// uniform bounding-box scaling. Replaceable with a real MapboxMap in iter 2.
class RouteMapPainter extends CustomPainter {
  const RouteMapPainter({
    required this.route,
    this.telemetry = const [],
    this.highlightSectorId,
    this.showSectors = false,
    this.finishMarker,
  });

  final RouteTemplate route;
  final List<TelemetryPoint> telemetry;
  final String? highlightSectorId;
  final bool showSectors;

  /// Overrides where the checkered finish flag is drawn. When null the flag
  /// is placed at the route's last path node (the end of the route).
  /// Used for free rides, which have no gate, to mark the end of the trace.
  final GeoPoint? finishMarker;

  @override
  void paint(Canvas canvas, Size size) {
    final allPoints = <GeoPoint>[
      ...route.path,
      route.startFinishGate.left,
      route.startFinishGate.right,
      for (final s in route.sectors) ...[s.gate.left, s.gate.right],
      for (final p in telemetry) p.location,
      if (finishMarker != null) finishMarker!,
    ];
    if (allPoints.isEmpty) return;

    double minLat = allPoints.first.latitude;
    double maxLat = minLat;
    double minLng = allPoints.first.longitude;
    double maxLng = minLng;
    for (final p in allPoints) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }
    final pad = 0.0001;
    minLat -= pad;
    maxLat += pad;
    minLng -= pad;
    maxLng += pad;

    final spanLat = (maxLat - minLat).abs().clamp(1e-9, double.infinity);
    final spanLng = (maxLng - minLng).abs().clamp(1e-9, double.infinity);
    // Match aspect — pick the tighter scale.
    final scale = (size.width / spanLng).clamp(0.0, double.infinity) <
            (size.height / spanLat).clamp(0.0, double.infinity)
        ? size.width / spanLng
        : size.height / spanLat;

    final offsetX = (size.width - spanLng * scale) / 2;
    final offsetY = (size.height - spanLat * scale) / 2;

    Offset project(GeoPoint p) {
      final x = (p.longitude - minLng) * scale + offsetX;
      // Latitude grows northward, but canvas y grows downward.
      final y = (maxLat - p.latitude) * scale + offsetY;
      return Offset(x, y);
    }

    // Background grid.
    final gridPaint = Paint()
      ..color = const Color(0xFFE0E0E0)
      ..strokeWidth = 0.5;
    for (double x = 0; x <= size.width; x += 24) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    for (double y = 0; y <= size.height; y += 24) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    // Path — plain or sector-colored.
    if (route.path.length >= 2) {
      if (showSectors && route.sectors.isNotEmpty) {
        final segments = computeSectorSegments(route.path, route.sectors);
        for (var i = 0; i < segments.length; i++) {
          final seg = segments[i];
          if (seg.length < 2) continue;
          final paint = Paint()
            ..color = kSectorColors[i % kSectorColors.length]
            ..strokeWidth = 3
            ..style = PaintingStyle.stroke
            ..strokeJoin = StrokeJoin.round;
          final p = Path()..moveTo(project(seg.first).dx, project(seg.first).dy);
          for (final pt in seg.skip(1)) {
            final o = project(pt);
            p.lineTo(o.dx, o.dy);
          }
          canvas.drawPath(p, paint);
        }
      } else {
        final pathPaint = Paint()
          ..color = const Color(0xFF1565C0)
          ..strokeWidth = 3
          ..style = PaintingStyle.stroke
          ..strokeJoin = StrokeJoin.round;
        final p = Path()
          ..moveTo(project(route.path.first).dx, project(route.path.first).dy);
        for (final pt in route.path.skip(1)) {
          final o = project(pt);
          p.lineTo(o.dx, o.dy);
        }
        canvas.drawPath(p, pathPaint);
      }
    }

    // Telemetry trace (if any).
    if (telemetry.length >= 2) {
      final telPaint = Paint()
        ..color = const Color(0xFFE65100).withValues(alpha: 0.85)
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke;
      final p = Path()
        ..moveTo(project(telemetry.first.location).dx,
            project(telemetry.first.location).dy);
      for (final t in telemetry.skip(1)) {
        final o = project(t.location);
        p.lineTo(o.dx, o.dy);
      }
      canvas.drawPath(p, telPaint);
    }

    // Sector boundary points (only when showSectors is active).
    if (showSectors && route.sectors.isNotEmpty) {
      for (var i = 0; i < route.sectors.length; i++) {
        final center = route.sectors[i].gate.center;
        final dot = Paint()
          ..color = kSectorColors[(i + 1) % kSectorColors.length];
        canvas.drawCircle(project(center), 6, dot);
        final border = Paint()
          ..color = const Color(0xFFFFFFFF)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2;
        canvas.drawCircle(project(center), 6, border);
      }
    }

    // Checkered flag marking the finish: a free ride's last point when
    // [finishMarker] is set, otherwise the route's last path node.
    final sfPos = project(finishMarker ?? route.path.last);
    const flagR = 8.0;
    canvas.drawCircle(
        sfPos, flagR, Paint()..color = const Color(0xFFFFFFFF));
    canvas.save();
    canvas.clipPath(
        Path()..addOval(Rect.fromCircle(center: sfPos, radius: flagR)));
    const cells = 4;
    final cellSize = flagR * 2 / cells;
    final black = Paint()..color = const Color(0xFF212121);
    for (var row = 0; row < cells; row++) {
      for (var col = 0; col < cells; col++) {
        if ((row + col) % 2 == 0) {
          canvas.drawRect(
            Rect.fromLTWH(
              sfPos.dx - flagR + col * cellSize,
              sfPos.dy - flagR + row * cellSize,
              cellSize,
              cellSize,
            ),
            black,
          );
        }
      }
    }
    canvas.restore();
    canvas.drawCircle(
      sfPos,
      flagR,
      Paint()
        ..color = const Color(0xFF212121)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(covariant RouteMapPainter oldDelegate) {
    return oldDelegate.route != route ||
        oldDelegate.telemetry.length != telemetry.length ||
        oldDelegate.highlightSectorId != highlightSectorId ||
        oldDelegate.showSectors != showSectors ||
        oldDelegate.finishMarker != finishMarker;
  }
}
