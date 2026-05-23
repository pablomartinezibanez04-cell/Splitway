import 'package:flutter_test/flutter_test.dart';
import 'package:splitway_mobile/src/services/speed/speed_metric.dart';

void main() {
  group('SpeedMetric', () {
    test('id round-trips through fromId', () {
      for (final m in SpeedMetric.values) {
        expect(SpeedMetric.fromId(m.id), m);
      }
    });

    test('fromId returns null for unknown', () {
      expect(SpeedMetric.fromId('nonsense'), null);
    });

    test('isTimeBased is true for time metrics, false for topSpeed', () {
      expect(SpeedMetric.reactionTime.isTimeBased, true);
      expect(SpeedMetric.zeroTo100.isTimeBased, true);
      expect(SpeedMetric.quarterMile.isTimeBased, true);
      expect(SpeedMetric.topSpeed.isTimeBased, false);
    });

    test('formatValue prints seconds with 2 decimals', () {
      expect(SpeedMetric.zeroTo100.formatValue(5.234), '5.23 s');
      expect(SpeedMetric.zeroTo100.formatValue(null), '-');
    });

    test('formatValue prints top speed as integer km/h', () {
      expect(SpeedMetric.topSpeed.formatValue(187.4), '187 km/h');
      expect(SpeedMetric.topSpeed.formatValue(null), '-');
    });
  });
}
