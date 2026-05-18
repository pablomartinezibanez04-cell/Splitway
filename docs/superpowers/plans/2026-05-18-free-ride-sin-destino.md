# "Sin destino" (Free Ride) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a new "Sin destino" mode that records the user's GPS track in real-time without a predefined route, collecting speed/distance/position, and optionally converts the recording into a reusable RouteTemplate.

**Architecture:** New `FreeRideRun` model + `FreeRideEngine` in `splitway_core` (no route/gate/sector dependency). New `free_ride` feature folder in the mobile app with its own controller and screen. A 4th tab is inserted in the bottom nav between Session and History. DB migration v3 adds `free_rides` + `free_ride_telemetry` tables.

**Tech Stack:** Flutter, splitway_core (pure Dart), sqflite, geolocator, Mapbox Maps Flutter, GoRouter, ChangeNotifier

---

## File Structure

| Action | Path | Responsibility |
|--------|------|----------------|
| Create | `packages/splitway_core/lib/src/models/free_ride_run.dart` | Domain model for a recorded free ride |
| Create | `packages/splitway_core/lib/src/models/free_ride_snapshot.dart` | Real-time tracking state for the UI |
| Create | `packages/splitway_core/lib/src/tracking/free_ride_engine.dart` | Lightweight engine — accumulates telemetry, computes distance/speed, no gates |
| Modify | `packages/splitway_core/lib/splitway_core.dart` | Export the 3 new files |
| Create | `movile_app/lib/src/features/free_ride/free_ride_controller.dart` | ChangeNotifier — manages stages (idle → recording → finished → saving) |
| Create | `movile_app/lib/src/features/free_ride/free_ride_screen.dart` | Full tab UI: idle prompt, live map + metrics, finished summary, save-as-route dialog |
| Modify | `movile_app/lib/src/features/home/home_shell.dart` | Add 4th NavigationDestination between Session and History |
| Modify | `movile_app/lib/src/routing/app_router.dart` | Add `/free-ride` StatefulShellBranch at index 2, shift History to index 3 |
| Modify | `movile_app/lib/src/data/local/splitway_local_database.dart` | Migration v3: `free_rides` + `free_ride_telemetry` tables |
| Modify | `movile_app/lib/src/data/repositories/local_draft_repository.dart` | CRUD methods for free rides |
| Modify | `movile_app/lib/l10n/app_en.arb` | English strings for the free ride tab |
| Modify | `movile_app/lib/l10n/app_es.arb` | Spanish strings for the free ride tab |
| Create | `packages/splitway_core/test/tracking/free_ride_engine_test.dart` | Unit tests for the engine |
| Create | `movile_app/test/features/free_ride/free_ride_controller_test.dart` | Unit tests for the controller |

---

### Task 1: FreeRideRun Model

**Files:**
- Create: `packages/splitway_core/lib/src/models/free_ride_run.dart`
- Create: `packages/splitway_core/test/models/free_ride_run_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// packages/splitway_core/test/models/free_ride_run_test.dart
import 'package:splitway_core/splitway_core.dart';
import 'package:test/test.dart';

void main() {
  group('FreeRideRun', () {
    test('totalDuration returns difference between start and end', () {
      final run = FreeRideRun(
        id: 'fr-1',
        startedAt: DateTime(2026, 1, 1, 10, 0),
        endedAt: DateTime(2026, 1, 1, 10, 30),
        status: FreeRideStatus.completed,
        points: const [],
        totalDistanceMeters: 5000,
        maxSpeedMps: 15.0,
        avgSpeedMps: 10.0,
      );
      expect(run.totalDuration, const Duration(minutes: 30));
    });

    test('totalDuration is null when endedAt is null', () {
      final run = FreeRideRun(
        id: 'fr-2',
        startedAt: DateTime(2026, 1, 1, 10, 0),
        status: FreeRideStatus.recording,
        points: const [],
        totalDistanceMeters: 0,
        maxSpeedMps: 0,
        avgSpeedMps: 0,
      );
      expect(run.totalDuration, isNull);
    });

    test('copyWith overrides specified fields', () {
      final run = FreeRideRun(
        id: 'fr-3',
        startedAt: DateTime(2026, 1, 1),
        status: FreeRideStatus.recording,
        points: const [],
        totalDistanceMeters: 0,
        maxSpeedMps: 0,
        avgSpeedMps: 0,
      );
      final updated = run.copyWith(
        name: 'Morning jog',
        status: FreeRideStatus.completed,
        totalDistanceMeters: 3000,
      );
      expect(updated.name, 'Morning jog');
      expect(updated.status, FreeRideStatus.completed);
      expect(updated.totalDistanceMeters, 3000);
      expect(updated.id, 'fr-3');
    });

    test('path returns locations from telemetry points', () {
      final points = [
        TelemetryPoint(
          timestamp: DateTime(2026, 1, 1, 10, 0),
          location: const GeoPoint(latitude: 40.0, longitude: -3.0),
          speedMps: 5.0,
        ),
        TelemetryPoint(
          timestamp: DateTime(2026, 1, 1, 10, 1),
          location: const GeoPoint(latitude: 40.001, longitude: -3.001),
          speedMps: 5.0,
        ),
      ];
      final run = FreeRideRun(
        id: 'fr-4',
        startedAt: DateTime(2026, 1, 1, 10, 0),
        status: FreeRideStatus.completed,
        points: points,
        totalDistanceMeters: 150,
        maxSpeedMps: 5.0,
        avgSpeedMps: 5.0,
      );
      expect(run.path, hasLength(2));
      expect(run.path.first.latitude, 40.0);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd packages/splitway_core && dart test test/models/free_ride_run_test.dart`
Expected: Compilation error — `FreeRideRun` and `FreeRideStatus` not defined.

- [ ] **Step 3: Write the model**

```dart
// packages/splitway_core/lib/src/models/free_ride_run.dart
import 'geo_point.dart';
import 'telemetry_point.dart';

enum FreeRideStatus { recording, completed }

extension FreeRideStatusX on FreeRideStatus {
  String get id => name;

  static FreeRideStatus fromId(String value) {
    return FreeRideStatus.values.firstWhere(
      (s) => s.name == value,
      orElse: () => FreeRideStatus.recording,
    );
  }
}

class FreeRideRun {
  const FreeRideRun({
    required this.id,
    required this.startedAt,
    required this.status,
    required this.points,
    required this.totalDistanceMeters,
    required this.maxSpeedMps,
    required this.avgSpeedMps,
    this.endedAt,
    this.name,
    this.description,
    this.locationLabel,
  });

  final String id;
  final DateTime startedAt;
  final DateTime? endedAt;
  final FreeRideStatus status;
  final List<TelemetryPoint> points;
  final double totalDistanceMeters;
  final double maxSpeedMps;
  final double avgSpeedMps;
  final String? name;
  final String? description;
  final String? locationLabel;

  Duration? get totalDuration {
    final end = endedAt;
    if (end == null) return null;
    return end.difference(startedAt);
  }

  List<GeoPoint> get path => points.map((p) => p.location).toList();

  FreeRideRun copyWith({
    String? id,
    DateTime? startedAt,
    DateTime? endedAt,
    FreeRideStatus? status,
    List<TelemetryPoint>? points,
    double? totalDistanceMeters,
    double? maxSpeedMps,
    double? avgSpeedMps,
    String? name,
    String? description,
    String? locationLabel,
  }) {
    return FreeRideRun(
      id: id ?? this.id,
      startedAt: startedAt ?? this.startedAt,
      endedAt: endedAt ?? this.endedAt,
      status: status ?? this.status,
      points: points ?? this.points,
      totalDistanceMeters: totalDistanceMeters ?? this.totalDistanceMeters,
      maxSpeedMps: maxSpeedMps ?? this.maxSpeedMps,
      avgSpeedMps: avgSpeedMps ?? this.avgSpeedMps,
      name: name ?? this.name,
      description: description ?? this.description,
      locationLabel: locationLabel ?? this.locationLabel,
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd packages/splitway_core && dart test test/models/free_ride_run_test.dart`
Expected: All 4 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add packages/splitway_core/lib/src/models/free_ride_run.dart packages/splitway_core/test/models/free_ride_run_test.dart
git commit -m "feat(core): add FreeRideRun model for destination-free recording"
```

---

### Task 2: FreeRideSnapshot Model

**Files:**
- Create: `packages/splitway_core/lib/src/models/free_ride_snapshot.dart`

- [ ] **Step 1: Create the snapshot model**

This is a simple value object with no behaviour to test beyond construction. Write it directly.

```dart
// packages/splitway_core/lib/src/models/free_ride_snapshot.dart
enum FreeRideTrackingStatus { idle, recording, finished }

