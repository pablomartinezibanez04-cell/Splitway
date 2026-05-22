import 'dart:async';

import 'package:flutter/foundation.dart';

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
  static const Duration _reactionSustain = Duration(milliseconds: 150);

  static const double _falseStartSpeedKmh = 1.5;
  static const double _falseStartAccelMs2 = 1.5;
  static const Duration _falseStartSustain = Duration(milliseconds: 150);

  final ValueNotifier<Map<SpeedMetric, double?>> results =
      ValueNotifier(const {});
  final ValueNotifier<SpeedPhase> phase = ValueNotifier(SpeedPhase.idle);
  final ValueNotifier<double> instantaneousKmh = ValueNotifier(0);
  final StreamController<FalseStartDetected> _falseStart =
      StreamController.broadcast();

  Stream<FalseStartDetected> get falseStartStream => _falseStart.stream;

  SpeedSample? _previousSample;
  Duration? _reactionCandidateTime;
  Duration? _falseStartCandidateTime;

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
      if (s.speedKmh >= _reactionSpeedKmh) {
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
