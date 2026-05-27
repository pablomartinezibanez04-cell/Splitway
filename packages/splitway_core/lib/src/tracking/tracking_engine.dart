import 'dart:async';

import '../models/lap_summary.dart';
import '../models/route_template.dart';
import '../models/sector_definition.dart';
import '../models/sector_summary.dart';
import '../models/session_run.dart';
import '../models/telemetry_point.dart';
import '../models/tracking_snapshot.dart';

sealed class TrackingEvent {
  const TrackingEvent(this.at);
  final DateTime at;
}

class TrackingStarted extends TrackingEvent {
  const TrackingStarted(super.at);
}

class SectorCrossed extends TrackingEvent {
  const SectorCrossed({
    required DateTime at,
    required this.sectorId,
    required this.lapNumber,
    required this.duration,
  }) : super(at);

  final String sectorId;
  final int lapNumber;
  final Duration duration;
}

class LapClosed extends TrackingEvent {
  const LapClosed({
    required DateTime at,
    required this.lap,
  }) : super(at);

  final LapSummary lap;
}

class TrackingFinished extends TrackingEvent {
  const TrackingFinished(super.at);
}

class TrackingEngine {
  TrackingEngine({
    required RouteTemplate route,
    required String sessionId,
    DateTime Function()? clock,
  })  : _route = route,
        _sessionId = sessionId,
        _clock = clock ?? DateTime.now;

  final RouteTemplate _route;
  final String _sessionId;
  final DateTime Function() _clock;

  final StreamController<TrackingEvent> _events =
      StreamController<TrackingEvent>.broadcast();
  Stream<TrackingEvent> get events => _events.stream;

  final List<TelemetryPoint> _points = [];
  final List<LapSummary> _laps = [];
  final List<SectorSummary> _sectorSummaries = [];

  TrackingStatus _status = TrackingStatus.idle;
  TelemetryPoint? _previous;
  DateTime? _lapStartedAt;
  DateTime? _lastSectorAt;
  int _currentLap = 0;
  int _nextSectorIndex = 0;
  double _totalDistanceMeters = 0;
  double _maxSpeedMps = 0;
  double _lastSpeedMps = 0;
  double _lapDistanceAccumulator = 0;
  double _sectorDistanceAccumulator = 0;
  Duration? _bestLap;
  DateTime? _lastCrossingAt;
  DateTime? _finishedAt;
  String? _lastCrossedSectorId;
  Duration? _lastSectorTime;

  /// Minimum time between two recognised start/finish crossings.
  /// Prevents double-counting from GPS noise or rapid simulation steps.
  static const _crossingCooldown = Duration(seconds: 3);

  /// Maximum distance (in meters) from the last path point to trigger
  /// an automatic finish on open (non-closed) routes.
  static const _finishProximityMeters = 20.0;

  /// Minimum distance (in meters) an incomplete lap must cover to be saved.
  /// Prevents recording a phantom lap when the session ends right after
  /// crossing the start/finish gate.
  static const _minIncompleteLapMeters = 50.0;

  static const _gapThreshold = Duration(seconds: 5);
  static const _recoveryDuration = Duration(seconds: 3);
  DateTime? _recoveringUntil;

  TrackingSnapshot get snapshot {
    final lapElapsed = _lapStartedAt == null
        ? Duration.zero
        : _clock().difference(_lapStartedAt!);
    return TrackingSnapshot(
      status: _status,
      currentLap: _currentLap,
      currentLapElapsed: lapElapsed,
      totalDistanceMeters: _totalDistanceMeters,
      lastSpeedMps: _lastSpeedMps,
      lastCrossedSectorId: _lastCrossedSectorId,
      lastSectorTime: _lastSectorTime,
      bestLap: _bestLap,
    );
  }

  /// Begins tracking. The next ingested point is the baseline; the first
  /// crossing of the start/finish gate opens lap 1.
  void start() {
    if (_status != TrackingStatus.idle) return;
    _status = TrackingStatus.awaitingStart;
    _lastCrossingAt = null;   // ensure cooldown does not carry over on engine reuse
  }

  void ingest(TelemetryPoint point) {
    if (_status == TrackingStatus.idle ||
        _status == TrackingStatus.finished) {
      return;
    }
    _points.add(point);

    final prev = _previous;
    if (prev == null) {
      _previous = point;
      return;
    }

    if (point.timestamp.difference(prev.timestamp) >= _gapThreshold) {
      _recoveringUntil = point.timestamp.add(_recoveryDuration);
      _previous = point;
      return;
    }

    if (_recoveringUntil != null) {
      if (point.timestamp.isBefore(_recoveringUntil!)) {
        _previous = point;
        return;
      }
      _recoveringUntil = null;
    }

    _lastSpeedMps = point.speedMps ?? _lastSpeedMps;

    final stepDistance = prev.location.distanceTo(point.location);
    _totalDistanceMeters += stepDistance;
    _lapDistanceAccumulator += stepDistance;
    _sectorDistanceAccumulator += stepDistance;
    if ((point.speedMps ?? 0) > _maxSpeedMps) {
      _maxSpeedMps = point.speedMps!;
    }

    if (_route.startFinishGate.crossedBy(prev.location, point.location)) {
      _onStartFinishCrossed(point.timestamp);
    } else if (_status == TrackingStatus.inLap &&
        _nextSectorIndex < _orderedSectors.length) {
      final sector = _orderedSectors[_nextSectorIndex];
      if (sector.gate.crossedBy(prev.location, point.location)) {
        _onSectorCrossed(sector, point.timestamp);
      }
    }

    // Open route finish: check proximity to the last path point.
    if (!_route.isClosed &&
        _status == TrackingStatus.inLap &&
        _route.path.length >= 2) {
      final finish = _route.path.last;
      if (point.location.distanceTo(finish) <= _finishProximityMeters) {
        _finishOpenRoute(point.timestamp);
      }
    }

    _previous = point;
  }

