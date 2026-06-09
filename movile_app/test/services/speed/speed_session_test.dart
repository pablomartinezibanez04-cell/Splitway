import 'package:flutter_test/flutter_test.dart';
import 'package:splitway_mobile/src/services/speed/speed_metric.dart';
import 'package:splitway_mobile/src/services/speed/speed_session.dart';

void main() {
  group('SpeedSession', () {
    test('toJson and fromJson round-trip', () {
      final now = DateTime.parse('2026-05-22T10:30:00.000Z');
      final session = SpeedSession(
        id: 'abc',
        userId: 'u1',
        vehicleId: 'v1',
        name: 'My run',
        selectedMetrics: {SpeedMetric.zeroTo100, SpeedMetric.topSpeed},
        results: {SpeedMetric.zeroTo100: 5.23, SpeedMetric.topSpeed: 187.0},
        countdownSeconds: 3,
        isPartial: false,
        startedAt: now,
        finishedAt: now.add(const Duration(seconds: 30)),
        createdAt: now,
        updatedAt: now,
      );

      final back = SpeedSession.fromJson(session.toJson());
      expect(back.id, session.id);
      expect(back.selectedMetrics, session.selectedMetrics);
      expect(back.results[SpeedMetric.zeroTo100], 5.23);
      expect(back.countdownSeconds, 3);
      expect(back.isPartial, false);
    });

    test('defaultName uses vehicle name only', () {
      final ts = DateTime.parse('2026-05-22T14:08:09.000');
      final name = SpeedSession.defaultName('Civic Type R', ts);
      expect(name, 'Civic Type R');
    });
  });
}
