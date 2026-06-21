import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:splitway_core/splitway_core.dart';

import '../../data/repositories/local_draft_repository.dart';
import '../../services/sensors/device_heading_service.dart';
import '../../services/tracking/live_tracking_controller.dart';
import '../../services/tracking/background_tracking_service.dart';
import '../../services/tracking/location_service.dart';

enum LiveSessionStage { selecting, ready, running, paused, summary, finished }

enum TrackingSource { simulated, realGps }

class LiveSessionController extends ChangeNotifier {
  LiveSessionController(
    this._repo, {
    DeviceHeadingService? headingService,
  }) : _headingService = headingService ?? DeviceHeadingService() {
    _changesSub = _repo.changes.listen((_) => _onRepoChanged());
  }

  final LocalDraftRepository _repo;
  StreamSubscription<void>? _changesSub;
  Timer? _reloadDebouncer;
  final DeviceHeadingService _headingService;
  StreamSubscription<double>? _headingSub;

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

  String? _selectedVehicleId;
  String? get selectedVehicleId => _selectedVehicleId;

  bool _backgroundActive = false;
  bool get backgroundActive => _backgroundActive;

  /// True while an automatic finish (open route reached its end) is in flight,
  /// so the detection in [_onTrackerChange] does not fire twice during the
  /// async [finishSession] await.
  bool _autoFinishing = false;

  /// Best recorded time per sector across the user's previous sessions on the
  /// selected route. Loaded when a session starts; drives the "purple"
  /// (all-time circuit record) sector colour. Empty when there is no history.
  Map<String, Duration> _historicalSectorRecords = const {};
  Map<String, Duration> get historicalSectorRecords => _historicalSectorRecords;

  /// Best completed-lap duration across the user's previous sessions on the
  /// selected route, or null when the user opted out (includeHistorical=false)
  /// or has no completed laps. Drives the closed-circuit reference lap.
  Duration? _historicalBestLap;
  Duration? get historicalBestLap => _historicalBestLap;

  /// Best total time across the user's previous sessions on the selected route
  /// (used for open routes, which have no laps). Loaded when the session starts
  /// and `includeHistorical` is true; null when there is no prior run.
  Duration? _historicalBestTotal;

  /// Reference time for an open route: the user's previous best total when they
  /// chose to compete against it and one exists, otherwise the route's normal
  /// (expected) time. Null when neither is available.
  Duration? get referenceDuration {
    if (_includeHistorical && _historicalBestTotal != null) {
      return _historicalBestTotal;
    }
    return _selected?.expectedDuration;
  }

  /// Whether this session competes against the user's historical best on the
  /// route. Set from the config modal when the session starts.
  bool _includeHistorical = true;
  bool get includeHistorical => _includeHistorical;

  /// Optional user-given name for the current session.
  String? _sessionName;

  void selectVehicle(String? vehicleId) {
    _selectedVehicleId = vehicleId;
    notifyListeners();
  }

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
  Timer? _bgNotificationTicker;
  int _distanceFilterMeters = 0;

  /// When false (recording in a motorized vehicle) the compass /
  /// accelerometer sensors are never started and the camera bearing comes
  /// from the GPS course alone.
  bool _useCompassHeading = true;

  /// Latest known heading in degrees (0 = north, clockwise). In a motorized
  /// vehicle the GPS course is used directly. Otherwise it blends the
  /// phone's magnetic compass (so the camera rotates when the user turns
  /// the device) with the GPS-derived course (so it snaps to direction of
  /// travel when actually moving). At standstill the compass wins; above
  /// ~4 m/s the GPS course wins.
  double? get currentBearingDeg {
    final gpsCourse = _gpsCourseDeg();
    if (!_useCompassHeading) return gpsCourse;
    final compass = _headingService.currentHeadingDeg;
    final speed = _tracker?.snapshot.lastSpeedMps ?? 0.0;
    return fusedBearingDeg(
      compassDeg: compass,
      gpsCourseDeg: gpsCourse,
      speedMps: speed,
    );
  }

  double? _gpsCourseDeg() {
    final t = _tracker;
    if (t == null || t.ingested.isEmpty) return null;
    final last = t.ingested.last;
    final reported = last.bearingDeg;
    if (reported != null && reported >= 0) return reported;
    if (t.ingested.length < 2) return null;
    final prev = t.ingested[t.ingested.length - 2];
    if (prev.location.distanceTo(last.location) < 1.0) return null;
    return prev.location.bearingTo(last.location);
  }

