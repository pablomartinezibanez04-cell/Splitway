import 'package:flutter_test/flutter_test.dart';
import 'package:splitway_mobile/src/data/local/legacy_id.dart';

void main() {
  // Reference vector: md5("abc") = 900150983cd24fb0d6963f7d28e17f72.
  // Reshaped into 8-4-4-4-12 this is the value Postgres' legacy_id_to_uuid
  // produces, so the Dart port must match it exactly.
  test('hashes a legacy text id with the same md5 layout as Postgres', () {
    expect(legacyIdToUuid('abc'), '90015098-3cd2-4fb0-d696-3f7d28e17f72');
  });

  test('produces a syntactically valid UUID for app-shaped legacy ids', () {
    final uuidRe = RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
    );
    for (final id in [
      'route-1781259371777430',
      'route-1781259371777430-sec-1',
      'sess-1781259371777430',
      'rt-1781259371777430',
    ]) {
      expect(uuidRe.hasMatch(legacyIdToUuid(id)), isTrue, reason: id);
    }
  });

  test('passes a real UUID through unchanged', () {
    const uuid = 'f47ac10b-58cc-4372-a567-0e02b2c3d479';
    expect(legacyIdToUuid(uuid), uuid);
  });

  test('is deterministic and FK-consistent across columns', () {
    // A route id and its references must all map to the same UUID, so FK
    // links (sectors.route_id, session_runs.route_id) survive the rewrite.
    const routeId = 'route-1781259371777430';
    expect(legacyIdToUuid(routeId), legacyIdToUuid(routeId));
  });
}
