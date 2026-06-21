import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:splitway_core/splitway_core.dart';
import 'package:uuid/uuid.dart';

enum LiveControllerState { idle, recording, finished }

class LiveTrackingController extends ChangeNotifier {
  LiveTrackingController({required RouteTemplate route, String? sessionId})
      : this._(route: route, sessionId: sessionId ?? const Uuid().v4());

  // Generate the session id exactly once and share it between the public
  // field and the engine — otherwise a null sessionId produced two different
  // ids, and the engine's (which becomes SessionRun.id) silently won.
  LiveTrackingController._({required this.route, required this.sessionId})
      : _engine = TrackingEngine(route: route, sessionId: sessionId);

  final RouteTemplate route;
  final String sessionId;
  final TrackingEngine _engine;

  LiveControllerState _state = LiveControllerState.idle;
  LiveControllerState get state => _state;

  TrackingSnapshot _snapshot = TrackingSnapshot.initial;
  TrackingSnapshot get snapshot => _snapshot;

  final List<TrackingEvent> _events = [];
  List<TrackingEvent> get events => List.unmodifiable(_events);

  final List<TelemetryPoint> _ingested = [];
  List<TelemetryPoint> get ingested => List.unmodifiable(_ingested);

  /// The in-route trail — telemetry recorded between the first node crossing and
  /// the finish. Drives the drawn estela; `ingested` (all points) still drives
  /// the user marker, camera and bearing.
  List<TelemetryPoint> get trailPoints => _engine.recordedPoints;

  /// All sector crossings recorded so far this session, across every lap.
  List<SectorSummary> get sectorSummaries => _engine.sectorSummaries;

  StreamSubscription<TrackingEvent>? _eventSub;
  Timer? _ticker;

  void startSession() {
    if (_state != LiveControllerState.idle) return;
    _engine.start();
    _state = LiveControllerState.recording;
    _eventSub = _engine.events.listen((evt) {
      _events.add(evt);
      // Open routes auto-finish in the engine on proximity to the last path
      // point. Mirror that here so listeners (LiveSessionController) can react.
      if (evt is TrackingFinished && _state == LiveControllerState.recording) {
        _state = LiveControllerState.finished;
        _ticker?.cancel();
        _ticker = null;
      }
      notifyListeners();
    });
    _ticker = Timer.periodic(const Duration(milliseconds: 100), (_) {
      _snapshot = _engine.snapshot;
      notifyListeners();
    });
    _snapshot = _engine.snapshot;
    notifyListeners();
  }

  /// Iter 1: feed simulated points (one per tap or scripted) so the engine
  /// can be exercised end-to-end without GPS hardware.
  void ingestSimulatedPoint(TelemetryPoint point) {
    if (_state != LiveControllerState.recording) return;
    _ingested.add(point);
    _engine.ingest(point);
    _snapshot = _engine.snapshot;
    notifyListeners();
  }

  /// Builds a synthetic telemetry script that drives [lapCount] complete laps
  /// around the route. Each point is spaced [intervalMs] ms apart.
  ///
  /// Guarantees:
  /// - Uses geometrically-correct approach points so the start/finish gate is
  ///   always crossed (never relies on gate.center, which lies on the gate line
  ///   and is rejected by the strict-intersection test).
  /// - Samples long road-snapped paths to at most [maxPathPoints] waypoints so
  ///   the simulation finishes in seconds rather than minutes.
  List<TelemetryPoint> buildAutoLapScript({
    required DateTime startTime,
    int lapCount = 1,
    double speedMps = 15.0,
    int intervalMs = 600,
    int maxPathPoints = 50,
  }) {
    final path = route.path;
    if (path.length < 3) return const [];

    // Sample the path so the script stays short even for snapped routes.
    final sampled = _samplePath(path, maxPathPoints);
    if (sampled.length < 2) return const []; // guard: _samplePath result too short

    // Gates in Splitway are auto-generated perpendicular to path[0]→path[1].
    // Therefore the forward path bearing IS the direction perpendicular to the gate,
    // and placing pBefore 20 m behind gate.center along the reverse bearing
    // guarantees that pBefore→sampled[1] will always cross the gate.
    //
    // Compute a point 20 m BEFORE the gate (guaranteed to be outside).
    // sampled[0] is the gate centre; sampled[1] is the first point inside the circuit.
    final fwdBearing = sampled.first.bearingTo(sampled[1]);
    final backBearing = (fwdBearing + 180) % 360;
    final pBefore = route.startFinishGate.center.destinationPoint(backBearing, 20);

    // Build point list: entry approach + N lap iterations.
    // Each iteration: [sampled[1]..sampled[-2], pBefore]
    //   - sampled[1] is inside (past the gate).
    //   - sampled[-2] is the last point before the gate centre (on the closing approach).
    //   - pBefore finishes outside, crossing the gate to close that lap.
    final geo = <GeoPoint>[];
    geo.add(pBefore); // entry: start outside so pBefore→sampled[1] opens lap 1.

    // Walk the circuit, skip index 0 (gate centre, on the gate line).
    // For closed circuits skip the last point too (= index 0, same issue).
    final isClosedCircuit = route.isClosed;
    final circuitPoints = isClosedCircuit
        ? sampled.skip(1).take(sampled.length - 2).toList() // skip first & last
        : sampled.skip(1).toList(); // skip only first

    for (int lap = 0; lap < lapCount; lap++) {
      geo.addAll(circuitPoints);
      // Close the lap: go back outside so the gate is crossed.
      geo.add(pBefore);
    }

    // Convert to TelemetryPoints.
    return [
      for (int i = 0; i < geo.length; i++)
        TelemetryPoint(
          timestamp: startTime.add(Duration(milliseconds: i * intervalMs)),
          location: geo[i],
          speedMps: speedMps,
        ),
    ];
  }

  /// Evenly samples [path] down to at most [max] points, always keeping
  /// the first and last point.
  static List<GeoPoint> _samplePath(List<GeoPoint> path, int max) {
    if (max <= 1) return path.isNotEmpty ? [path.first] : const [];
    if (path.length <= max) return List.of(path);
    final result = <GeoPoint>[];
    final step = (path.length - 1) / (max - 1);
    for (var i = 0; i < max; i++) {
      result.add(path[(i * step).round()]);
    }
    return result;
  }

  SessionRun finishSession() {
    if (_state == LiveControllerState.finished) {
      // Engine already finalized; rebuild a snapshot session.
      return _engine.finish();
    }
    final session = _engine.finish();
    _state = LiveControllerState.finished;
    _ticker?.cancel();
    _ticker = null;
    notifyListeners();
    return session;
  }

  @override
  Future<void> dispose() async {
    _ticker?.cancel();
    await _eventSub?.cancel();
    await _engine.dispose();
    super.dispose();
  }
}
