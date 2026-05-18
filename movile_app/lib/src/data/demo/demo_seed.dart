import 'dart:math' as math;

import 'package:splitway_core/splitway_core.dart';

import '../repositories/local_draft_repository.dart';

class DemoSeed {
  DemoSeed._();

  /// Ensures the demo oval-track route exists so the editor and session
  /// screens have something visible even when no user is logged in.
  static Future<void> ensureSeeded(LocalDraftRepository repo) async {
    final existing = await repo.getRouteTemplate('demo-oval');
    if (existing != null) return;
    await repo.saveRouteTemplate(_buildOvalDemo());
  }

  static RouteTemplate _buildOvalDemo() {
    // Centered roughly at Madrid. Coordinates are illustrative — users can
    // replace this route with a real Mapbox-drawn one in iter 2.
    const baseLat = 40.4168;
    const baseLng = -3.7038;
    const radiusLat = 0.0009;
    const radiusLng = 0.0012;

    final path = <GeoPoint>[];
    for (int i = 0; i <= 24; i++) {
      final t = (i / 24) * 2 * math.pi;
      path.add(GeoPoint(
        latitude: baseLat + radiusLat * math.sin(t),
        longitude: baseLng + radiusLng * math.cos(t),
      ));
    }

    final startGate = GateDefinition(
      left: GeoPoint(
        latitude: baseLat - 0.00015,
        longitude: baseLng + radiusLng,
      ),
      right: GeoPoint(
        latitude: baseLat + 0.00015,
        longitude: baseLng + radiusLng,
      ),
    );
    final sector1 = SectorDefinition(
      id: 'demo-sector-1',
      order: 0,
      label: 'Curva 1',
      gate: GateDefinition(
        left: GeoPoint(
          latitude: baseLat + radiusLat,
          longitude: baseLng - 0.00015,
        ),
        right: GeoPoint(
          latitude: baseLat + radiusLat,
          longitude: baseLng + 0.00015,
        ),
      ),
    );
    final sector2 = SectorDefinition(
      id: 'demo-sector-2',
      order: 1,
      label: 'Curva 2',
      gate: GateDefinition(
        left: GeoPoint(
          latitude: baseLat - 0.00015,
          longitude: baseLng - radiusLng,
        ),
        right: GeoPoint(
          latitude: baseLat + 0.00015,
          longitude: baseLng - radiusLng,
        ),
      ),
    );

    return RouteTemplate(
      id: 'demo-oval',
      name: 'Pista demo (Madrid)',
      description: 'Ruta de ejemplo precargada al instalar la app.',
      path: path,
      startFinishGate: startGate,
      sectors: [sector1, sector2],
      difficulty: RouteDifficulty.easy,
      createdAt: DateTime.now(),
    );
  }
}
