import 'package:splitway_core/splitway_core.dart';
import 'package:test/test.dart';

SessionRun _base() => SessionRun(
      id: 's1',
      routeTemplateId: 'r1',
      startedAt: DateTime.utc(2026, 1, 1),
      status: SessionStatus.completed,
      points: const [],
      laps: const [],
      sectorSummaries: const [],
      totalDistanceMeters: 0,
      maxSpeedMps: 0,
      avgSpeedMps: 0,
    );

void main() {
  test('name defaults to null and survives copyWith', () {
    final s = _base();
    expect(s.name, isNull);

    final named = s.copyWith(name: 'Morning run');
    expect(named.name, 'Morning run');
    // copyWith without name keeps the existing value.
    expect(named.copyWith(maxSpeedMps: 10).name, 'Morning run');
  });
}