class FreeRideSnapshot {
  const FreeRideSnapshot({
    required this.status,
    required this.elapsed,
    required this.totalDistanceMeters,
    required this.currentSpeedMps,
    required this.maxSpeedMps,
    required this.avgSpeedMps,
    required this.pointCount,
  });

  final FreeRideTrackingStatus status;
  final Duration elapsed;
  final double totalDistanceMeters;
  final double currentSpeedMps;
  final double maxSpeedMps;
  final double avgSpeedMps;
  final int pointCount;

  static const FreeRideSnapshot initial = FreeRideSnapshot(
    status: FreeRideTrackingStatus.idle,
    elapsed: Duration.zero,
    totalDistanceMeters: 0,
    currentSpeedMps: 0,
    maxSpeedMps: 0,
    avgSpeedMps: 0,
    pointCount: 0,
  );
}
```

- [ ] **Step 2: Commit**

```bash
git add packages/splitway_core/lib/src/models/free_ride_snapshot.dart
git commit -m "feat(core): add FreeRideSnapshot value object"
```

---

### Task 3: FreeRideEngine

**Files:**
- Create: `packages/splitway_core/lib/src/tracking/free_ride_engine.dart`
- Create: `packages/splitway_core/test/tracking/free_ride_engine_test.dart`

- [ ] **Step 1: Write the failing tests**

```dart
// packages/splitway_core/test/tracking/free_ride_engine_test.dart
import 'package:splitway_core/splitway_core.dart';
import 'package:test/test.dart';

