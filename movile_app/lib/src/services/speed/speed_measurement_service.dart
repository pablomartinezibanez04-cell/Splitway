import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sensors_plus/sensors_plus.dart';

import 'speed_metric.dart';
import 'speed_sample.dart';

enum SpeedPhase { idle, armed, running, finished }

class FalseStartDetected {
  const FalseStartDetected();
}

/// Fuses GPS and IMU samples and resolves drag-strip milestones.
///
/// Live wiring lives in companion methods [liveArm], [liveStart], and
/// [liveStop]; tests use [SpeedMeasurementService.forTesting] together
/// with [debugInjectSample] to drive the state machine deterministically.
class SpeedMeasurementService {
  SpeedMeasurementService({required this.targets}) : _isTestMode = false;

  SpeedMeasurementService.forTesting({required this.targets})
      : _isTestMode = true;

  final Set<SpeedMetric> targets;
  final bool _isTestMode;

  static const double _sixtyFeetMeters = 18.29;
  static const double _eighthMileMeters = 201.168;
  static const double _quarterMileMeters = 402.336;

  static const double _reactionSpeedKmh = 0.5;
  static const double _reactionAccelMs2 = 1.0;
  static const Duration _reactionSustain = Duration(milliseconds: 100);

  static const double _falseStartSpeedKmh = 1.5;
  static const double _falseStartAccelMs2 = 1.5;
  static const Duration _falseStartSustain = Duration(milliseconds: 150);

  final ValueNotifier<Map<SpeedMetric, double?>> results =
      ValueNotifier(const {});
  final ValueNotifier<SpeedPhase> phase = ValueNotifier(SpeedPhase.idle);
  final ValueNotifier<double> instantaneousKmh = ValueNotifier(0);
  final ValueNotifier<Duration> elapsed = ValueNotifier(Duration.zero);
  final StreamController<FalseStartDetected> _falseStart =
      StreamController.broadcast();

  Stream<FalseStartDetected> get falseStartStream => _falseStart.stream;

  SpeedSample? _previousSample;
  Duration? _reactionCandidateTime;
  Duration? _falseStartCandidateTime;

  StreamSubscription<Position>? _gpsSub;
  StreamSubscription<AccelerometerEvent>? _accelSub;
  Stopwatch _sessionClock = Stopwatch();
  DateTime? _lastImuTickAt;
  double _liveSpeedKmh = 0;
  double _liveDistanceM = 0;
  double _liveAccelMs2 = 0;

  Future<void> liveArm() async {
    arm();
    _sessionClock = Stopwatch()..start();
    _lastImuTickAt = DateTime.now();
    _liveSpeedKmh = 0;
    _liveDistanceM = 0;
    _liveAccelMs2 = 0;
    await _subscribeSensors();
  }

  Future<void> liveStart() async {
    start();
    _liveDistanceM = 0;
    _sessionClock = Stopwatch()..start();
    _lastImuTickAt = DateTime.now();
    await _subscribeSensors();
  }

  Future<void> liveStop() async {
    await _gpsSub?.cancel();
    await _accelSub?.cancel();
    _gpsSub = null;
    _accelSub = null;
    _sessionClock.stop();
    if (phase.value != SpeedPhase.idle) stop();
  }

