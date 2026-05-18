import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:splitway_core/splitway_core.dart';

import '../../data/repositories/local_draft_repository.dart';
import '../../services/tracking/live_tracking_controller.dart';
import '../../services/tracking/location_service.dart';

enum LiveSessionStage { selecting, ready, running, finished }

enum TrackingSource { simulated, realGps }

class LiveSessionController extends ChangeNotifier {
  LiveSessionController(this._repo) {
    _changesSub = _repo.changes.listen((_) => _onRepoChanged());
  }

  final LocalDraftRepository _repo;
  StreamSubscription<void>? _changesSub;
  Timer? _reloadDebouncer;

  LiveSessionStage _stage = LiveSessionStage.selecting;
  LiveSessionStage get stage => _stage;

  List<RouteTemplate> _routes = const [];
  List<RouteTemplate> get routes => _routes;

  RouteTemplate? _selected;
  RouteTemplate? get selected => _selected;

  LiveTrackingController? _tracker;
  LiveTrackingController? get tracker => _tracker;

  SessionRun? _result;
  SessionRun? get result => _result;

  TrackingSource _source = TrackingSource.simulated;
  TrackingSource get source => _source;

  LocationPermissionStatus? _permissionStatus;
  LocationPermissionStatus? get permissionStatus => _permissionStatus;

  Timer? _autoSimulator;
  int _autoIndex = 0;
  List<TelemetryPoint> _autoScript = const [];

  int _simSpeedMultiplier = 1;
  int get simSpeedMultiplier => _simSpeedMultiplier;

  Duration get _simInterval =>
      Duration(milliseconds: 600 ~/ _simSpeedMultiplier.clamp(1, 20));

  StreamSubscription<TelemetryPoint>? _gpsSub;

  Future<void> load() async {
    _routes = await _repo.getAllRoutes();
    if (_selected != null) {
      final stillExists = _routes.any((r) => r.id == _selected!.id);
      if (!stillExists) _selected = null;
    }
    _selected ??= _routes.isNotEmpty ? _routes.first : null;
    _stage =
        _selected != null ? LiveSessionStage.ready : LiveSessionStage.selecting;
    notifyListeners();
  }

  void _onRepoChanged() {
    if (_stage == LiveSessionStage.running ||
        _stage == LiveSessionStage.finished) {
      return;
    }
    _reloadDebouncer?.cancel();
    _reloadDebouncer = Timer(const Duration(milliseconds: 300), load);
  }

  void selectRoute(RouteTemplate route) {
    _selected = route;
    _stage = LiveSessionStage.ready;
    notifyListeners();
  }

  /// Switches between simulated and real-GPS sources. When picking real
  /// GPS, asks the OS for permission so the UI can show the resulting
  /// status before [startSession] is called.
  Future<void> setSource(TrackingSource source) async {
    _source = source;
    if (source == TrackingSource.realGps) {
      _permissionStatus = await LocationService.ensurePermission();
      // Permission denied/disabled — fall back to simulated so the UI
      // doesn't get stuck.
      if (_permissionStatus != LocationPermissionStatus.granted) {
        _source = TrackingSource.simulated;
      }
    } else {
      _permissionStatus = null;
    }
    notifyListeners();
  }

  Future<void> startSession() async {
    final route = _selected;
    if (route == null) return;
    _tracker?.dispose();
    _tracker = LiveTrackingController(route: route)
      ..addListener(_onTrackerChange)
      ..startSession();
    _stage = LiveSessionStage.running;
    notifyListeners();

    if (_source == TrackingSource.realGps) {
      _gpsSub = LocationService.positionStream().listen((p) {
        _tracker?.ingestSimulatedPoint(p);
        notifyListeners();
      }, onError: (_) {
        // Fall back to simulated so the user can still finish the run.
        _source = TrackingSource.simulated;
        notifyListeners();
      });
    }
  }

  void simulateOnePoint() {
    final t = _tracker;
    final route = _selected;
    if (t == null || route == null) return;
    if (_source == TrackingSource.realGps) return;
    final base = DateTime.now();
    if (_autoScript.isEmpty) {
      _autoScript = t.buildAutoLapScript(startTime: base);
      _autoIndex = 0;
    }
    if (_autoIndex >= _autoScript.length) return;
    final original = _autoScript[_autoIndex];
    final point = TelemetryPoint(
      timestamp: original.timestamp, // use script time so engine cooldown is speed-independent
      location: original.location,
      speedMps: original.speedMps,
    );
    t.ingestSimulatedPoint(point);
    _autoIndex++;
    notifyListeners();
  }

  void toggleAutoSimulate() {
    if (_source == TrackingSource.realGps) return;
    if (_autoSimulator != null) {
      _autoSimulator?.cancel();
      _autoSimulator = null;
      notifyListeners();
      return;
    }
    final t = _tracker;
    if (t == null) return;
    if (_autoScript.isEmpty) {
      _autoScript = t.buildAutoLapScript(startTime: DateTime.now());
      _autoIndex = 0;
    }
    _startAutoTimer();
    notifyListeners();
  }

  void _startAutoTimer() {
    final t = _tracker;
    if (t == null) return;
    _autoSimulator = Timer.periodic(_simInterval, (_) {
      if (_autoIndex >= _autoScript.length) {
        _autoSimulator?.cancel();
        _autoSimulator = null;
        notifyListeners();
        return;
      }
      final scripted = _autoScript[_autoIndex];
      final point = TelemetryPoint(
        timestamp: scripted.timestamp, // use script time so engine cooldown is speed-independent
        location: scripted.location,
        speedMps: scripted.speedMps,
      );
      t.ingestSimulatedPoint(point);
      _autoIndex++;
      notifyListeners();
    });
  }

  /// Sets the simulation playback speed multiplier (1, 5, or 10).
  /// If auto-simulate is currently running it is restarted at the new rate.
  void setSimSpeedMultiplier(int multiplier) {
    _simSpeedMultiplier = multiplier.clamp(1, 20);
    if (_autoSimulator != null) {
      _autoSimulator?.cancel();
      _autoSimulator = null;
      _startAutoTimer();
    }
    notifyListeners();
  }

  bool get isAutoSimulating => _autoSimulator != null;

  /// Current position in the auto-simulation script (number of points sent).
  int get simProgress => _autoIndex;

  /// Total number of points in the current auto-simulation script.
  int get simTotal => _autoScript.length;

  Future<SessionRun?> finishSession() async {
    await _gpsSub?.cancel();
    _gpsSub = null;
    _autoSimulator?.cancel();
    _autoSimulator = null;
    final t = _tracker;
    if (t == null) return null;
    final session = t.finishSession();
    await _repo.saveSessionRun(session);
    _result = session;
    _stage = LiveSessionStage.finished;
    notifyListeners();
    return session;
  }

  void resetForNewSession() {
    _tracker?.removeListener(_onTrackerChange);
    _tracker?.dispose();
    _tracker = null;
    _autoIndex = 0;
    _autoScript = const [];
    _result = null;
    _stage = _selected == null
        ? LiveSessionStage.selecting
        : LiveSessionStage.ready;
    notifyListeners();
  }

  void _onTrackerChange() => notifyListeners();

  @override
  void dispose() {
    _changesSub?.cancel();
    _reloadDebouncer?.cancel();
    _gpsSub?.cancel();
    _autoSimulator?.cancel();
    _tracker?.removeListener(_onTrackerChange);
    _tracker?.dispose();
    super.dispose();
  }
}