void main() {
  group('FreeRideEngine', () {
    late FreeRideEngine engine;
    final baseTime = DateTime(2026, 1, 1, 10, 0);

    setUp(() {
      engine = FreeRideEngine(
        sessionId: 'test-fr',
        clock: () => baseTime.add(const Duration(minutes: 5)),
      );
    });

    tearDown(() async {
      await engine.dispose();
    });

    test('snapshot is idle before start', () {
      expect(engine.snapshot.status, FreeRideTrackingStatus.idle);
      expect(engine.snapshot.pointCount, 0);
    });

    test('snapshot transitions to recording after start', () {
      engine.start();
      expect(engine.snapshot.status, FreeRideTrackingStatus.recording);
    });

    test('ignores points before start', () {
      engine.ingest(TelemetryPoint(
        timestamp: baseTime,
        location: const GeoPoint(latitude: 40.0, longitude: -3.0),
      ));
      expect(engine.snapshot.pointCount, 0);
    });

    test('accumulates distance between ingested points', () {
      engine.start();
      final p1 = TelemetryPoint(
        timestamp: baseTime,
        location: const GeoPoint(latitude: 40.0, longitude: -3.0),
        speedMps: 5.0,
      );
      final p2 = TelemetryPoint(
        timestamp: baseTime.add(const Duration(seconds: 10)),
        location: const GeoPoint(latitude: 40.001, longitude: -3.0),
        speedMps: 10.0,
      );
      engine.ingest(p1);
      engine.ingest(p2);

      expect(engine.snapshot.pointCount, 2);
      expect(engine.snapshot.totalDistanceMeters, greaterThan(100));
      expect(engine.snapshot.maxSpeedMps, 10.0);
      expect(engine.snapshot.currentSpeedMps, 10.0);
    });

    test('finish returns a FreeRideRun with computed stats', () {
      engine.start();
      engine.ingest(TelemetryPoint(
        timestamp: baseTime,
        location: const GeoPoint(latitude: 40.0, longitude: -3.0),
        speedMps: 5.0,
      ));
      engine.ingest(TelemetryPoint(
        timestamp: baseTime.add(const Duration(seconds: 30)),
        location: const GeoPoint(latitude: 40.001, longitude: -3.0),
        speedMps: 12.0,
      ));

      final result = engine.finish();

      expect(result.id, 'test-fr');
      expect(result.status, FreeRideStatus.completed);
      expect(result.points, hasLength(2));
      expect(result.totalDistanceMeters, greaterThan(100));
      expect(result.maxSpeedMps, 12.0);
      expect(result.avgSpeedMps, greaterThan(0));
      expect(result.endedAt, isNotNull);
    });

    test('finish is idempotent', () {
      engine.start();
      engine.ingest(TelemetryPoint(
        timestamp: baseTime,
        location: const GeoPoint(latitude: 40.0, longitude: -3.0),
      ));
      final first = engine.finish();
      final second = engine.finish();
      expect(first.id, second.id);
      expect(first.points.length, second.points.length);
    });

    test('ignores points after finish', () {
      engine.start();
      engine.ingest(TelemetryPoint(
        timestamp: baseTime,
        location: const GeoPoint(latitude: 40.0, longitude: -3.0),
      ));
      engine.finish();
      engine.ingest(TelemetryPoint(
        timestamp: baseTime.add(const Duration(seconds: 60)),
        location: const GeoPoint(latitude: 41.0, longitude: -3.0),
      ));
      expect(engine.snapshot.pointCount, 1);
    });
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd packages/splitway_core && dart test test/tracking/free_ride_engine_test.dart`
Expected: Compilation error — `FreeRideEngine` not defined.

- [ ] **Step 3: Write the engine**

```dart
// packages/splitway_core/lib/src/tracking/free_ride_engine.dart
import '../models/free_ride_run.dart';
import '../models/free_ride_snapshot.dart';
import '../models/telemetry_point.dart';

class FreeRideEngine {
  FreeRideEngine({
    required String sessionId,
    DateTime Function()? clock,
  })  : _sessionId = sessionId,
        _clock = clock ?? DateTime.now;

  final String _sessionId;
  final DateTime Function() _clock;

  final List<TelemetryPoint> _points = [];

  FreeRideTrackingStatus _status = FreeRideTrackingStatus.idle;
  TelemetryPoint? _previous;
  double _totalDistanceMeters = 0;
  double _maxSpeedMps = 0;
  double _lastSpeedMps = 0;

  FreeRideSnapshot get snapshot {
    final elapsed = _points.length >= 2
        ? _points.last.timestamp.difference(_points.first.timestamp)
        : Duration.zero;
    final totalSeconds = elapsed.inMilliseconds / 1000.0;
    final avgSpeed =
        totalSeconds <= 0 ? 0.0 : _totalDistanceMeters / totalSeconds;

    return FreeRideSnapshot(
      status: _status,
      elapsed: elapsed,
      totalDistanceMeters: _totalDistanceMeters,
      currentSpeedMps: _lastSpeedMps,
      maxSpeedMps: _maxSpeedMps,
      avgSpeedMps: avgSpeed,
      pointCount: _points.length,
    );
  }

  void start() {
    if (_status != FreeRideTrackingStatus.idle) return;
    _status = FreeRideTrackingStatus.recording;
  }

  void ingest(TelemetryPoint point) {
    if (_status != FreeRideTrackingStatus.recording) return;

    _points.add(point);
    _lastSpeedMps = point.speedMps ?? _lastSpeedMps;

    if ((point.speedMps ?? 0) > _maxSpeedMps) {
      _maxSpeedMps = point.speedMps!;
    }

    final prev = _previous;
    if (prev != null) {
      _totalDistanceMeters += prev.location.distanceTo(point.location);
    }
    _previous = point;
  }

  FreeRideRun finish() {
    if (_status == FreeRideTrackingStatus.finished) {
      return _buildRun();
    }
    _status = FreeRideTrackingStatus.finished;
    return _buildRun();
  }

  Future<void> dispose() async {
    // No streams to close in this simplified engine.
  }

  FreeRideRun _buildRun() {
    final startedAt =
        _points.isNotEmpty ? _points.first.timestamp : _clock();
    final endedAt =
        _points.isNotEmpty ? _points.last.timestamp : _clock();
    final totalSeconds =
        endedAt.difference(startedAt).inMilliseconds / 1000.0;
    final avgSpeed =
        totalSeconds <= 0 ? 0.0 : _totalDistanceMeters / totalSeconds;

    return FreeRideRun(
      id: _sessionId,
      startedAt: startedAt,
      endedAt: endedAt,
      status: FreeRideStatus.completed,
      points: List.unmodifiable(_points),
      totalDistanceMeters: _totalDistanceMeters,
      maxSpeedMps: _maxSpeedMps,
      avgSpeedMps: avgSpeed,
    );
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd packages/splitway_core && dart test test/tracking/free_ride_engine_test.dart`
Expected: All 7 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add packages/splitway_core/lib/src/tracking/free_ride_engine.dart packages/splitway_core/test/tracking/free_ride_engine_test.dart
git commit -m "feat(core): add FreeRideEngine for destination-free GPS tracking"
```

---

### Task 4: Export New Types from splitway_core

**Files:**
- Modify: `packages/splitway_core/lib/splitway_core.dart`

- [ ] **Step 1: Add the three new exports**

Add these lines after the existing exports in `packages/splitway_core/lib/splitway_core.dart`:

```dart
export 'src/models/free_ride_run.dart';
export 'src/models/free_ride_snapshot.dart';
export 'src/tracking/free_ride_engine.dart';
```

- [ ] **Step 2: Verify the package compiles**

Run: `cd packages/splitway_core && dart analyze`
Expected: No errors.

- [ ] **Step 3: Commit**

```bash
git add packages/splitway_core/lib/splitway_core.dart
git commit -m "feat(core): export free ride types from barrel file"
```

---

### Task 5: Database Migration v3 — free_rides + free_ride_telemetry

**Files:**
- Modify: `movile_app/lib/src/data/local/splitway_local_database.dart`
- Create: `movile_app/test/data/local/free_ride_migration_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// movile_app/test/data/local/free_ride_migration_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:splitway_mobile/src/data/local/splitway_local_database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('Migration v3 — free_rides tables', () {
    late SplitwayLocalDatabase db;

    setUp(() async {
      db = await SplitwayLocalDatabase.open(overridePath: inMemoryDatabasePath);
    });

    tearDown(() async {
      await db.close();
    });

    test('free_rides table exists and accepts inserts', () async {
      await db.raw.insert('free_rides', {
        'id': 'fr-test',
        'started_at': DateTime.now().millisecondsSinceEpoch,
        'status': 'recording',
        'total_distance_m': 0.0,
        'max_speed_mps': 0.0,
        'avg_speed_mps': 0.0,
      });
      final rows = await db.raw.query('free_rides');
      expect(rows, hasLength(1));
      expect(rows.first['id'], 'fr-test');
    });

    test('free_ride_telemetry table exists with FK to free_rides', () async {
      await db.raw.insert('free_rides', {
        'id': 'fr-fk',
        'started_at': DateTime.now().millisecondsSinceEpoch,
        'status': 'recording',
        'total_distance_m': 0.0,
        'max_speed_mps': 0.0,
        'avg_speed_mps': 0.0,
      });
      await db.raw.insert('free_ride_telemetry', {
        'free_ride_id': 'fr-fk',
        'ts': DateTime.now().millisecondsSinceEpoch,
        'lat': 40.0,
        'lng': -3.0,
      });
      final rows = await db.raw.query('free_ride_telemetry');
      expect(rows, hasLength(1));
    });

    test('cascade delete removes telemetry when free ride is deleted', () async {
      await db.raw.insert('free_rides', {
        'id': 'fr-del',
        'started_at': DateTime.now().millisecondsSinceEpoch,
        'status': 'completed',
        'total_distance_m': 100.0,
        'max_speed_mps': 5.0,
        'avg_speed_mps': 3.0,
      });
      await db.raw.insert('free_ride_telemetry', {
        'free_ride_id': 'fr-del',
        'ts': DateTime.now().millisecondsSinceEpoch,
        'lat': 40.0,
        'lng': -3.0,
      });
      await db.raw.delete('free_rides', where: 'id = ?', whereArgs: ['fr-del']);
      final rows = await db.raw
          .query('free_ride_telemetry', where: 'free_ride_id = ?', whereArgs: ['fr-del']);
      expect(rows, isEmpty);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd movile_app && flutter test test/data/local/free_ride_migration_test.dart`
Expected: FAIL — table `free_rides` does not exist.

- [ ] **Step 3: Add migration v3 to the database**

In `movile_app/lib/src/data/local/splitway_local_database.dart`, change `_schemaVersion` from `2` to `3` and add the v3 migration block at the end of `_migrate`:

```dart
static const int _schemaVersion = 3;
```

Add after the `if (from < 2 && to >= 2)` block:

```dart
    if (from < 3 && to >= 3) {
      await db.execute('''
        CREATE TABLE free_rides (
          id TEXT PRIMARY KEY NOT NULL,
          started_at INTEGER NOT NULL,
          ended_at INTEGER,
          status TEXT NOT NULL,
          total_distance_m REAL NOT NULL,
          max_speed_mps REAL NOT NULL,
          avg_speed_mps REAL NOT NULL,
          name TEXT,
          description TEXT,
          location_label TEXT
        )
      ''');
      await db.execute('''
        CREATE TABLE free_ride_telemetry (
          free_ride_id TEXT NOT NULL,
          ts INTEGER NOT NULL,
          lat REAL NOT NULL,
          lng REAL NOT NULL,
          speed_mps REAL,
          accuracy_m REAL,
          bearing_deg REAL,
          altitude_m REAL,
          FOREIGN KEY (free_ride_id) REFERENCES free_rides(id) ON DELETE CASCADE
        )
      ''');
      await db.execute(
        'CREATE INDEX idx_fr_telemetry_ride_ts ON free_ride_telemetry(free_ride_id, ts)',
      );
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd movile_app && flutter test test/data/local/free_ride_migration_test.dart`
Expected: All 3 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add movile_app/lib/src/data/local/splitway_local_database.dart movile_app/test/data/local/free_ride_migration_test.dart
git commit -m "feat(db): migration v3 — add free_rides and free_ride_telemetry tables"
```

---

### Task 6: Repository CRUD for Free Rides

**Files:**
- Modify: `movile_app/lib/src/data/repositories/local_draft_repository.dart`
- Create: `movile_app/test/data/repositories/free_ride_repository_test.dart`

- [ ] **Step 1: Write the failing tests**

```dart
// movile_app/test/data/repositories/free_ride_repository_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:splitway_core/splitway_core.dart';
import 'package:splitway_mobile/src/data/local/splitway_local_database.dart';
import 'package:splitway_mobile/src/data/repositories/local_draft_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late SplitwayLocalDatabase db;
  late LocalDraftRepository repo;

  setUp(() async {
    db = await SplitwayLocalDatabase.open(overridePath: inMemoryDatabasePath);
    repo = LocalDraftRepository(db);
  });

  tearDown(() async {
    await repo.dispose();
    await db.close();
  });

  FreeRideRun _makeFreeRide({
    String id = 'fr-1',
    List<TelemetryPoint>? points,
  }) {
    return FreeRideRun(
      id: id,
      startedAt: DateTime(2026, 1, 1, 10, 0),
      endedAt: DateTime(2026, 1, 1, 10, 30),
      status: FreeRideStatus.completed,
      points: points ??
          [
            TelemetryPoint(
              timestamp: DateTime(2026, 1, 1, 10, 0),
              location: const GeoPoint(latitude: 40.0, longitude: -3.0),
              speedMps: 5.0,
            ),
            TelemetryPoint(
              timestamp: DateTime(2026, 1, 1, 10, 1),
              location: const GeoPoint(latitude: 40.001, longitude: -3.001),
              speedMps: 10.0,
            ),
          ],
      totalDistanceMeters: 150,
      maxSpeedMps: 10.0,
      avgSpeedMps: 7.5,
      name: 'Test ride',
    );
  }

  group('Free ride CRUD', () {
    test('saveFreeRideRun persists and getAllFreeRides retrieves', () async {
      await repo.saveFreeRideRun(_makeFreeRide());
      final rides = await repo.getAllFreeRides();
      expect(rides, hasLength(1));
      expect(rides.first.id, 'fr-1');
      expect(rides.first.name, 'Test ride');
    });

    test('getFreeRideRun loads telemetry points', () async {
      await repo.saveFreeRideRun(_makeFreeRide());
      final ride = await repo.getFreeRideRun('fr-1');
      expect(ride, isNotNull);
      expect(ride!.points, hasLength(2));
      expect(ride.points.first.speedMps, 5.0);
    });

    test('deleteFreeRide removes the record', () async {
      await repo.saveFreeRideRun(_makeFreeRide());
      await repo.deleteFreeRide('fr-1');
      final rides = await repo.getAllFreeRides();
      expect(rides, isEmpty);
    });

    test('updateFreeRideMetadata updates name and description', () async {
      await repo.saveFreeRideRun(_makeFreeRide());
      await repo.updateFreeRideMetadata(
        'fr-1',
        name: 'Updated name',
        description: 'A description',
        locationLabel: 'Madrid',
      );
      final ride = await repo.getFreeRideRun('fr-1');
      expect(ride!.name, 'Updated name');
      expect(ride.description, 'A description');
      expect(ride.locationLabel, 'Madrid');
    });
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd movile_app && flutter test test/data/repositories/free_ride_repository_test.dart`
Expected: Compilation error — methods `saveFreeRideRun`, `getAllFreeRides`, etc. not defined on `LocalDraftRepository`.

- [ ] **Step 3: Add free ride CRUD methods to LocalDraftRepository**

Add the following section at the end of `movile_app/lib/src/data/repositories/local_draft_repository.dart`, before the `// ---------- Cloud sync ----------` section. Also add the `FreeRideRun` import at the top (it comes from `splitway_core`):

```dart
  // ---------- Free rides ----------

  Future<void> saveFreeRideRun(FreeRideRun ride) async {
    await _db.transaction((txn) async {
      await txn.insert(
        'free_rides',
        {
          'id': ride.id,
          'started_at': ride.startedAt.toUtc().millisecondsSinceEpoch,
          'ended_at': ride.endedAt?.toUtc().millisecondsSinceEpoch,
          'status': ride.status.id,
          'total_distance_m': ride.totalDistanceMeters,
          'max_speed_mps': ride.maxSpeedMps,
          'avg_speed_mps': ride.avgSpeedMps,
          'name': ride.name,
          'description': ride.description,
          'location_label': ride.locationLabel,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await txn.delete('free_ride_telemetry',
          where: 'free_ride_id = ?', whereArgs: [ride.id]);
      final batch = txn.batch();
      for (final p in ride.points) {
        batch.insert('free_ride_telemetry', {
          'free_ride_id': ride.id,
          'ts': p.timestamp.toUtc().millisecondsSinceEpoch,
          'lat': p.location.latitude,
          'lng': p.location.longitude,
          'speed_mps': p.speedMps,
          'accuracy_m': p.accuracyMeters,
          'bearing_deg': p.bearingDeg,
          'altitude_m': p.altitudeMeters,
        });
      }
      await batch.commit(noResult: true);
    });
    _changes.add(null);
  }

  Future<FreeRideRun?> getFreeRideRun(String id) async {
    final rows = await _db
        .query('free_rides', where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return null;
    return _readFreeRide(rows.first, includePoints: true);
  }

  Future<List<FreeRideRun>> getAllFreeRides() async {
    final rows = await _db.query('free_rides', orderBy: 'started_at DESC');
    return Future.wait(
        rows.map((r) => _readFreeRide(r, includePoints: false)));
  }

  Future<void> updateFreeRideMetadata(
    String id, {
    String? name,
    String? description,
    String? locationLabel,
  }) async {
    await _db.update(
      'free_rides',
      {
        if (name != null) 'name': name,
        if (description != null) 'description': description,
        if (locationLabel != null) 'location_label': locationLabel,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    _changes.add(null);
  }

  Future<void> deleteFreeRide(String id) async {
    await _db.delete('free_rides', where: 'id = ?', whereArgs: [id]);
    _changes.add(null);
  }

  Future<FreeRideRun> _readFreeRide(
    Map<String, Object?> row, {
    bool includePoints = false,
  }) async {
    final id = row['id']! as String;

    List<TelemetryPoint> points = const [];
    if (includePoints) {
      final tRows = await _db.query(
        'free_ride_telemetry',
        where: 'free_ride_id = ?',
        whereArgs: [id],
        orderBy: 'ts ASC',
      );
      points = tRows.map((t) {
        return TelemetryPoint(
          timestamp: DateTime.fromMillisecondsSinceEpoch(
            t['ts']! as int,
            isUtc: true,
          ).toLocal(),
          location: GeoPoint(
            latitude: (t['lat']! as num).toDouble(),
            longitude: (t['lng']! as num).toDouble(),
          ),
          speedMps: (t['speed_mps'] as num?)?.toDouble(),
          accuracyMeters: (t['accuracy_m'] as num?)?.toDouble(),
          bearingDeg: (t['bearing_deg'] as num?)?.toDouble(),
          altitudeMeters: (t['altitude_m'] as num?)?.toDouble(),
        );
      }).toList();
    }

    return FreeRideRun(
      id: id,
      startedAt: DateTime.fromMillisecondsSinceEpoch(
        row['started_at']! as int,
        isUtc: true,
      ).toLocal(),
      endedAt: row['ended_at'] == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(
              row['ended_at']! as int,
              isUtc: true,
            ).toLocal(),
      status: FreeRideStatusX.fromId(row['status']! as String),
      points: points,
      totalDistanceMeters: (row['total_distance_m']! as num).toDouble(),
      maxSpeedMps: (row['max_speed_mps']! as num).toDouble(),
      avgSpeedMps: (row['avg_speed_mps']! as num).toDouble(),
      name: row['name'] as String?,
      description: row['description'] as String?,
      locationLabel: row['location_label'] as String?,
    );
  }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd movile_app && flutter test test/data/repositories/free_ride_repository_test.dart`
Expected: All 4 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add movile_app/lib/src/data/repositories/local_draft_repository.dart movile_app/test/data/repositories/free_ride_repository_test.dart
git commit -m "feat(repo): add CRUD methods for free ride runs"
```

---

### Task 7: Localization Strings (EN + ES)

**Files:**
- Modify: `movile_app/lib/l10n/app_en.arb`
- Modify: `movile_app/lib/l10n/app_es.arb`

- [ ] **Step 1: Add English strings to app_en.arb**

Add the following entries before the closing `}` in `movile_app/lib/l10n/app_en.arb`:

```json
  "navFreeRide": "Free ride",

  "freeRideTitle": "Free ride",
  "freeRideIdleTitle": "Ride without a destination",
  "freeRideIdleMessage": "Record your path in real time without a predefined route. Speed, distance and position are tracked automatically.",
  "freeRideStartButton": "Start recording",
  "freeRideElapsedLabel": "Elapsed",
  "freeRideDistanceLabel": "Distance",
  "freeRideSpeedLabel": "Speed",
  "freeRideMaxSpeedLabel": "Max speed",
  "freeRideAvgSpeedLabel": "Avg speed",
  "freeRideFinishButton": "Finish ride",
  "freeRideCompleteTitle": "Ride complete",
  "freeRideSavedSnackBar": "Free ride saved",
  "freeRideSaveAsRouteButton": "Save as reusable route",
  "freeRideDiscardButton": "Finish without saving route",
  "freeRideNewRideButton": "New ride",
  "freeRideSaveRouteDialogTitle": "Save as route",
  "freeRideNameLabel": "Name",
  "freeRideDescriptionLabel": "Description (optional)",
  "freeRideDifficultyLabel": "Difficulty",
  "freeRideRouteSavedSnack": "Route \"{name}\" saved",
  "@freeRideRouteSavedSnack": { "placeholders": { "name": { "type": "String" } } },
  "freeRidePointsLabel": "{count, plural, =1{1 point} other{{count} points}}",
  "@freeRidePointsLabel": { "placeholders": { "count": { "type": "int" } } }
```

- [ ] **Step 2: Add Spanish strings to app_es.arb**

Add the following entries before the closing `}` in `movile_app/lib/l10n/app_es.arb`:

```json
  "navFreeRide": "Sin destino",

  "freeRideTitle": "Sin destino",
  "freeRideIdleTitle": "Ruta sin destino",
  "freeRideIdleMessage": "Graba tu recorrido en tiempo real sin una ruta predefinida. Se registran velocidad, distancia y posición automáticamente.",
  "freeRideStartButton": "Comenzar grabación",
  "freeRideElapsedLabel": "Tiempo",
  "freeRideDistanceLabel": "Distancia",
  "freeRideSpeedLabel": "Velocidad",
  "freeRideMaxSpeedLabel": "Vel. máx.",
  "freeRideAvgSpeedLabel": "Vel. media",
  "freeRideFinishButton": "Finalizar recorrido",
  "freeRideCompleteTitle": "Recorrido completo",
  "freeRideSavedSnackBar": "Recorrido guardado",
  "freeRideSaveAsRouteButton": "Guardar como ruta reutilizable",
  "freeRideDiscardButton": "Finalizar sin guardar ruta",
  "freeRideNewRideButton": "Nuevo recorrido",
  "freeRideSaveRouteDialogTitle": "Guardar como ruta",
  "freeRideNameLabel": "Nombre",
  "freeRideDescriptionLabel": "Descripción (opcional)",
  "freeRideDifficultyLabel": "Dificultad",
  "freeRideRouteSavedSnack": "Ruta \"{name}\" guardada",
  "freeRidePointsLabel": "{count, plural, =1{1 punto} other{{count} puntos}}"
```

- [ ] **Step 3: Regenerate l10n files**

Run: `cd movile_app && flutter gen-l10n`
Expected: Success, no errors.

- [ ] **Step 4: Commit**

```bash
git add movile_app/lib/l10n/
git commit -m "feat(l10n): add EN/ES strings for free ride feature"
```

---

### Task 8: FreeRideController

**Files:**
- Create: `movile_app/lib/src/features/free_ride/free_ride_controller.dart`
- Create: `movile_app/test/features/free_ride/free_ride_controller_test.dart`

- [ ] **Step 1: Write the failing tests**

```dart
// movile_app/test/features/free_ride/free_ride_controller_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:splitway_core/splitway_core.dart';
import 'package:splitway_mobile/src/data/local/splitway_local_database.dart';
import 'package:splitway_mobile/src/data/repositories/local_draft_repository.dart';
import 'package:splitway_mobile/src/features/free_ride/free_ride_controller.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late SplitwayLocalDatabase db;
  late LocalDraftRepository repo;
  late FreeRideController ctrl;

  setUp(() async {
    db = await SplitwayLocalDatabase.open(overridePath: inMemoryDatabasePath);
    repo = LocalDraftRepository(db);
    ctrl = FreeRideController(repo);
  });

  tearDown(() async {
    ctrl.dispose();
    await repo.dispose();
    await db.close();
  });

  group('FreeRideController', () {
    test('starts in idle stage', () {
      expect(ctrl.stage, FreeRideStage.idle);
      expect(ctrl.engine, isNull);
    });

    test('startRecording transitions to recording', () async {
      await ctrl.startRecording();
      expect(ctrl.stage, FreeRideStage.recording);
      expect(ctrl.engine, isNotNull);
    });

    test('ingestPoint feeds the engine', () async {
      await ctrl.startRecording();
      ctrl.ingestPoint(TelemetryPoint(
        timestamp: DateTime(2026, 1, 1, 10, 0),
        location: const GeoPoint(latitude: 40.0, longitude: -3.0),
        speedMps: 5.0,
      ));
      expect(ctrl.snapshot.pointCount, 1);
    });

    test('finishRecording saves to repo and transitions to finished', () async {
      await ctrl.startRecording();
      ctrl.ingestPoint(TelemetryPoint(
        timestamp: DateTime(2026, 1, 1, 10, 0),
        location: const GeoPoint(latitude: 40.0, longitude: -3.0),
        speedMps: 5.0,
      ));
      ctrl.ingestPoint(TelemetryPoint(
        timestamp: DateTime(2026, 1, 1, 10, 1),
        location: const GeoPoint(latitude: 40.001, longitude: -3.001),
        speedMps: 8.0,
      ));
      await ctrl.finishRecording();
      expect(ctrl.stage, FreeRideStage.finished);
      expect(ctrl.result, isNotNull);

      final saved = await repo.getAllFreeRides();
      expect(saved, hasLength(1));
    });

    test('resetForNewRide transitions back to idle', () async {
      await ctrl.startRecording();
      ctrl.ingestPoint(TelemetryPoint(
        timestamp: DateTime(2026, 1, 1, 10, 0),
        location: const GeoPoint(latitude: 40.0, longitude: -3.0),
      ));
      await ctrl.finishRecording();
      ctrl.resetForNewRide();
      expect(ctrl.stage, FreeRideStage.idle);
      expect(ctrl.result, isNull);
      expect(ctrl.engine, isNull);
    });

    test('saveAsRoute creates a RouteTemplate in the repo', () async {
      await ctrl.startRecording();
      ctrl.ingestPoint(TelemetryPoint(
        timestamp: DateTime(2026, 1, 1, 10, 0),
        location: const GeoPoint(latitude: 40.0, longitude: -3.0),
        speedMps: 5.0,
      ));
      ctrl.ingestPoint(TelemetryPoint(
        timestamp: DateTime(2026, 1, 1, 10, 0, 30),
        location: const GeoPoint(latitude: 40.001, longitude: -3.0),
        speedMps: 5.0,
      ));
      ctrl.ingestPoint(TelemetryPoint(
        timestamp: DateTime(2026, 1, 1, 10, 1),
        location: const GeoPoint(latitude: 40.002, longitude: -3.001),
        speedMps: 5.0,
      ));
      await ctrl.finishRecording();

      await ctrl.saveAsRoute(
        name: 'Morning run',
        description: 'A test',
        difficulty: RouteDifficulty.easy,
      );

      final routes = await repo.getAllRoutes();
      expect(routes, hasLength(1));
      expect(routes.first.name, 'Morning run');
      expect(routes.first.path.length, greaterThanOrEqualTo(2));
      expect(routes.first.sectors, isEmpty);
    });
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd movile_app && flutter test test/features/free_ride/free_ride_controller_test.dart`
Expected: Compilation error — `FreeRideController` not defined.

- [ ] **Step 3: Write the controller**

```dart
// movile_app/lib/src/features/free_ride/free_ride_controller.dart
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:splitway_core/splitway_core.dart';

import '../../data/repositories/local_draft_repository.dart';
import '../../services/tracking/location_service.dart';

enum FreeRideStage { idle, recording, finished }

class FreeRideController extends ChangeNotifier {
  FreeRideController(this._repo);

  final LocalDraftRepository _repo;

  FreeRideStage _stage = FreeRideStage.idle;
  FreeRideStage get stage => _stage;

  FreeRideEngine? _engine;
  FreeRideEngine? get engine => _engine;

  FreeRideRun? _result;
  FreeRideRun? get result => _result;

  LocationPermissionStatus? _permissionStatus;
  LocationPermissionStatus? get permissionStatus => _permissionStatus;

  StreamSubscription<TelemetryPoint>? _gpsSub;
  Timer? _ticker;

  final List<TelemetryPoint> _ingested = [];
  List<TelemetryPoint> get ingested => List.unmodifiable(_ingested);

  FreeRideSnapshot get snapshot =>
      _engine?.snapshot ?? FreeRideSnapshot.initial;

  Future<void> startRecording() async {
    _permissionStatus = await LocationService.ensurePermission();
    if (_permissionStatus != LocationPermissionStatus.granted) {
      notifyListeners();
      return;
    }

    final id = 'fr-${DateTime.now().microsecondsSinceEpoch}';
    _engine = FreeRideEngine(sessionId: id);
    _engine!.start();
    _ingested.clear();
    _stage = FreeRideStage.recording;
    notifyListeners();

    _gpsSub = LocationService.positionStream().listen((point) {
      ingestPoint(point);
    }, onError: (_) {
      // GPS error — keep recording what we have.
    });

    _ticker = Timer.periodic(const Duration(milliseconds: 500), (_) {
      notifyListeners();
    });
  }

  void ingestPoint(TelemetryPoint point) {
    if (_stage != FreeRideStage.recording) return;
    _engine?.ingest(point);
    _ingested.add(point);
    notifyListeners();
  }

  Future<FreeRideRun?> finishRecording() async {
    await _gpsSub?.cancel();
    _gpsSub = null;
    _ticker?.cancel();
    _ticker = null;

    final e = _engine;
    if (e == null) return null;
    final run = e.finish();
    await _repo.saveFreeRideRun(run);
    _result = run;
    _stage = FreeRideStage.finished;
    notifyListeners();
    return run;
  }

  Future<RouteTemplate?> saveAsRoute({
    required String name,
    String? description,
    RouteDifficulty difficulty = RouteDifficulty.medium,
    String? locationLabel,
  }) async {
    final run = _result;
    if (run == null || run.points.length < 2) return null;

    final path = run.points.map((p) => p.location).toList();
    final simplified =
        path.length > 200 ? douglasPeucker(path, 5.0) : path;

    final gate = GateDefinition(
      left: simplified.first.destinationPoint(
        (simplified.first.bearingTo(simplified[1]) + 90) % 360,
        10,
      ),
      right: simplified.first.destinationPoint(
        (simplified.first.bearingTo(simplified[1]) - 90 + 360) % 360,
        10,
      ),
    );

    final route = RouteTemplate(
      id: 'rt-${DateTime.now().microsecondsSinceEpoch}',
      name: name,
      description: description,
      path: simplified,
      startFinishGate: gate,
      sectors: const [],
      difficulty: difficulty,
      createdAt: DateTime.now(),
      locationLabel: locationLabel ?? run.locationLabel,
    );

    await _repo.saveRouteTemplate(route);

    await _repo.updateFreeRideMetadata(
      run.id,
      name: name,
      description: description,
      locationLabel: locationLabel,
    );

    return route;
  }

  void resetForNewRide() {
    _engine = null;
    _result = null;
    _ingested.clear();
    _permissionStatus = null;
    _stage = FreeRideStage.idle;
    notifyListeners();
  }

  @override
  void dispose() {
    _gpsSub?.cancel();
    _ticker?.cancel();
    super.dispose();
  }
}
```

- [ ] **Step 4: Verify `douglasPeucker` exists in splitway_core**

The controller uses `douglasPeucker` from `splitway_core`. Verify it is exported:

Run: `cd packages/splitway_core && grep -r "douglasPeucker" lib/`

This function is exported from `src/path_simplifier.dart` (already in the barrel file). If it doesn't exist with this exact name, check the actual export and adjust the import/call accordingly.

- [ ] **Step 5: Run tests to verify they pass**

Run: `cd movile_app && flutter test test/features/free_ride/free_ride_controller_test.dart`
Expected: All 6 tests PASS.

- [ ] **Step 6: Commit**

```bash
git add movile_app/lib/src/features/free_ride/free_ride_controller.dart movile_app/test/features/free_ride/free_ride_controller_test.dart
git commit -m "feat(free-ride): add FreeRideController with GPS tracking and save-as-route"
```

---

### Task 9: FreeRideScreen UI

**Files:**
- Create: `movile_app/lib/src/features/free_ride/free_ride_screen.dart`

- [ ] **Step 1: Write the screen**

```dart
// movile_app/lib/src/features/free_ride/free_ride_screen.dart
import 'package:flutter/material.dart';
import 'package:splitway_core/splitway_core.dart';
import 'package:splitway_mobile/l10n/app_localizations.dart';

import '../../config/app_config.dart';
import '../../routing/app_router.dart';
import '../../services/auth/auth_service.dart';
import '../../services/tracking/location_service.dart';
import '../../shared/formatters.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/splitway_map.dart';
import '../home/home_shell.dart';
import 'free_ride_controller.dart';

class FreeRideScreen extends StatefulWidget {
  const FreeRideScreen({
    super.key,
    required this.controller,
    required this.config,
    this.authService,
  });

  final FreeRideController controller;
  final AppConfig config;
  final AuthService? authService;

  @override
  State<FreeRideScreen> createState() => _FreeRideScreenState();
}

class _FreeRideScreenState extends State<FreeRideScreen> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChange);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final ctrl = widget.controller;
    return Scaffold(
      appBar: AppBar(
        leading: buildDrawerLeading(context, widget.authService),
        title: Text(l.freeRideTitle),
      ),
      body: switch (ctrl.stage) {
        FreeRideStage.idle => _buildIdle(context, ctrl),
        FreeRideStage.recording => _buildRecording(context, ctrl),
        FreeRideStage.finished => _buildFinished(context, ctrl),
      },
    );
  }

  Widget _buildIdle(BuildContext context, FreeRideController ctrl) {
    final l = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          EmptyState(
            icon: Icons.explore_outlined,
            title: l.freeRideIdleTitle,
            message: l.freeRideIdleMessage,
          ),
          if (ctrl.permissionStatus != null &&
              ctrl.permissionStatus != LocationPermissionStatus.granted) ...[
            const SizedBox(height: 16),
            _PermissionBanner(status: ctrl.permissionStatus!),
          ],
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: () async {
              final allowed = await requireAuth(
                context,
                widget.authService,
                message: AppLocalizations.of(context).loginBannerDefault,
              );
              if (!allowed || !mounted) return;
              await ctrl.startRecording();
            },
            icon: const Icon(Icons.play_arrow),
            label: Text(l.freeRideStartButton),
          ),
        ],
      ),
    );
  }

  Widget _buildRecording(BuildContext context, FreeRideController ctrl) {
    final l = AppLocalizations.of(context);
    final snap = ctrl.snapshot;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Expanded(
            child: Card(
              clipBehavior: Clip.antiAlias,
              child: SplitwayMap(
                useMapbox: widget.config.hasMapbox,
                telemetry: ctrl.ingested,
                userLocation: ctrl.ingested.isNotEmpty
                    ? ctrl.ingested.last.location
                    : null,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _MetricCard(
                  label: l.freeRideElapsedLabel,
                  value: Formatters.duration(snap.elapsed),
                ),
              ),
              Expanded(
                child: _MetricCard(
                  label: l.freeRideDistanceLabel,
                  value: () {
                    final (dv, isKm) =
                        Formatters.distanceMeters(snap.totalDistanceMeters);
                    return isKm
                        ? l.unitKilometers(dv.toStringAsFixed(2))
                        : l.unitMeters(dv.toStringAsFixed(0));
                  }(),
                ),
              ),
              Expanded(
                child: _MetricCard(
                  label: l.freeRideSpeedLabel,
                  value: l.unitKmh(
                    Formatters.speedMps(snap.currentSpeedMps)
                        .toStringAsFixed(1),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _GpsStatusTile(pointCount: snap.pointCount),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: () async {
              final savedText = l.freeRideSavedSnackBar;
              final messenger = ScaffoldMessenger.of(context);
              await ctrl.finishRecording();
              if (!mounted) return;
              messenger.showSnackBar(
                SnackBar(content: Text(savedText)),
              );
            },
            icon: const Icon(Icons.stop),
            label: Text(l.freeRideFinishButton),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.redAccent,
              minimumSize: const Size.fromHeight(48),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFinished(BuildContext context, FreeRideController ctrl) {
    final l = AppLocalizations.of(context);
    final result = ctrl.result!;
    final (dv, isKm) = Formatters.distanceMeters(result.totalDistanceMeters);
    final distStr = isKm
        ? l.unitKilometers(dv.toStringAsFixed(2))
        : l.unitMeters(dv.toStringAsFixed(0));

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(l.freeRideCompleteTitle,
            style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 16),
        Card(
          clipBehavior: Clip.antiAlias,
          child: AspectRatio(
            aspectRatio: 4 / 3,
            child: SplitwayMap(
              useMapbox: widget.config.hasMapbox,
              telemetry: result.points,
              interactive: false,
            ),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _StatCard(l.freeRideDistanceLabel, distStr),
            ),
            Expanded(
              child: _StatCard(
                l.freeRideMaxSpeedLabel,
                l.unitKmh(Formatters.speedMps(result.maxSpeedMps)
                    .toStringAsFixed(1)),
              ),
            ),
            Expanded(
              child: _StatCard(
                l.freeRideAvgSpeedLabel,
                l.unitKmh(Formatters.speedMps(result.avgSpeedMps)
                    .toStringAsFixed(1)),
              ),
            ),
          ],
        ),
        if (result.totalDuration != null) ...[
          const SizedBox(height: 8),
          _StatCard(
            l.freeRideElapsedLabel,
            Formatters.duration(result.totalDuration!),
          ),
        ],
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: () => _showSaveAsRouteDialog(context, ctrl),
          icon: const Icon(Icons.save_alt),
          label: Text(l.freeRideSaveAsRouteButton),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: ctrl.resetForNewRide,
          icon: const Icon(Icons.refresh),
          label: Text(l.freeRideNewRideButton),
        ),
      ],
    );
  }

  Future<void> _showSaveAsRouteDialog(
    BuildContext context,
    FreeRideController ctrl,
  ) async {
    final l = AppLocalizations.of(context);
    final nameCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    var difficulty = RouteDifficulty.medium;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(l.freeRideSaveRouteDialogTitle),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: InputDecoration(labelText: l.freeRideNameLabel),
                autofocus: true,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: descCtrl,
                decoration:
                    InputDecoration(labelText: l.freeRideDescriptionLabel),
              ),
              const SizedBox(height: 16),
              Text(l.freeRideDifficultyLabel,
                  style: Theme.of(ctx).textTheme.titleSmall),
              const SizedBox(height: 8),
              SegmentedButton<RouteDifficulty>(
                segments: [
                  ButtonSegment(
                    value: RouteDifficulty.easy,
                    label: Text(l.editorDifficultyEasy),
                  ),
                  ButtonSegment(
                    value: RouteDifficulty.medium,
                    label: Text(l.editorDifficultyMedium),
                  ),
                  ButtonSegment(
                    value: RouteDifficulty.hard,
                    label: Text(l.editorDifficultyHard),
                  ),
                ],
                selected: {difficulty},
                onSelectionChanged: (s) {
                  setDialogState(() => difficulty = s.first);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l.commonCancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(l.commonSave),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true || !mounted) return;
    final name = nameCtrl.text.trim();
    if (name.isEmpty) return;

    final route = await ctrl.saveAsRoute(
      name: name,
      description: descCtrl.text.trim().isEmpty ? null : descCtrl.text.trim(),
      difficulty: difficulty,
    );

    if (!mounted || route == null) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l.freeRideRouteSavedSnack(route.name))),
    );
    ctrl.resetForNewRide();
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        child: Column(
          children: [
            Text(label,
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: theme.colorScheme.outline)),
            const SizedBox(height: 4),
            Text(value, style: theme.textTheme.titleMedium),
          ],
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          children: [
            Text(label, style: Theme.of(context).textTheme.labelSmall),
            const SizedBox(height: 4),
            Text(value, style: Theme.of(context).textTheme.titleMedium),
          ],
        ),
      ),
    );
  }
}

