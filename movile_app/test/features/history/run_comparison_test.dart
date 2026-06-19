import 'package:flutter_test/flutter_test.dart';
import 'package:splitway_mobile/src/features/history/run_comparison.dart';

void main() {
  test('percent is negative when faster than expected', () {
    final pct = runDeltaPercent(
      expected: const Duration(seconds: 100),
      actual: const Duration(seconds: 80),
    );
    expect(pct, -20.0);
  });

  test('percent is positive when slower than expected', () {
    final pct = runDeltaPercent(
      expected: const Duration(seconds: 100),
      actual: const Duration(seconds: 110),
    );
    expect(pct, 10.0);
  });

  test('percent is null when expected is zero', () {
    expect(
      runDeltaPercent(
          expected: Duration.zero, actual: const Duration(seconds: 1)),
      isNull,
    );
  });
}
