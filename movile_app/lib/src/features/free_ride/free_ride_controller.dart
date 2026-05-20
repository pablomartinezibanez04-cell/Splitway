// movile_app/lib/src/features/free_ride/free_ride_controller.dart
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:splitway_core/splitway_core.dart';

import '../../data/repositories/local_draft_repository.dart';
import '../../services/tracking/background_tracking_service.dart';
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

  String? _selectedVehicleId;
  String? get selectedVehicleId => _selectedVehicleId;

  bool _backgroundActive = false;
  bool get backgroundActive => _backgroundActive;

  void selectVehicle(String? vehicleId) {
    _selectedVehicleId = vehicleId;
    notifyListeners();
  }

  StreamSubscription<TelemetryPoint>? _gpsSub;
  Timer? _ticker;

  final List<TelemetryPoint> _ingested = [];
  List<TelemetryPoint> get ingested => List.unmodifiable(_ingested);

  FreeRideSnapshot get snapshot =>
      _engine?.snapshot ?? FreeRideSnapshot.initial;

  Future<void> startRecording({int distanceFilterMeters = 0}) async {
    _permissionStatus = await LocationService.ensurePermission();
    if (_permissionStatus != LocationPermissionStatus.granted) {
      notifyListeners();
      return;
    }

    final bgStatus = await LocationService.ensureBackgroundPermission();
    _backgroundActive = bgStatus == LocationPermissionStatus.granted;

    if (_backgroundActive) {
      await BackgroundTrackingService.startTracking(
        title: 'Splitway · Grabando ruta',
        body: '0.0 km · 00:00:00',
      );
    }

    final id = 'fr-${DateTime.now().microsecondsSinceEpoch}';
    _engine = FreeRideEngine(sessionId: id);
    _engine!.start();
    _ingested.clear();
    _stage = FreeRideStage.recording;
    notifyListeners();

    _gpsSub = LocationService.positionStream(
      distanceFilterMeters: distanceFilterMeters,
      backgroundMode: _backgroundActive,
    ).listen((point) {
      ingestPoint(point);
    }, onError: (_) {
      // GPS error — keep recording what we have.
    });

    _ticker = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (_backgroundActive) {
        final snap = snapshot;
        final distKm = (snap.totalDistanceMeters / 1000).toStringAsFixed(1);
        BackgroundTrackingService.updateNotification(
          distance: '$distKm km',
          time: _formatElapsed(snap.elapsed),
        );
      }
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

    if (_backgroundActive) {
      await BackgroundTrackingService.stopTracking();
      _backgroundActive = false;
    }

    final e = _engine;
    if (e == null) return null;
    final raw = e.finish();
    final run = raw.copyWith(vehicleId: _selectedVehicleId);
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
      elevationRangeMeters: run.elevationRangeMeters,
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
      vehicleId: run.vehicleId,
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
    _backgroundActive = false;
    _stage = FreeRideStage.idle;
    notifyListeners();
  }

  static String _formatElapsed(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  @override
  void dispose() {
    _gpsSub?.cancel();
    _ticker?.cancel();
    if (_backgroundActive) {
      BackgroundTrackingService.stopTracking();
    }
    super.dispose();
  }
}
