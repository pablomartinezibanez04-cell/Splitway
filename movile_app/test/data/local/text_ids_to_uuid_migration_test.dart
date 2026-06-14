import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:splitway_mobile/src/data/local/legacy_id.dart';
import 'package:splitway_mobile/src/data/local/splitway_local_database.dart';

/// Exercises [SplitwayLocalDatabase.migrateTextIdsToUuid] — the v11 local
/// migration that rewrites legacy text ids to the same deterministic UUIDs the
/// Supabase migration `20260601000004_text_ids_to_uuid.sql` produced, fixing
/// the `invalid input syntax for type uuid` (22P02) sync failures.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late SplitwayLocalDatabase db;

  setUp(() async {
    db = await SplitwayLocalDatabase.open(overridePath: inMemoryDatabasePath);
  });

  tearDown(() async => db.close());

  test('rewrites legacy ids to UUIDs while preserving FK links', () async {
    final raw = db.raw;
    const routeId = 'route-1781259371777430';
    const sectorId = 'route-1781259371777430-sec-1';
    const sessionId = 'sess-1781259371777430';

    await raw.insert('route_templates', {
      'id': routeId,
      'name': 'Jarama',
      'path_json': '[]',
      'start_finish_gate_json': '{}',
      'difficulty': 'medium',
      'created_at': 0,
      'is_official': 0,
    });
    await raw.insert('sectors', {
      'id': sectorId,
      'route_id': routeId,
      'order_index': 0,
      'label': 'S1',
      'gate_json': '{}',
    });
    await raw.insert('session_runs', {
      'id': sessionId,
      'route_id': routeId,
      'started_at': 0,
      'status': 'completed',
      'lap_summaries_json': '[]',
      'sector_summaries_json': '[]',
      'total_distance_m': 0,
      'max_speed_mps': 0,
      'avg_speed_mps': 0,
    });
    await raw.insert('telemetry_points', {
      'session_id': sessionId,
      'ts': 0,
      'lat': 1.0,
      'lng': 2.0,
    });

    await raw.transaction(
        (txn) => SplitwayLocalDatabase.migrateTextIdsToUuid(txn));

    final newRouteId = legacyIdToUuid(routeId);
    final newSectorId = legacyIdToUuid(sectorId);
    final newSessionId = legacyIdToUuid(sessionId);

    // PKs were rewritten.
    expect((await raw.query('route_templates')).single['id'], newRouteId);
    expect((await raw.query('sectors')).single['id'], newSectorId);
    expect((await raw.query('session_runs')).single['id'], newSessionId);

    // FKs followed the new PKs (links intact, no orphans).
    expect((await raw.query('sectors')).single['route_id'], newRouteId);
    expect((await raw.query('session_runs')).single['route_id'], newRouteId);
    final tp = (await raw.query('telemetry_points')).single;
    expect(tp['session_id'], newSessionId);
    expect(tp['lat'], 1.0); // payload untouched

    // Sector id is hashed from its OWN text id, not derived from the route's.
    expect(newSectorId, isNot(newRouteId));
  });

  test('leaves rows that already have UUID ids unchanged (idempotent)',
      () async {
    final raw = db.raw;
    const uuid = 'f47ac10b-58cc-4372-a567-0e02b2c3d479';
    await raw.insert('route_templates', {
      'id': uuid,
      'name': 'Already UUID',
      'path_json': jsonEncode([]),
      'start_finish_gate_json': '{}',
      'difficulty': 'medium',
      'created_at': 0,
      'is_official': 0,
    });

    await raw.transaction(
        (txn) => SplitwayLocalDatabase.migrateTextIdsToUuid(txn));
    // Running twice must be safe.
    await raw.transaction(
        (txn) => SplitwayLocalDatabase.migrateTextIdsToUuid(txn));

    expect((await raw.query('route_templates')).single['id'], uuid);
  });
}
