import 'package:test/test.dart';
import 'package:splitway_core/splitway_core.dart';

void main() {
  FreeRideRun sample({Duration? expectedDuration}) => FreeRideRun(
        id: 'fr-1',
        startedAt: DateTime.utc(2026, 1, 1, 10),
        endedAt: DateTime.utc(2026, 1, 1, 10, 30),
        status: FreeRideStatus.completed,
        points: const [],
        totalDistanceMeters: 1000,
        maxSpeedMps: 20,
        avgSpeedMps: 10,
        expectedDuration: expectedDuration,
      );

  test('expectedDuration defaults to null', () {
    expect(sample().expectedDuration, isNull);
  });

  test('copyWith keeps, sets, and clears expectedDuration', () {
    final r = sample(expectedDuration: const Duration(seconds: 90));
    expect(r.expectedDuration, const Duration(seconds: 90));
    expect(r.copyWith().expectedDuration, const Duration(seconds: 90));
    expect(
      sample().copyWith(expectedDuration: const Duration(seconds: 45)).expectedDuration,
      const Duration(seconds: 45),
    );
    expect(r.copyWith(expectedDuration: null).expectedDuration, isNull);
  });
}