class _GpsStatusTile extends StatelessWidget {
  const _GpsStatusTile({required this.pointCount});

  final int pointCount;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            const Icon(Icons.gps_fixed, color: Colors.green),
            const SizedBox(width: 8),
            Text(
              l.freeRidePointsLabel(pointCount),
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _PermissionBanner extends StatelessWidget {
  const _PermissionBanner({required this.status});

  final LocationPermissionStatus status;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final (color, icon, text) = switch (status) {
      LocationPermissionStatus.granted => (
          Colors.green,
          Icons.check_circle_outline,
          l.sessionPermissionGranted,
        ),
      LocationPermissionStatus.denied => (
          Colors.orange,
          Icons.warning_amber_rounded,
          l.sessionPermissionDenied,
        ),
      LocationPermissionStatus.permanentlyDenied => (
          Colors.red,
          Icons.block,
          l.sessionPermissionPermanentlyDenied,
        ),
      LocationPermissionStatus.servicesDisabled => (
          Colors.red,
          Icons.location_off,
          l.sessionServicesDisabled,
        ),
    };
    return Container(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        border: Border.all(color: color.withValues(alpha: 0.5)),
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.all(10),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style: Theme.of(context).textTheme.bodySmall),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 2: Commit**

```bash
git add movile_app/lib/src/features/free_ride/free_ride_screen.dart
git commit -m "feat(free-ride): add FreeRideScreen with idle, recording, and finished views"
```

---

### Task 10: Wire into Navigation — Router + HomeShell

**Files:**
- Modify: `movile_app/lib/src/routing/app_router.dart`
- Modify: `movile_app/lib/src/features/home/home_shell.dart`

- [ ] **Step 1: Update app_router.dart**

Add the import at the top of `movile_app/lib/src/routing/app_router.dart`:

```dart
import '../features/free_ride/free_ride_controller.dart';
import '../features/free_ride/free_ride_screen.dart';
```

Add a `_freeRideController` field in `AppRouter`, after `_sessionController`:

```dart
        _freeRideController = FreeRideController(repository);
```

Also initialize it in the constructor parameter list (add after the existing `_sessionController` assignment):

```dart
        _freeRideController = FreeRideController(repository);
```

Add a new `StatefulShellBranch` between Session (index 1) and History (index 2) in the `branches` list:

```dart
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/free-ride',
                builder: (_, __) => FreeRideScreen(
                  controller: _freeRideController,
                  config: config,
                  authService: authService,
                ),
              ),
            ],
          ),
```

The `branches` list should now be:
1. `/editor` (index 0)
2. `/session` (index 1)
3. `/free-ride` (index 2) — NEW
4. `/history` (index 3)

Add `_freeRideController.dispose()` in the `dispose()` method.

Add the field declaration after `_sessionController`:

```dart
  final FreeRideController _freeRideController;
```

- [ ] **Step 2: Update home_shell.dart**

In `movile_app/lib/src/features/home/home_shell.dart`, add a new `NavigationDestination` between Session and History in the `destinations` list:

```dart
          NavigationDestination(
            icon: const Icon(Icons.explore_outlined),
            selectedIcon: const Icon(Icons.explore),
            label: AppLocalizations.of(context).navFreeRide,
          ),
```

The destinations list should now be:
1. Editor (pencil icon)
2. Session (play icon)
3. **Free ride (explore icon)** — NEW
4. History (history icon)

- [ ] **Step 3: Verify the app compiles**

Run: `cd movile_app && flutter analyze`
Expected: No errors.

- [ ] **Step 4: Commit**

```bash
git add movile_app/lib/src/routing/app_router.dart movile_app/lib/src/features/home/home_shell.dart
git commit -m "feat(nav): wire free ride tab into bottom navigation at index 2"
```

---

### Task 11: Manual Testing in Browser/Emulator

**Files:** None (testing only)

- [ ] **Step 1: Start the dev server**

Run: `cd movile_app && flutter run -d chrome` (or an emulator)

- [ ] **Step 2: Verify the new tab appears**

Check that the bottom navigation now has 4 tabs: Editor, Session, Sin destino (or Free ride), History. Tap through each tab and verify none crash.

- [ ] **Step 3: Test the idle screen**

Navigate to the "Sin destino" tab. Confirm:
- The explore icon and correct title are shown
- The idle message explains the feature
- The "Start recording" button is visible

- [ ] **Step 4: Test the recording flow (requires GPS or emulator location)**

If running on a device/emulator with GPS:
1. Tap "Start recording"
2. Verify the map appears with telemetry being drawn
3. Verify elapsed time, distance, and speed update in real time
4. Verify the GPS point counter increments

- [ ] **Step 5: Test the finish flow**

1. Tap "Finish ride"
2. Verify the summary screen appears with map, distance, max speed, avg speed
3. Verify "Save as reusable route" button appears
4. Tap it, fill in name/description/difficulty, and save
5. Navigate to the Editor tab and confirm the new route appears

- [ ] **Step 6: Test "New ride"**

1. Finish a ride without saving as route (tap "New ride")
2. Verify the screen returns to idle state

- [ ] **Step 7: Test history persistence**

Navigate to History and verify previous sessions are unaffected. The free rides are stored separately and don't appear in the session history (they are a different data model).

---

### Task 12: Run Full Test Suite

**Files:** None (verification only)

- [ ] **Step 1: Run core package tests**

Run: `cd packages/splitway_core && dart test`
Expected: All tests PASS (including the new free ride tests).

- [ ] **Step 2: Run mobile app tests**

Run: `cd movile_app && flutter test`
Expected: All tests PASS (existing + new free ride tests).

- [ ] **Step 3: Run static analysis**

Run: `cd movile_app && flutter analyze`
Expected: No errors.

- [ ] **Step 4: Commit any fixes if tests revealed issues**

```bash
git add -A
git commit -m "fix: address test/lint issues from free ride integration"
```

---

## Summary of Changes

| Layer | What changes |
|-------|-------------|
| **splitway_core** | 3 new files: `FreeRideRun` model, `FreeRideSnapshot` value object, `FreeRideEngine` (lightweight tracking without route) |
| **Database** | Migration v3: `free_rides` + `free_ride_telemetry` tables |
| **Repository** | 5 new methods: `saveFreeRideRun`, `getFreeRideRun`, `getAllFreeRides`, `updateFreeRideMetadata`, `deleteFreeRide` |
| **Feature** | New `free_ride/` folder: `FreeRideController` (ChangeNotifier) + `FreeRideScreen` (3 views: idle, recording, finished) |
| **Navigation** | 4th tab "Sin destino" inserted between Session and History |
| **i18n** | ~20 new strings in EN + ES ARB files |
| **Conversion** | `saveAsRoute()` creates a `RouteTemplate` from the recorded telemetry using Douglas-Peucker simplification |