  Future<void> _subscribeSensors() async {
    await _gpsSub?.cancel();
    await _accelSub?.cancel();

    _gpsSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 0,
      ),
    ).listen((p) {
      if (p.speed >= 0) _liveSpeedKmh = p.speed * 3.6;
    });

    _accelSub = accelerometerEventStream().listen((e) {
      final now = DateTime.now();
      final last = _lastImuTickAt ?? now;
      final dt = now.difference(last).inMicroseconds / 1e6;
      _lastImuTickAt = now;
      if (dt <= 0 || dt > 0.5) return;
      // Magnitude of total acceleration vector minus gravity. Shaking the
      // phone produces values >> 1 m/s²; resting it gives ~0.
      final magnitude =
          math.sqrt(e.x * e.x + e.y * e.y + e.z * e.z);
      _liveAccelMs2 = math.max(0, magnitude - 9.81);
      // Integrate distance from current (GPS-resolved) speed.
      final gpsSpeedMs = _liveSpeedKmh / 3.6;
      _liveDistanceM += gpsSpeedMs * dt;
      _onSample(SpeedSample(
        tSinceStart:
            Duration(microseconds: _sessionClock.elapsedMicroseconds),
        speedKmh: _liveSpeedKmh,
        distanceM: _liveDistanceM,
        accelMs2: _liveAccelMs2,
      ));
    });
  }

  Future<void> disposeAsync() async {
    await _gpsSub?.cancel();
    await _accelSub?.cancel();
    _falseStart.close();
    results.dispose();
    phase.dispose();
    instantaneousKmh.dispose();
    elapsed.dispose();
  }

  void arm() {
    phase.value = SpeedPhase.armed;
    _resetResults();
    _previousSample = null;
    _falseStartCandidateTime = null;
  }

  void start() {
    phase.value = SpeedPhase.running;
    _resetResults();
    _previousSample = null;
    _reactionCandidateTime = null;
    elapsed.value = Duration.zero;
  }

  void stop() {
    phase.value = SpeedPhase.finished;
  }

  void cancel() {
    phase.value = SpeedPhase.idle;
  }

  void dispose() {
    _falseStart.close();
    results.dispose();
    phase.dispose();
    instantaneousKmh.dispose();
    elapsed.dispose();
  }

  @visibleForTesting
  void debugInjectSample(SpeedSample sample) {
    if (!_isTestMode) return;
    _onSample(sample);
  }

  void _resetResults() {
    results.value = {for (final t in targets) t: null};
  }

  void _onSample(SpeedSample s) {
    instantaneousKmh.value = s.speedKmh;
    switch (phase.value) {
      case SpeedPhase.armed:
        _checkFalseStart(s);
        break;
      case SpeedPhase.running:
        elapsed.value = s.tSinceStart;
        _detectMilestones(s);
        break;
      case SpeedPhase.idle:
      case SpeedPhase.finished:
        break;
    }
    _previousSample = s;
  }

  void _checkFalseStart(SpeedSample s) {
    final exceeded = s.speedKmh >= _falseStartSpeedKmh ||
        s.accelMs2 >= _falseStartAccelMs2;
    if (!exceeded) {
      _falseStartCandidateTime = null;
      return;
    }
    _falseStartCandidateTime ??= s.tSinceStart;
    final sustained = s.tSinceStart - _falseStartCandidateTime!;
    if (sustained >= _falseStartSustain) {
      _falseStart.add(const FalseStartDetected());
      phase.value = SpeedPhase.idle;
    }
  }

  void _detectMilestones(SpeedSample s) {
    final updated = Map<SpeedMetric, double?>.from(results.value);

    if (targets.contains(SpeedMetric.topSpeed)) {
      final current = updated[SpeedMetric.topSpeed] ?? 0;
      if (s.speedKmh > current) updated[SpeedMetric.topSpeed] = s.speedKmh;
    }

    if (targets.contains(SpeedMetric.reactionTime) &&
        updated[SpeedMetric.reactionTime] == null) {
      // Reaction triggers on either real GPS motion or a clear IMU spike,
      // whichever happens first. This lets the metric resolve even when
      // GPS lag is hiding the start of motion.
      final motion = s.speedKmh >= _reactionSpeedKmh ||
          s.accelMs2 >= _reactionAccelMs2;
      if (motion) {
        _reactionCandidateTime ??= s.tSinceStart;
        final sustained = s.tSinceStart - _reactionCandidateTime!;
        if (sustained >= _reactionSustain) {
          updated[SpeedMetric.reactionTime] =
              _reactionCandidateTime!.inMicroseconds / 1e6;
        }
      } else {
        _reactionCandidateTime = null;
      }
    }

    final prev = _previousSample;
    if (prev != null) {
      _resolveDistanceCrossing(
          updated, prev, s, SpeedMetric.sixtyFoot, _sixtyFeetMeters);
      _resolveDistanceCrossing(
          updated, prev, s, SpeedMetric.eighthMile, _eighthMileMeters);
      _resolveDistanceCrossing(
          updated, prev, s, SpeedMetric.quarterMile, _quarterMileMeters);
      _resolveSpeedCrossing(updated, prev, s, SpeedMetric.zeroTo50, 50);
      _resolveSpeedCrossing(updated, prev, s, SpeedMetric.zeroTo100, 100);
      _resolveSpeedCrossing(updated, prev, s, SpeedMetric.zeroTo200, 200);
    }

    if (!_mapEquals(updated, results.value)) {
      results.value = updated;
    }
  }

  void _resolveDistanceCrossing(
    Map<SpeedMetric, double?> out,
    SpeedSample prev,
    SpeedSample curr,
    SpeedMetric metric,
    double thresholdM,
  ) {
    if (!targets.contains(metric)) return;
    if (out[metric] != null) return;
    if (prev.distanceM < thresholdM && curr.distanceM >= thresholdM) {
      final ratio = (thresholdM - prev.distanceM) /
          (curr.distanceM - prev.distanceM);
      final dtMicros = curr.tSinceStart.inMicroseconds -
          prev.tSinceStart.inMicroseconds;
      final tMicros = prev.tSinceStart.inMicroseconds + ratio * dtMicros;
      out[metric] = tMicros / 1e6;
    }
  }

  void _resolveSpeedCrossing(
    Map<SpeedMetric, double?> out,
    SpeedSample prev,
    SpeedSample curr,
    SpeedMetric metric,
    double thresholdKmh,
  ) {
    if (!targets.contains(metric)) return;
    if (out[metric] != null) return;
    if (prev.speedKmh < thresholdKmh && curr.speedKmh >= thresholdKmh) {
      final ratio = (thresholdKmh - prev.speedKmh) /
          (curr.speedKmh - prev.speedKmh);
      final dtMicros = curr.tSinceStart.inMicroseconds -
          prev.tSinceStart.inMicroseconds;
      final tMicros = prev.tSinceStart.inMicroseconds + ratio * dtMicros;
      out[metric] = tMicros / 1e6;
    }
  }

  bool _mapEquals(
    Map<SpeedMetric, double?> a,
    Map<SpeedMetric, double?> b,
  ) {
    if (a.length != b.length) return false;
    for (final k in a.keys) {
      if (a[k] != b[k]) return false;
    }
    return true;
  }
}
