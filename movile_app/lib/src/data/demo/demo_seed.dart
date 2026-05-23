import 'package:splitway_core/splitway_core.dart';

import '../../services/settings/app_settings_controller.dart';
import '../repositories/local_draft_repository.dart';

class DemoSeed {
  DemoSeed._();

  static const _jaramaId = 'demo-jarama';

  /// Seeds the Jarama circuit demo route unless the user has already dismissed it.
  static Future<void> ensureSeeded(
    LocalDraftRepository repo,
    AppSettingsController settings,
  ) async {
    if (settings.dismissedDemoIds.contains(_jaramaId)) return;
    final existing = await repo.getRouteTemplate(_jaramaId);
    if (existing != null) return;
    await repo.saveRouteTemplate(_buildJaramaDemo());
  }

  static RouteTemplate _buildJaramaDemo() {
    // Approximate GPS trace of Circuito del Jarama, San Sebastián de los Reyes,
    // Madrid (~40.62°N, ~3.59°W). ~21 waypoints, clockwise direction.
    final path = [
      GeoPoint(latitude: 40.6208, longitude: -3.5862), // Start/finish
      GeoPoint(latitude: 40.6213, longitude: -3.5874),
      GeoPoint(latitude: 40.6220, longitude: -3.5886),
      GeoPoint(latitude: 40.6230, longitude: -3.5897),
      GeoPoint(latitude: 40.6240, longitude: -3.5905),
      GeoPoint(latitude: 40.6248, longitude: -3.5915),
      GeoPoint(latitude: 40.6258, longitude: -3.5925),
      GeoPoint(latitude: 40.6265, longitude: -3.5935),
      GeoPoint(latitude: 40.6268, longitude: -3.5948), // Chicane peak
      GeoPoint(latitude: 40.6265, longitude: -3.5958),
      GeoPoint(latitude: 40.6255, longitude: -3.5965),
      GeoPoint(latitude: 40.6242, longitude: -3.5968),
      GeoPoint(latitude: 40.6230, longitude: -3.5962),
      GeoPoint(latitude: 40.6220, longitude: -3.5950),
      GeoPoint(latitude: 40.6215, longitude: -3.5937),
      GeoPoint(latitude: 40.6213, longitude: -3.5920),
      GeoPoint(latitude: 40.6215, longitude: -3.5905),
      GeoPoint(latitude: 40.6218, longitude: -3.5892),
      GeoPoint(latitude: 40.6214, longitude: -3.5880),
      GeoPoint(latitude: 40.6210, longitude: -3.5872),
      GeoPoint(latitude: 40.6208, longitude: -3.5862), // Close loop
    ];

    final startGate = GateDefinition(
      left: GeoPoint(latitude: 40.6204, longitude: -3.5862),
      right: GeoPoint(latitude: 40.6212, longitude: -3.5862),
    );

    final sector1 = SectorDefinition(
      id: 'demo-jarama-s1',
      order: 0,
      label: 'Sector 1',
      gate: GateDefinition(
        left: GeoPoint(latitude: 40.6270, longitude: -3.5942),
        right: GeoPoint(latitude: 40.6270, longitude: -3.5956),
      ),
    );

    final sector2 = SectorDefinition(
      id: 'demo-jarama-s2',
      order: 1,
      label: 'Sector 2',
      gate: GateDefinition(
        left: GeoPoint(latitude: 40.6212, longitude: -3.5894),
        right: GeoPoint(latitude: 40.6222, longitude: -3.5894),
      ),
    );

    return RouteTemplate(
      id: _jaramaId,
      name: 'Circuito del Jarama',
      description: 'Trazado aproximado del Circuito del Jarama '
          '(San Sebastián de los Reyes, Madrid).',
      path: path,
      startFinishGate: startGate,
      sectors: [sector1, sector2],
      difficulty: RouteDifficulty.hard,
      createdAt: DateTime.now(),
    );
  }
}
