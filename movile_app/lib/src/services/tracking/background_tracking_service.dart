import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

class BackgroundTrackingService {
  BackgroundTrackingService._();

  static bool _running = false;
  static bool get isRunning => _running;

  /// Guards [startTracking] against re-entrancy across its `await`: a second
  /// call while a start is in flight must not invoke the service again.
  static bool _starting = false;

  static DateTime? _lastUpdate;
  static const _throttleDuration = Duration(seconds: 2);

  @visibleForTesting
  static VoidCallback? onUpdateForTest;

  /// Test seam for [startTracking]: when set, the service starter is replaced
  /// by this function (regardless of platform) so concurrency can be asserted.
  @visibleForTesting
  static Future<bool> Function({required String title, required String body})?
      startOverrideForTest;

  static void init() {
    if (!Platform.isAndroid) return;
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'splitway_tracking',
        channelName: 'Splitway Tracking',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
      ),
      iosNotificationOptions: const IOSNotificationOptions(),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
        autoRunOnBoot: false,
        autoRunOnMyPackageReplaced: false,
        allowWakeLock: true,
        allowWifiLock: false,
      ),
    );
  }

  static Future<bool> startTracking({
    required String title,
    required String body,
  }) async {
    if (_running) return true;
    // Re-entrancy guard: set synchronously before the first `await` so a
    // second near-simultaneous call short-circuits instead of starting the
    // service twice.
    if (_starting) return true;
    _starting = true;
    try {
      final override = startOverrideForTest;
      if (override != null) {
        _running = await override(title: title, body: body);
        return _running;
      }
      if (!Platform.isAndroid) {
        _running = true;
        return true;
      }
      try {
        final result = await FlutterForegroundTask.startService(
          serviceId: 256,
          notificationTitle: title,
          notificationText: body,
          callback: _taskCallback,
        );
        if (result is ServiceRequestSuccess) {
          _running = true;
        } else if (result is ServiceRequestFailure &&
            result.error is ServiceAlreadyStartedException) {
          // Service survived a hot-reload or app kill without a clean stop.
          // Adopt the orphaned service and reset its notification content.
          _running = true;
          FlutterForegroundTask.updateService(
            notificationTitle: title,
            notificationText: body,
          );
        } else {
          debugPrint(
              'BackgroundTrackingService.startTracking failed: ${(result as ServiceRequestFailure).error}');
        }
        return _running;
      } catch (e) {
        debugPrint('BackgroundTrackingService.startTracking failed: $e');
        return false;
      }
    } finally {
      _starting = false;
    }
  }

  static void updateNotification({
    required String distance,
    required String time,
  }) {
    if (!_running) return;

    final now = DateTime.now();
    if (_lastUpdate != null &&
        now.difference(_lastUpdate!) < _throttleDuration) {
      return;
    }
    _lastUpdate = now;

    if (onUpdateForTest != null) {
      onUpdateForTest!();
      return;
    }

    if (!Platform.isAndroid) return;
    FlutterForegroundTask.updateService(
      notificationText: '$distance · $time',
    );
  }

  static Future<void> stopTracking() async {
    if (!_running) return;
    _running = false;
    _lastUpdate = null;
    if (!Platform.isAndroid) return;
    try {
      await FlutterForegroundTask.stopService();
    } catch (e) {
      debugPrint('BackgroundTrackingService.stopTracking failed: $e');
    }
  }

  @visibleForTesting
  static void resetForTest() {
    _running = false;
    _starting = false;
    _lastUpdate = null;
    onUpdateForTest = null;
    startOverrideForTest = null;
  }

  @visibleForTesting
  static void setRunningForTest(bool value) {
    _running = value;
    _lastUpdate = null;
  }
}

@pragma('vm:entry-point')
void _taskCallback() {
  // The foreground service keeps the Flutter engine alive.
  // GPS streaming and notification updates happen in the main isolate
  // via the controllers, so this callback is intentionally empty.
}
