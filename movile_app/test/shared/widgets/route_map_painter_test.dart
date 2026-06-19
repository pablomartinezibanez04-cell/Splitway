import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:splitway_core/splitway_core.dart';
import 'package:splitway_mobile/src/shared/widgets/route_map_painter.dart';

RouteTemplate _route() => RouteTemplate(
      id: 'route-x',
      name: 'Circuito X',
      path: const [
        GeoPoint(latitude: 40.0, longitude: -3.0),
        GeoPoint(latitude: 40.002, longitude: -3.0),
      ],
      startFinishGate: const GateDefinition(
        left: GeoPoint(latitude: 40.0, longitude: -3.0),
        right: GeoPoint(latitude: 40.001, longitude: -3.0),
      ),
      sectors: const [],
      difficulty: RouteDifficulty.medium,
      createdAt: DateTime(2024, 1, 1),
    );

void main() {
  group('RouteMapPainter finishMarker', () {
    test('shouldRepaint reacts to a finishMarker change', () {
      final base = RouteMapPainter(route: _route());
      final withMarker = RouteMapPainter(
        route: _route(),
        finishMarker: const GeoPoint(latitude: 40.002, longitude: -3.0),
      );
      expect(withMarker.shouldRepaint(base), isTrue);
      expect(base.shouldRepaint(withMarker), isTrue);
      expect(withMarker.shouldRepaint(withMarker), isFalse);
    });

    test('paints without error when finishMarker overrides the gate', () {
      final painter = RouteMapPainter(
        route: _route(),
        finishMarker: const GeoPoint(latitude: 40.002, longitude: -3.0),
      );
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      expect(
        () => painter.paint(canvas, const Size(200, 120)),
        returnsNormally,
      );
      recorder.endRecording().dispose();
    });
  });
}
