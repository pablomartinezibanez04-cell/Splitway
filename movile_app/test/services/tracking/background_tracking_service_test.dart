import 'package:flutter_test/flutter_test.dart';
import 'package:splitway_mobile/src/services/tracking/background_tracking_service.dart';

void main() {
  group('BackgroundTrackingService', () {
    setUp(() {
      BackgroundTrackingService.resetForTest();
    });

    test('isRunning is false initially', () {
      expect(BackgroundTrackingService.isRunning, isFalse);
    });

    test('updateNotification throttles calls within 2 seconds', () {
      // Simulate running state
      BackgroundTrackingService.setRunningForTest(true);

      var callCount = 0;
      BackgroundTrackingService.onUpdateForTest = () => callCount++;

      BackgroundTrackingService.updateNotification(
        distance: '0.0 km',
        time: '00:00:00',
      );
      expect(callCount, 1);

      // Second call within 2s should be throttled
      BackgroundTrackingService.updateNotification(
        distance: '0.1 km',
        time: '00:00:01',
      );
      expect(callCount, 1);
    });

    test('updateNotification does nothing when not running', () {
      var callCount = 0;
      BackgroundTrackingService.onUpdateForTest = () => callCount++;

      BackgroundTrackingService.updateNotification(
        distance: '0.0 km',
        time: '00:00:00',
      );
      expect(callCount, 0);
    });
  });
}