  Future<void> load() async {
    _routes = await _repo.getAllRoutes();
    if (_selected != null) {
      final updated = _routes.where((r) => r.id == _selected!.id).firstOrNull;
      _selected = updated;
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

  Future<void> startSession({
    int distanceFilterMeters = 0,
    bool backgroundActive = false,
    bool useCompassHeading = true,
    bool includeHistorical = true,
    String? name,
  }) async {
    final route = _selected;
    if (route == null) return;
    _distanceFilterMeters = distanceFilterMeters;
    _useCompassHeading = useCompassHeading;
    _includeHistorical = includeHistorical;
    _sessionName = (name != null && name.trim().isNotEmpty) ? name.trim() : null;
    if (includeHistorical) {
      try {
        final sessions = await _repo.getSessionsByRoute(route.id);
        _historicalSectorRecords = _bestSectorRecords(sessions);
        _historicalBestLap = _bestHistoricalLap(sessions);
        _historicalBestTotal = _bestHistoricalTotal(sessions);
      } catch (_) {
        _historicalSectorRecords = const {};
        _historicalBestLap = null;
        _historicalBestTotal = null;
      }
    } else {
      _historicalSectorRecords = const {};
      _historicalBestLap = null;
      _historicalBestTotal = null;
    }
    _tracker?.dispose();
    _tracker = LiveTrackingController(route: route)
      ..addListener(_onTrackerChange)
      ..startSession();
    _stage = LiveSessionStage.running;
    _subscribeToHeading();
    notifyListeners();

    if (_source == TrackingSource.realGps) {
      _backgroundActive = backgroundActive;

      if (_backgroundActive) {
        await BackgroundTrackingService.startTracking(
          title: 'Splitway · Grabando ruta',
          body: '0.0 km · 00:00:00',
        );
        _startBgNotificationTicker();
      }

      _subscribeToGps();
    }
  }

  /// Computes the best (minimum) recorded duration per sector across [sessions]
  /// (the user's previous sessions on the route).
  Map<String, Duration> _bestSectorRecords(List<SessionRun> sessions) {
    final records = <String, Duration>{};
    for (final session in sessions) {
      for (final sector in session.sectorSummaries) {
        final current = records[sector.sectorId];
        if (current == null || sector.duration < current) {
          records[sector.sectorId] = sector.duration;
        }
      }
    }
    return records;
  }

  /// Minimum completed-lap duration across [sessions], or null when none has a
  /// completed lap. Drives the closed-circuit reference lap.
  Duration? _bestHistoricalLap(List<SessionRun> sessions) {
    Duration? best;
    for (final session in sessions) {
      final lap = session.bestLap;
      if (lap == null) continue;
      if (best == null || lap.duration < best) best = lap.duration;
    }
    return best;
  }

  /// Minimum total run duration across [sessions]; null when none has one.
  Duration? _bestHistoricalTotal(List<SessionRun> sessions) {
    Duration? best;
    for (final session in sessions) {
      final d = session.totalDuration;
      if (d == null) continue;
      if (best == null || d < best) best = d;
    }
    return best;
  }

  void _subscribeToHeading() {
    if (!_useCompassHeading) return;
    _headingService.start();
    _headingSub?.cancel();
    _headingSub = _headingService.headingStream.listen((_) {
      // Phone heading changed — notify the UI so the camera can rotate
      // even when no new GPS sample has arrived.
      notifyListeners();
    });
  }

  void _unsubscribeFromHeading() {
    _headingSub?.cancel();
    _headingSub = null;
    _headingService.stop();
  }

  void _subscribeToGps() {
    _gpsSub = LocationService.positionStream(
      distanceFilterMeters: _distanceFilterMeters,
      backgroundMode: _backgroundActive,
    ).listen((p) {
      _tracker?.ingestSimulatedPoint(p);
      notifyListeners();
    }, onError: (_) {
      // Fall back to simulated so the user can still finish the run.
      _source = TrackingSource.simulated;
      notifyListeners();
    });
  }

  /// Pause an in-progress session. GPS samples are dropped while paused.
  void pauseSession() {
    if (_stage != LiveSessionStage.running) return;
    _stage = LiveSessionStage.paused;
    _gpsSub?.cancel();
    _gpsSub = null;
    _autoSimulator?.cancel();
    _autoSimulator = null;
    _unsubscribeFromHeading();
    notifyListeners();
  }

  /// Resume a paused session.
  void resumeSession() {
    if (_stage != LiveSessionStage.paused) return;
    _stage = LiveSessionStage.running;
    if (_source == TrackingSource.realGps) {
      _subscribeToGps();
    }
    _subscribeToHeading();
    notifyListeners();
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
    _bgNotificationTicker?.cancel();
    _bgNotificationTicker = null;
    if (_backgroundActive) {
      await BackgroundTrackingService.stopTracking();
      _backgroundActive = false;
    }
    _autoSimulator?.cancel();
    _autoSimulator = null;
    _unsubscribeFromHeading();
    final t = _tracker;
    if (t == null) return null;
    final raw = t.finishSession();
    final session = raw.copyWith(vehicleId: _selectedVehicleId, name: _sessionName);
    await _repo.saveSessionRun(session);
    _result = session;
    // Open routes pause on a finish overlay (frozen map + summary) before the
    // results screen; closed routes go straight to results as before.
    _stage = t.route.isClosed
        ? LiveSessionStage.finished
        : LiveSessionStage.summary;
    notifyListeners();
    return session;
  }

  /// Advances from the finish overlay (open routes) to the results screen.
  void dismissFinishOverlay() {
    if (_stage != LiveSessionStage.summary) return;
    _stage = LiveSessionStage.finished;
    notifyListeners();
  }

  void resetForNewSession() {
    _tracker?.removeListener(_onTrackerChange);
    _tracker?.dispose();
    _tracker = null;
    _autoIndex = 0;
    _autoScript = const [];
    _result = null;
    _autoFinishing = false;
    _backgroundActive = false;
    _historicalSectorRecords = const {};
    _historicalBestLap = null;
    _historicalBestTotal = null;
    _sessionName = null;
    _stage = _selected == null
        ? LiveSessionStage.selecting
        : LiveSessionStage.ready;
    notifyListeners();
  }

  /// Hot-upgrade from foreground-only to background tracking mid-session.
  /// Called when the user grants 'always' permission via OS settings and
  /// returns to the app.
  Future<void> upgradeToBackground() async {
    if (_backgroundActive || _stage != LiveSessionStage.running) return;
    if (_source != TrackingSource.realGps) return;

    final permission = await LocationService.ensureBackgroundPermission();
    if (permission != LocationPermissionStatus.granted) return;

    _backgroundActive = true;

    await BackgroundTrackingService.startTracking(
      title: 'Splitway · Grabando ruta',
      body: '0.0 km · 00:00:00',
    );
    _startBgNotificationTicker();

    // Restart the GPS stream with background mode enabled.
    await _gpsSub?.cancel();
    _subscribeToGps();

    notifyListeners();
  }

  void _startBgNotificationTicker() {
    _bgNotificationTicker?.cancel();
    _bgNotificationTicker = Timer.periodic(
      const Duration(seconds: 1),
      (_) {
        if (!_backgroundActive) return;
        final snap = _tracker?.snapshot;
        if (snap == null) return;
        final distKm =
            (snap.totalDistanceMeters / 1000).toStringAsFixed(1);
        BackgroundTrackingService.updateNotification(
          distance: '$distKm km',
          time: _formatElapsed(snap.currentLapElapsed),
        );
      },
    );
  }

  void _onTrackerChange() {
    final t = _tracker;
    // Open routes auto-finish in the tracker on proximity to the last path
    // point. When that happens mid-session, finalize the session exactly as
    // the manual "Finish" button would.
    if (t != null &&
        !_autoFinishing &&
        t.state == LiveControllerState.finished &&
        (_stage == LiveSessionStage.running ||
            _stage == LiveSessionStage.paused)) {
      _autoFinishing = true;
      // Fire-and-forget: we cannot await inside a listener. If persistence
      // fails, reset the guard and notify so the session isn't left silently
      // wedged in `running` — the user can still retry via the Finish button
      // (which re-runs finishSession against the already-finished tracker).
      // ignore: discarded_futures
      finishSession().catchError((Object _) {
        _autoFinishing = false;
        notifyListeners();
        return null;
      });
    }
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
    _changesSub?.cancel();
    _reloadDebouncer?.cancel();
    _gpsSub?.cancel();
    _autoSimulator?.cancel();
    _tracker?.removeListener(_onTrackerChange);
    _tracker?.dispose();
    _bgNotificationTicker?.cancel();
    _headingSub?.cancel();
    _headingService.dispose();
    if (_backgroundActive) {
      BackgroundTrackingService.stopTracking();
    }
    super.dispose();
  }
}
