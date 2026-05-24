import 'package:splitway_core/splitway_core.dart';

import '../../services/routing/elevation_service.dart';
import '../../services/settings/app_settings_controller.dart';
import '../repositories/local_draft_repository.dart';

class DemoSeed {
  DemoSeed._();

  static const _demoId = 'demo-espana';

  /// Legacy demo route IDs that are no longer active and must be removed.
  static const _staleIds = ['demo-oval', 'demo-jarama'];

  /// Seeds the España demo route unless the user has already dismissed it.
  /// Also purges any legacy demo routes left over from older app versions.
  /// If [elevationService] is provided, the path is enriched with altitude
  /// data on first seed so [RouteTemplate.elevationRangeMeters] is populated.
  static Future<void> ensureSeeded(
    LocalDraftRepository repo,
    AppSettingsController settings, {
    ElevationService? elevationService,
  }) async {
    for (final staleId in _staleIds) {
      await repo.deleteRoute(staleId);
    }
    if (settings.dismissedDemoIds.contains(_demoId)) return;
    final existing = await repo.getRouteTemplate(_demoId);
    if (existing != null) return;
    await repo.saveRouteTemplate(
      await _buildEspanaDemo(elevationService),
    );
  }

  static Future<RouteTemplate> _buildEspanaDemo(
    ElevationService? elevationService,
  ) async {
    // Real GPS trace recorded near Rascafría, Madrid (~40.90°N, ~3.86°W).
    // 194 sampled points from a 961-point original trace.
    var path = [
      GeoPoint(latitude: 40.904159, longitude: -3.865264),
      GeoPoint(latitude: 40.903307, longitude: -3.863611),
      GeoPoint(latitude: 40.901953, longitude: -3.862806),
      GeoPoint(latitude: 40.901069, longitude: -3.862567),
      GeoPoint(latitude: 40.898699, longitude: -3.863098),
      GeoPoint(latitude: 40.896564, longitude: -3.86267),
      GeoPoint(latitude: 40.895416, longitude: -3.861983),
      GeoPoint(latitude: 40.89448, longitude: -3.861545),
      GeoPoint(latitude: 40.893598, longitude: -3.859728),
      GeoPoint(latitude: 40.890884, longitude: -3.855632),
      GeoPoint(latitude: 40.887826, longitude: -3.85126),
      GeoPoint(latitude: 40.887253, longitude: -3.850295),
      GeoPoint(latitude: 40.887252, longitude: -3.848541),
      GeoPoint(latitude: 40.887581, longitude: -3.846229),
      GeoPoint(latitude: 40.887829, longitude: -3.843217),
      GeoPoint(latitude: 40.88782, longitude: -3.841584),
      GeoPoint(latitude: 40.888107, longitude: -3.839995),
      GeoPoint(latitude: 40.888024, longitude: -3.839119),
      GeoPoint(latitude: 40.887385, longitude: -3.837899),
      GeoPoint(latitude: 40.886777, longitude: -3.83761),
      GeoPoint(latitude: 40.886857, longitude: -3.838087),
      GeoPoint(latitude: 40.886769, longitude: -3.838352),
      GeoPoint(latitude: 40.886225, longitude: -3.838235),
      GeoPoint(latitude: 40.885215, longitude: -3.838341),
      GeoPoint(latitude: 40.885133, longitude: -3.838552),
      GeoPoint(latitude: 40.885548, longitude: -3.838917),
      GeoPoint(latitude: 40.885955, longitude: -3.839434),
      GeoPoint(latitude: 40.886149, longitude: -3.840525),
      GeoPoint(latitude: 40.886001, longitude: -3.840624),
      GeoPoint(latitude: 40.88567, longitude: -3.840056),
      GeoPoint(latitude: 40.885176, longitude: -3.839654),
      GeoPoint(latitude: 40.883597, longitude: -3.839391),
      GeoPoint(latitude: 40.883157, longitude: -3.839722),
      GeoPoint(latitude: 40.8829, longitude: -3.840165),
      GeoPoint(latitude: 40.881888, longitude: -3.842383),
      GeoPoint(latitude: 40.88119, longitude: -3.844075),
      GeoPoint(latitude: 40.880548, longitude: -3.845246),
      GeoPoint(latitude: 40.880233, longitude: -3.845485),
      GeoPoint(latitude: 40.879522, longitude: -3.845585),
      GeoPoint(latitude: 40.878611, longitude: -3.844884),
      GeoPoint(latitude: 40.87813, longitude: -3.844966),
      GeoPoint(latitude: 40.877801, longitude: -3.844892),
      GeoPoint(latitude: 40.877513, longitude: -3.844786),
      GeoPoint(latitude: 40.877483, longitude: -3.845037),
      GeoPoint(latitude: 40.877949, longitude: -3.845405),
      GeoPoint(latitude: 40.878763, longitude: -3.845877),
      GeoPoint(latitude: 40.878923, longitude: -3.846508),
      GeoPoint(latitude: 40.878444, longitude: -3.84807),
      GeoPoint(latitude: 40.878284, longitude: -3.848054),
      GeoPoint(latitude: 40.878387, longitude: -3.84765),
      GeoPoint(latitude: 40.878582, longitude: -3.846842),
      GeoPoint(latitude: 40.878387, longitude: -3.846497),
      GeoPoint(latitude: 40.877299, longitude: -3.846305),
      GeoPoint(latitude: 40.876811, longitude: -3.846005),
      GeoPoint(latitude: 40.876508, longitude: -3.845851),
      GeoPoint(latitude: 40.876246, longitude: -3.845209),
      GeoPoint(latitude: 40.876361, longitude: -3.843306),
      GeoPoint(latitude: 40.876333, longitude: -3.84248),
      GeoPoint(latitude: 40.875965, longitude: -3.84165),
      GeoPoint(latitude: 40.875634, longitude: -3.841627),
      GeoPoint(latitude: 40.8753, longitude: -3.84193),
      GeoPoint(latitude: 40.875052, longitude: -3.843407),
      GeoPoint(latitude: 40.874144, longitude: -3.844539),
      GeoPoint(latitude: 40.873252, longitude: -3.844487),
      GeoPoint(latitude: 40.872067, longitude: -3.844353),
      GeoPoint(latitude: 40.871518, longitude: -3.84465),
      GeoPoint(latitude: 40.87092, longitude: -3.845173),
      GeoPoint(latitude: 40.869887, longitude: -3.845349),
      GeoPoint(latitude: 40.868511, longitude: -3.84589),
      GeoPoint(latitude: 40.868142, longitude: -3.845338),
      GeoPoint(latitude: 40.867577, longitude: -3.843829),
      GeoPoint(latitude: 40.867206, longitude: -3.843301),
      GeoPoint(latitude: 40.866744, longitude: -3.843317),
      GeoPoint(latitude: 40.866448, longitude: -3.8431),
      GeoPoint(latitude: 40.866082, longitude: -3.842556),
      GeoPoint(latitude: 40.86513, longitude: -3.84233),
      GeoPoint(latitude: 40.864445, longitude: -3.841763),
      GeoPoint(latitude: 40.86433, longitude: -3.841287),
      GeoPoint(latitude: 40.864097, longitude: -3.840852),
      GeoPoint(latitude: 40.86338, longitude: -3.840747),
      GeoPoint(latitude: 40.862625, longitude: -3.841155),
      GeoPoint(latitude: 40.861774, longitude: -3.841601),
      GeoPoint(latitude: 40.861622, longitude: -3.841963),
      GeoPoint(latitude: 40.861428, longitude: -3.84315),
      GeoPoint(latitude: 40.860682, longitude: -3.844535),
      GeoPoint(latitude: 40.859925, longitude: -3.844908),
      GeoPoint(latitude: 40.859355, longitude: -3.844897),
      GeoPoint(latitude: 40.858927, longitude: -3.844422),
      GeoPoint(latitude: 40.858353, longitude: -3.84457),
      GeoPoint(latitude: 40.85759, longitude: -3.84481),
      GeoPoint(latitude: 40.857119, longitude: -3.845883),
      GeoPoint(latitude: 40.855752, longitude: -3.84706),
      GeoPoint(latitude: 40.855323, longitude: -3.847138),
      GeoPoint(latitude: 40.854448, longitude: -3.846529),
      GeoPoint(latitude: 40.85328, longitude: -3.844648),
      GeoPoint(latitude: 40.852744, longitude: -3.844654),
      GeoPoint(latitude: 40.852148, longitude: -3.844669),
      GeoPoint(latitude: 40.851068, longitude: -3.843383),
      GeoPoint(latitude: 40.84989, longitude: -3.843385),
      GeoPoint(latitude: 40.849551, longitude: -3.842514),
      GeoPoint(latitude: 40.849038, longitude: -3.841538),
      GeoPoint(latitude: 40.847114, longitude: -3.841972),
      GeoPoint(latitude: 40.846644, longitude: -3.84168),
      GeoPoint(latitude: 40.845321, longitude: -3.841567),
      GeoPoint(latitude: 40.843948, longitude: -3.841692),
      GeoPoint(latitude: 40.842816, longitude: -3.839683),
      GeoPoint(latitude: 40.842449, longitude: -3.83652),
      GeoPoint(latitude: 40.840769, longitude: -3.834355),
      GeoPoint(latitude: 40.839004, longitude: -3.834499),
      GeoPoint(latitude: 40.836111, longitude: -3.834745),
      GeoPoint(latitude: 40.83451, longitude: -3.835187),
      GeoPoint(latitude: 40.833421, longitude: -3.836275),
      GeoPoint(latitude: 40.83158, longitude: -3.836568),
      GeoPoint(latitude: 40.83064, longitude: -3.83667),
      GeoPoint(latitude: 40.829457, longitude: -3.835053),
      GeoPoint(latitude: 40.828518, longitude: -3.832828),
      GeoPoint(latitude: 40.828174, longitude: -3.831634),
      GeoPoint(latitude: 40.828125, longitude: -3.830576),
      GeoPoint(latitude: 40.828845, longitude: -3.82945),
      GeoPoint(latitude: 40.829253, longitude: -3.827978),
      GeoPoint(latitude: 40.829716, longitude: -3.826859),
      GeoPoint(latitude: 40.830175, longitude: -3.82651),
      GeoPoint(latitude: 40.830761, longitude: -3.826026),
      GeoPoint(latitude: 40.831369, longitude: -3.824388),
      GeoPoint(latitude: 40.831833, longitude: -3.821785),
      GeoPoint(latitude: 40.831616, longitude: -3.820837),
      GeoPoint(latitude: 40.831528, longitude: -3.819789),
      GeoPoint(latitude: 40.83139, longitude: -3.818864),
      GeoPoint(latitude: 40.831508, longitude: -3.818252),
      GeoPoint(latitude: 40.832214, longitude: -3.817186),
      GeoPoint(latitude: 40.832795, longitude: -3.816487),
      GeoPoint(latitude: 40.833483, longitude: -3.816594),
      GeoPoint(latitude: 40.833692, longitude: -3.816093),
      GeoPoint(latitude: 40.833897, longitude: -3.815816),
      GeoPoint(latitude: 40.83384, longitude: -3.815319),
      GeoPoint(latitude: 40.833906, longitude: -3.814346),
      GeoPoint(latitude: 40.834169, longitude: -3.812556),
      GeoPoint(latitude: 40.834199, longitude: -3.810525),
      GeoPoint(latitude: 40.834423, longitude: -3.809807),
      GeoPoint(latitude: 40.834755, longitude: -3.809376),
      GeoPoint(latitude: 40.835482, longitude: -3.809075),
      GeoPoint(latitude: 40.836214, longitude: -3.80929),
      GeoPoint(latitude: 40.837289, longitude: -3.810324),
      GeoPoint(latitude: 40.837501, longitude: -3.810377),
      GeoPoint(latitude: 40.837908, longitude: -3.809904),
      GeoPoint(latitude: 40.838175, longitude: -3.809241),
      GeoPoint(latitude: 40.838386, longitude: -3.808423),
      GeoPoint(latitude: 40.838634, longitude: -3.808163),
      GeoPoint(latitude: 40.839345, longitude: -3.80819),
      GeoPoint(latitude: 40.839784, longitude: -3.808169),
      GeoPoint(latitude: 40.839964, longitude: -3.807959),
      GeoPoint(latitude: 40.840133, longitude: -3.806876),
      GeoPoint(latitude: 40.840438, longitude: -3.806475),
      GeoPoint(latitude: 40.841279, longitude: -3.80614),
      GeoPoint(latitude: 40.841515, longitude: -3.805389),
      GeoPoint(latitude: 40.840986, longitude: -3.804176),
      GeoPoint(latitude: 40.840636, longitude: -3.803868),
      GeoPoint(latitude: 40.84033, longitude: -3.803828),
      GeoPoint(latitude: 40.839676, longitude: -3.803971),
      GeoPoint(latitude: 40.838224, longitude: -3.80311),
      GeoPoint(latitude: 40.837042, longitude: -3.80217),
      GeoPoint(latitude: 40.83647, longitude: -3.801841),
      GeoPoint(latitude: 40.83569, longitude: -3.800849),
      GeoPoint(latitude: 40.835334, longitude: -3.800675),
      GeoPoint(latitude: 40.834306, longitude: -3.800461),
      GeoPoint(latitude: 40.831735, longitude: -3.799013),
      GeoPoint(latitude: 40.830276, longitude: -3.797834),
      GeoPoint(latitude: 40.829796, longitude: -3.797445),
      GeoPoint(latitude: 40.828149, longitude: -3.796552),
      GeoPoint(latitude: 40.824368, longitude: -3.793755),
      GeoPoint(latitude: 40.823216, longitude: -3.793764),
      GeoPoint(latitude: 40.823202, longitude: -3.793355),
      GeoPoint(latitude: 40.823315, longitude: -3.79211),
      GeoPoint(latitude: 40.823425, longitude: -3.791378),
      GeoPoint(latitude: 40.822354, longitude: -3.789803),
      GeoPoint(latitude: 40.821688, longitude: -3.787614),
      GeoPoint(latitude: 40.821761, longitude: -3.787324),
      GeoPoint(latitude: 40.822319, longitude: -3.787127),
      GeoPoint(latitude: 40.824649, longitude: -3.787427),
      GeoPoint(latitude: 40.82521, longitude: -3.787499),
      GeoPoint(latitude: 40.825307, longitude: -3.787285),
      GeoPoint(latitude: 40.824725, longitude: -3.786309),
      GeoPoint(latitude: 40.823297, longitude: -3.785215),
      GeoPoint(latitude: 40.82121, longitude: -3.783937),
      GeoPoint(latitude: 40.8204, longitude: -3.783262),
      GeoPoint(latitude: 40.819623, longitude: -3.783048),
      GeoPoint(latitude: 40.818031, longitude: -3.782015),
      GeoPoint(latitude: 40.816584, longitude: -3.780899),
      GeoPoint(latitude: 40.815815, longitude: -3.7809),
      GeoPoint(latitude: 40.814819, longitude: -3.780222),
      GeoPoint(latitude: 40.814106, longitude: -3.778911),
      GeoPoint(latitude: 40.814067, longitude: -3.778065),
      GeoPoint(latitude: 40.811904, longitude: -3.776073),
    ];

    if (elevationService != null) {
      path = await elevationService.enrich(path);
    }

    double? elevMin;
    double? elevMax;
    for (final p in path) {
      final alt = p.altitudeMeters;
      if (alt == null) continue;
      if (elevMin == null || alt < elevMin) elevMin = alt;
      if (elevMax == null || alt > elevMax) elevMax = alt;
    }
    final elevationRange = (elevMin != null && elevMax != null)
        ? elevMax - elevMin
        : null;

    final startGate = GateDefinition(
      left: GeoPoint(latitude: 40.9040613648343, longitude: -3.86514083951192),
      right: GeoPoint(latitude: 40.9042566350347, longitude: -3.86538716085181),
    );

    final sector1 = SectorDefinition(
      id: 'demo-espana-s1',
      order: 0,
      label: 'Sector 1',
      gate: GateDefinition(
        left: GeoPoint(latitude: 40.88691837891315, longitude: -3.8373778310237867),
        right: GeoPoint(latitude: 40.88690362081269, longitude: -3.8377341689364357),
      ),
    );

    final sector2 = SectorDefinition(
      id: 'demo-espana-s2',
      order: 1,
      label: 'Sector 2',
      gate: GateDefinition(
        left: GeoPoint(latitude: 40.84164773628664, longitude: -3.805357203923336),
        right: GeoPoint(latitude: 40.84138226370464, longitude: -3.805420795949317),
      ),
    );

    return RouteTemplate(
      id: _demoId,
      name: 'Demo España',
      description: 'Ruta de demostración grabada cerca de Rascafría, Madrid.',
      path: path,
      startFinishGate: startGate,
      sectors: [sector1, sector2],
      difficulty: RouteDifficulty.medium,
      locationLabel: 'Rascafría, Madrid, Spain',
      createdAt: DateTime.now(),
      elevationRangeMeters: elevationRange,
    );
  }
}