  /// Closes the current state and returns the recorded session.
  /// Safe to call multiple times — subsequent calls return the same snapshot.
  SessionRun finish() {
    if (_status == TrackingStatus.finished) {
      return _buildSession(endedAt: _finishedAt);
    }
    final endedAt = _clock();
    // Only record an incomplete lap for closed routes if enough distance
    // was covered. This avoids saving a phantom lap when the session ends
    // right after crossing the start/finish gate.
    if (_route.isClosed &&
        _status == TrackingStatus.inLap &&
        _lapStartedAt != null &&
        _lapDistanceAccumulator >= _minIncompleteLapMeters) {
      _laps.add(_buildLap(
        endedAt: endedAt,
        completed: false,
      ));
    }
    _finishedAt = endedAt;
    _status = TrackingStatus.finished;
    _events.add(TrackingFinished(endedAt));
    return _buildSession(endedAt: endedAt);
  }

  Future<void> dispose() async {
    await _events.close();
  }

  // ---------- internals ----------

  List<SectorDefinition> get _orderedSectors {
    final list = [..._route.sectors]..sort((a, b) => a.order.compareTo(b.order));
    return list;
  }

  void _onStartFinishCrossed(DateTime at) {
    // Cooldown: ignore crossings that arrive too soon after the previous one.
    final last = _lastCrossingAt;
    // Covers both too-soon crossings and out-of-order timestamps (negative difference).
    if (last != null && at.difference(last) < _crossingCooldown) return;
    _lastCrossingAt = at;

    if (_status == TrackingStatus.awaitingStart) {
      _status = TrackingStatus.inLap;
      _currentLap = 1;
      _lapStartedAt = at;
      _lastSectorAt = at;
      _nextSectorIndex = 0;
      _lapDistanceAccumulator = 0;
      _sectorDistanceAccumulator = 0;
      _events.add(TrackingStarted(at));
      return;
    }
    if (_status == TrackingStatus.inLap && _lapStartedAt != null) {
      // Open routes have no laps — ignore subsequent start/finish crossings.
      if (!_route.isClosed) return;

      final closed = _buildLap(endedAt: at, completed: true);
      _laps.add(closed);
      if (_bestLap == null || closed.duration < _bestLap!) {
        _bestLap = closed.duration;
      }
      _events.add(LapClosed(at: at, lap: closed));
      _currentLap += 1;
      _lapStartedAt = at;
      _lastSectorAt = at;
      _nextSectorIndex = 0;
      _lapDistanceAccumulator = 0;
      _sectorDistanceAccumulator = 0;
    }
  }

  /// Automatically finishes the session for open routes (e.g. when the rider
  /// reaches the last path point).
  void _finishOpenRoute(DateTime at) {
    _finishedAt = at;
    _status = TrackingStatus.finished;
    _events.add(TrackingFinished(at));
  }

  void _onSectorCrossed(SectorDefinition sector, DateTime at) {
    final since = _lastSectorAt ?? _lapStartedAt ?? at;
    final duration = at.difference(since);
    final avgSpeed = duration.inMilliseconds == 0
        ? 0.0
        : _sectorDistanceAccumulator / (duration.inMilliseconds / 1000.0);
    final summary = SectorSummary(
      sectorId: sector.id,
      lapNumber: _currentLap,
      duration: duration,
      startedAt: since,
      endedAt: at,
      distanceMeters: _sectorDistanceAccumulator,
      avgSpeedMps: avgSpeed,
    );
    _sectorSummaries.add(summary);
    _lastCrossedSectorId = sector.id;
    _lastSectorTime = duration;
    _lastSectorAt = at;
    _sectorDistanceAccumulator = 0;
    _nextSectorIndex += 1;
    _events.add(SectorCrossed(
      at: at,
      sectorId: sector.id,
      lapNumber: _currentLap,
      duration: duration,
    ));
  }

  LapSummary _buildLap({required DateTime endedAt, required bool completed}) {
    final start = _lapStartedAt!;
    final duration = endedAt.difference(start);
    final avgSpeed = duration.inMilliseconds == 0
        ? 0.0
        : _lapDistanceAccumulator / (duration.inMilliseconds / 1000.0);
    return LapSummary(
      lapNumber: _currentLap,
      duration: duration,
      startedAt: start,
      endedAt: endedAt,
      distanceMeters: _lapDistanceAccumulator,
      avgSpeedMps: avgSpeed,
      completed: completed,
    );
  }

  SessionRun _buildSession({DateTime? endedAt}) {
    final firstTs = _points.isNotEmpty ? _points.first.timestamp : _clock();
    final lastTs = endedAt ?? (_points.isNotEmpty ? _points.last.timestamp : firstTs);
    final totalSeconds = lastTs.difference(firstTs).inMilliseconds / 1000.0;
    final avgSpeed =
        totalSeconds <= 0 ? 0.0 : _totalDistanceMeters / totalSeconds;
    return SessionRun(
      id: _sessionId,
      routeTemplateId: _route.id,
      startedAt: firstTs,
      endedAt: lastTs,
      status: SessionStatus.completed,
      points: List.unmodifiable(_points),
      laps: List.unmodifiable(_laps),
      sectorSummaries: List.unmodifiable(_sectorSummaries),
      totalDistanceMeters: _totalDistanceMeters,
      maxSpeedMps: _maxSpeedMps,
      avgSpeedMps: avgSpeed,
    );
  }
}
