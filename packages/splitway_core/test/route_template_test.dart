import 'package:splitway_core/splitway_core.dart';
import 'package:test/test.dart';

void main() {
  RouteTemplate sample({
    bool isOfficial = false,
    DateTime? updatedAt,
  }) {
    return RouteTemplate(
      id: 'r1',
      name: 'X',
      path: const [],
      startFinishGate: const GateDefinition(
        left: GeoPoint(latitude: 0, longitude: 0),
        right: GeoPoint(latitude: 0, longitude: 0),
      ),
      sectors: const [],
      difficulty: RouteDifficulty.medium,
      createdAt: DateTime.utc(2026, 1, 1),
      isOfficial: isOfficial,
      updatedAt: updatedAt,
    );
  }

  test('isOfficial defaults to false and updatedAt defaults to null', () {
    final r = RouteTemplate(
      id: 'r1',
      name: 'X',
      path: const [],
      startFinishGate: const GateDefinition(
        left: GeoPoint(latitude: 0, longitude: 0),
        right: GeoPoint(latitude: 0, longitude: 0),
      ),
      sectors: const [],
      difficulty: RouteDifficulty.medium,
      createdAt: DateTime.utc(2026, 1, 1),
    );
    expect(r.isOfficial, isFalse);
    expect(r.updatedAt, isNull);
  });

  test('copyWith updates isOfficial and updatedAt', () {
    final ts = DateTime.utc(2026, 2, 1);
    final r = sample().copyWith(isOfficial: true, updatedAt: ts);
    expect(r.isOfficial, isTrue);
    expect(r.updatedAt, ts);
  });

  test('toJson/fromJson roundtrip preserves new fields', () {
    final ts = DateTime.utc(2026, 2, 1);
    final original = sample(isOfficial: true, updatedAt: ts);
    final restored = RouteTemplate.fromJson(original.toJson());
    expect(restored.isOfficial, isTrue);
    expect(restored.updatedAt, ts);
  });

  test('expectedDuration roundtrips and copyWith clears/sets it', () {
    final r = sample().copyWith(expectedDuration: const Duration(seconds: 90));
    expect(r.expectedDuration, const Duration(seconds: 90));

    final restored = RouteTemplate.fromJson(r.toJson());
    expect(restored.expectedDuration, const Duration(seconds: 90));

    // No-arg copyWith keeps the value; explicit null clears it.
    expect(r.copyWith().expectedDuration, const Duration(seconds: 90));
    expect(r.copyWith(expectedDuration: null).expectedDuration, isNull);
  });

  test('expectedDuration defaults to null', () {
    expect(sample().expectedDuration, isNull);
  });
}
