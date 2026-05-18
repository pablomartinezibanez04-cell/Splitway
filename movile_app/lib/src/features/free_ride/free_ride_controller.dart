// movile_app/lib/src/features/free_ride/free_ride_controller.dart
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:splitway_core/splitway_core.dart';

import '../../data/repositories/local_draft_repository.dart';
import '../../services/tracking/location_service.dart';

enum FreeRideStage { idle, recording, finished }

class FreeRideController extends ChangeNotifier {
  FreeRideController(this._repo);

  final LocalDraftRepository _repo;

  FreeRideStage _stage = FreeRideStage.idle;
  FreeRideStage get stage => _stage;

  FreeRideEngine? _engine;
  FreeRideEngine? get engine => _engine;

  FreeRideRun? _result;
  FreeRideRun? get result => _result;

  LocationPermissionStatus? _permissionStatus;
  LocationPermissionStatus? get permissionStatus => _permissionStatus;

  StreamSubscription<TelemetryPoint>? _gpsSub;
  Timer? _ticker;

  final List<TelemetryPoint> _ingested = [];
  List<TelemetryPoint> get ingested => List.unmodifiable(_ingested);

  FreeRideSnapshot get snapshot =>
      _engine?.snapshot ?? FreeRideSnapshot.initial;

  Future<void> startRecording() async {
    _permissionStatus = await LocationService.ensurePermission();
    if (_permissionStatus != LocationPermissionStatus.granted) {
      notifyListeners();
      return;
    }

    final id = 'fr-${DateTime.now().microsecondsSinceEpoch}';
    _engine = FreeRideEngine(sessionId: id);
    _engine!.start();
    _ingested.clear();
    _stage = FreeRideStage.recording;
    notifyListeners();

    _gpsSub = LocationService.positionStream().listen((point) {
      ingestPoint(point);
    }, onError: (_) {
      // GPS error — keep recording what we have.
    });

    _ticker = Timer.periodic(const Duration(milliseconds: 500), (_) {
      notifyListeners();
    });
  }

  void ingestPoint(TelemetryPoint point) {
    if (_stage != FreeRideStage.recording) return;
    _engine?.ingest(point);
    _ingested.add(point);
    notifyListeners();
  }

  Future<FreeRideRun?> finishRecording() async {
    await _gpsSub?.cancel();
    _gpsSub = null;
    _ticker?.cancel();
    _ticker = null;

    final e = _engine;
    if (e == null) return null;
    final run = e.finish();
    await _repo.saveFreeRideRun(run);
    _result = run;
    _stage = FreeRideStage.finished;
    notifyListeners();
    return run;
  }

  Future<RouteTemplate?> saveAsRoute({
    required String name,
    String? description,
    RouteDifficulty difficulty = RouteDifficulty.medium,
    String? locationLabel,
  }) async {
    final run = _result;
    if (run == null || run.points.length < 2) return null;

    final path = run.points.map((p) => p.location).toList();
    final simplified =
        path.length > 200 ? simplifyPath(path, 5.0) : path;

    final gate = GateDefinition(
      left: simplified.first.destinationPoint(
        (simplified.first.bearingTo(simplified[1]) + 90) % 360,
        10,
      ),
      right: simplified.first.destinationPoint(
        (simplified.first.bearingTo(simplified[1]) - 90 + 360) % 360,
        10,
      ),
    );

    final route = RouteTemplate(
      id: 'rt-${DateTime.now().microsecondsSinceEpoch}',
      name: name,
      description: description,
      path: simplified,
      startFinishGate: gate,
      sectors: const [],
      difficulty: difficulty,
      createdAt: DateTime.now(),
      locationLabel: locationLabel ?? run.locationLabel,
    );

    await _repo.saveRouteTemplate(route);

    final session = SessionRun(
      id: 'sess-${DateTime.now().microsecondsSinceEpoch}',
      routeTemplateId: route.id,
      startedAt: run.startedAt,
      endedAt: run.endedAt,
      status: SessionStatus.completed,
      points: run.points,
      laps: const [],
      sectorSummaries: const [],
      totalDistanceMeters: run.totalDistanceMeters,
      maxSpeedMps: run.maxSpeedMps,
      avgSpeedMps: run.avgSpeedMps,
    );
    await _repo.saveSessionRun(session);

    await _repo.updateFreeRideMetadata(
      run.id,
      name: name,
      description: description,
      locationLabel: locationLabel,
    );

    return route;
  }

  void resetForNewRide() {
    _engine = null;
    _result = null;
    _ingested.clear();
    _permissionStatus = null;
    _stage = FreeRideStage.idle;
    notifyListeners();
  }

  @override
  void dispose() {
    _gpsSub?.cancel();
    _ticker?.cancel();
    super.dispose();
  }
}
