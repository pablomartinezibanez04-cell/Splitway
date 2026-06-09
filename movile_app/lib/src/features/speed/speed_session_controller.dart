import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../data/repositories/speed_repository.dart';
import '../../services/speed/beep_player.dart';
import '../../services/speed/speed_measurement_service.dart';
import '../../services/speed/speed_metric.dart';
import '../../services/speed/speed_session.dart';

enum SpeedScreenPhase {
  ready,
  arming,
  countdown,
  running,
  falseStart,
  finished,
}

class SpeedSessionController extends ChangeNotifier {
  SpeedSessionController({
    required this.userId,
    required this.vehicleId,
    required this.vehicleName,
    required this.metrics,
    required this.countdownSeconds,
    required this.userProvidedName,
    required this.repository,
  })  : service = SpeedMeasurementService(targets: metrics),
        beep = BeepPlayer();

  final String? userId;
  final String? vehicleId;
  final String vehicleName;
  final Set<SpeedMetric> metrics;
  final int countdownSeconds;
  final String? userProvidedName;
  final SpeedRepository repository;

  final SpeedMeasurementService service;
  final BeepPlayer beep;

  SpeedScreenPhase phase = SpeedScreenPhase.ready;
  int countdownValue = 0;
  DateTime? startedAt;
  DateTime? finishedAt;

  StreamSubscription<FalseStartDetected>? _falseStartSub;
  final List<Timer> _countdownTimers = [];
  bool _resultsListenerAttached = false;
  bool _disposed = false;

  Future<void> begin() async {
    await beep.preload();
    _falseStartSub = service.falseStartStream.listen((_) {
      _onFalseStart();
    });
    await _arm();
  }

  Future<void> _arm() async {
    phase = SpeedScreenPhase.arming;
    countdownValue = countdownSeconds;
    notifyListeners();
    await service.liveArm();
    if (_disposed) return;
    phase = SpeedScreenPhase.countdown;
    notifyListeners();
    _startCountdown();
  }

  void _startCountdown() {
    _cancelCountdownTimers();
    final origin = DateTime.now();
    for (var i = 0; i < countdownSeconds; i++) {
      final step = i;
      final target = origin.add(Duration(seconds: step + 1));
      final delay = target.difference(DateTime.now());
      _countdownTimers.add(Timer(delay, () {
        if (_disposed) return;
        beep.tick();
        countdownValue = countdownSeconds - step - 1;
        notifyListeners();
        if (countdownValue == 0) {
          beep.go();
          _go();
        }
      }));
    }
  }

  void _cancelCountdownTimers() {
    for (final t in _countdownTimers) {
      t.cancel();
    }
    _countdownTimers.clear();
  }

  Future<void> _go() async {
    if (_disposed) return;
    startedAt = DateTime.now();
    phase = SpeedScreenPhase.running;
    notifyListeners();
    await service.liveStop();
    await service.liveStart();
    if (!_resultsListenerAttached) {
      service.results.addListener(_maybeFinish);
      _resultsListenerAttached = true;
    }
  }

  void _maybeFinish() {
    if (_disposed) return;
    final allResolved =
        metrics.every((m) => service.results.value[m] != null);
    if (allResolved) {
      _finish();
    }
    notifyListeners();
  }

  Future<void> _finish() async {
    if (_disposed) return;
    if (phase == SpeedScreenPhase.finished) return;
    finishedAt = DateTime.now();
    phase = SpeedScreenPhase.finished;
    await service.liveStop();
    notifyListeners();
  }

  Future<void> _onFalseStart() async {
    if (_disposed) return;
    _cancelCountdownTimers();
    await service.liveStop();
    beep.falseStart();
    phase = SpeedScreenPhase.falseStart;
    notifyListeners();
  }

  Future<void> retry() async {
    await _arm();
  }

  Future<void> manualStop() async {
    await _finish();
  }

  Future<SpeedSession> saveResult() async {
    final id = const Uuid().v4();
    final now = DateTime.now();
    final results = Map<SpeedMetric, double?>.from(service.results.value);
    final session = SpeedSession(
      id: id,
      userId: userId,
      vehicleId: vehicleId,
      name: userProvidedName ?? SpeedSession.defaultName(vehicleName, now),
      selectedMetrics: metrics,
      results: results,
      countdownSeconds: countdownSeconds,
      isPartial: !metrics.every((m) => results[m] != null),
      startedAt: startedAt ?? now,
      finishedAt: finishedAt ?? now,
      createdAt: now,
      updatedAt: now,
    );
    await repository.save(session);
    return session;
  }

  @override
  void dispose() {
    _disposed = true;
    _cancelCountdownTimers();
    _falseStartSub?.cancel();
    if (_resultsListenerAttached) {
      service.results.removeListener(_maybeFinish);
    }
    unawaited(service.disposeAsync());
    unawaited(beep.dispose());
    super.dispose();
  }
}
