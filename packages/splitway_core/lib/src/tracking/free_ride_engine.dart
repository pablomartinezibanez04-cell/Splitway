import '../models/free_ride_run.dart';
import '../models/free_ride_snapshot.dart';
import '../models/telemetry_point.dart';

class FreeRideEngine {
  FreeRideEngine({
    required String sessionId,
    DateTime Function()? clock,
  })  : _sessionId = sessionId,
        _clock = clock ?? DateTime.now;

  final String _sessionId;
  final DateTime Function() _clock;

  static const _gapThreshold = Duration(seconds: 5);
  static const _recoveryDuration = Duration(seconds: 3);

  final List<TelemetryPoint> _points = [];

  FreeRideTrackingStatus _status = FreeRideTrackingStatus.idle;
  TelemetryPoint? _previous;
  DateTime? _recoveringUntil;
  double _totalDistanceMeters = 0;
  double _maxSpeedMps = 0;
  double _lastSpeedMps = 0;

  FreeRideSnapshot get snapshot {
    final elapsed = _points.length >= 2
        ? _points.last.timestamp.difference(_points.first.timestamp)
        : Duration.zero;
    final totalSeconds = elapsed.inMilliseconds / 1000.0;
    final avgSpeed =
        totalSeconds <= 0 ? 0.0 : _totalDistanceMeters / totalSeconds;

    return FreeRideSnapshot(
      status: _status,
      elapsed: elapsed,
      totalDistanceMeters: _totalDistanceMeters,
      currentSpeedMps: _lastSpeedMps,
      maxSpeedMps: _maxSpeedMps,
      avgSpeedMps: avgSpeed,
      pointCount: _points.length,
    );
  }

  void start() {
    if (_status != FreeRideTrackingStatus.idle) return;
    _status = FreeRideTrackingStatus.recording;
  }

  void ingest(TelemetryPoint point) {
    if (_status != FreeRideTrackingStatus.recording) return;

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

    if ((point.speedMps ?? 0) > _maxSpeedMps) {
      _maxSpeedMps = point.speedMps!;
    }

    _totalDistanceMeters += prev.location.distanceTo(point.location);
    _previous = point;
  }

  FreeRideRun finish() {
    if (_status == FreeRideTrackingStatus.finished) {
      return _buildRun();
    }
    _status = FreeRideTrackingStatus.finished;
    return _buildRun();
  }

  Future<void> dispose() async {}

  FreeRideRun _buildRun() {
    final startedAt =
        _points.isNotEmpty ? _points.first.timestamp : _clock();
    final endedAt =
        _points.isNotEmpty ? _points.last.timestamp : _clock();
    final totalSeconds =
        endedAt.difference(startedAt).inMilliseconds / 1000.0;
    final avgSpeed =
        totalSeconds <= 0 ? 0.0 : _totalDistanceMeters / totalSeconds;

    return FreeRideRun(
      id: _sessionId,
      startedAt: startedAt,
      endedAt: endedAt,
      status: FreeRideStatus.completed,
      points: List.unmodifiable(_points),
      totalDistanceMeters: _totalDistanceMeters,
      maxSpeedMps: _maxSpeedMps,
      avgSpeedMps: avgSpeed,
    );
  }
}
