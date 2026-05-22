# Velocidad Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a drag-strip-style speed measurement feature to the Splitway mobile app. Users pick a vehicle and metrics (0-100, 1/4 mile, reaction time, top speed, etc.), run a countdown with false-start detection, and see live results that persist to local SQLite, Supabase, and the History screen.

**Architecture:** A self-contained `features/speed/` module with its own controller, four screens (Setup → Ready → Session → Detail), and a `SpeedMeasurementService` that fuses high-rate GPS with the IMU (`sensors_plus`) using a 1-D Kalman filter. Persistence goes through a new `SpeedSessionRepository` (local SQLite + Supabase mirror). The existing `SyncService` is extended to push/pull the new table.

**Tech Stack:** Flutter 3.5+, Dart, `geolocator`, `sensors_plus` (new dep), `audioplayers`, `wakelock_plus`, `sqflite`, `supabase_flutter`, `go_router`, `intl`.

**Spec:** `docs/superpowers/specs/2026-05-22-velocidad-design.md`

---

## Task 1: Add dependencies and audio assets

**Files:**
- Modify: `movile_app/pubspec.yaml`
- Create: `movile_app/assets/sounds/beep.mp3`
- Create: `movile_app/assets/sounds/beep_go.mp3`
- Create: `movile_app/assets/sounds/beep_false.mp3`

- [ ] **Step 1: Add `sensors_plus` dependency**

In `movile_app/pubspec.yaml`, under `dependencies:`, after `audioplayers: ^6.1.0`, add:

```yaml
  sensors_plus: ^6.1.0
```

- [ ] **Step 2: Run `flutter pub get`**

```bash
cd movile_app && flutter pub get
```

Expected: dependency resolved without errors.

- [ ] **Step 3: Add three placeholder sound files**

Generate three short MP3 placeholders (sine tones, ~150 ms). Any tool works; one option using `ffmpeg`:

```bash
cd movile_app/assets/sounds
ffmpeg -f lavfi -i "sine=frequency=880:duration=0.12" -ac 1 -ar 22050 beep.mp3
ffmpeg -f lavfi -i "sine=frequency=440:duration=0.30" -ac 1 -ar 22050 beep_go.mp3
ffmpeg -f lavfi -i "sine=frequency=220:duration=0.40" -ac 1 -ar 22050 beep_false.mp3
```

If `ffmpeg` is unavailable, place any short royalty-free MP3 with these names. The audio files are bundled by the existing `- assets/sounds/` entry in `pubspec.yaml`.

- [ ] **Step 4: Commit**

```bash
git add movile_app/pubspec.yaml movile_app/pubspec.lock movile_app/assets/sounds/beep.mp3 movile_app/assets/sounds/beep_go.mp3 movile_app/assets/sounds/beep_false.mp3
git commit -m "chore(deps): add sensors_plus and Velocidad beep assets"
```

---

## Task 2: Supabase migration for `speed_sessions`

**Files:**
- Create: `supabase/migrations/20260522000000_add_speed_sessions.sql`

- [ ] **Step 1: Create the migration file**

```sql
-- Speed sessions: drag-strip-style measurements per vehicle.

CREATE TABLE public.speed_sessions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  vehicle_id UUID REFERENCES public.vehicles(id) ON DELETE SET NULL,
  name TEXT NOT NULL,
  selected_metrics TEXT[] NOT NULL,
  results JSONB NOT NULL DEFAULT '{}'::jsonb,
  countdown_seconds INTEGER NOT NULL,
  is_partial BOOLEAN NOT NULL DEFAULT false,
  started_at TIMESTAMPTZ NOT NULL,
  finished_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  deleted_at TIMESTAMPTZ
);

ALTER TABLE public.speed_sessions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view own speed sessions"
  ON public.speed_sessions FOR SELECT
  USING (auth.uid() = user_id);

CREATE POLICY "Users can insert own speed sessions"
  ON public.speed_sessions FOR INSERT
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update own speed sessions"
  ON public.speed_sessions FOR UPDATE
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can delete own speed sessions"
  ON public.speed_sessions FOR DELETE
  USING (auth.uid() = user_id);

CREATE INDEX idx_speed_sessions_user_created
  ON public.speed_sessions(user_id, created_at DESC);
```

- [ ] **Step 2: Apply locally (if Supabase CLI is configured)**

```bash
cd supabase && supabase db reset
```

Expected: migration applied without errors. If the CLI is not configured, the migration will be applied on next remote sync.

- [ ] **Step 3: Commit**

```bash
git add supabase/migrations/20260522000000_add_speed_sessions.sql
git commit -m "feat(db): add speed_sessions table with RLS"
```

---

## Task 3: SpeedMetric enum and helpers

**Files:**
- Create: `movile_app/lib/src/services/speed/speed_metric.dart`
- Test: `movile_app/test/services/speed/speed_metric_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/services/speed/speed_metric_test.dart
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
```

- [ ] **Step 2: Run the test, expect failure (file missing)**

```bash
cd movile_app && flutter test test/services/speed/speed_metric_test.dart
```

Expected: error — `speed_metric.dart` does not exist.

- [ ] **Step 3: Implement `SpeedMetric`**

```dart
// lib/src/services/speed/speed_metric.dart
enum SpeedMetric {
  reactionTime,
  sixtyFoot,
  eighthMile,
  quarterMile,
  zeroTo50,
  zeroTo100,
  zeroTo200,
  topSpeed;

  String get id => name;

  static SpeedMetric? fromId(String value) {
    for (final m in SpeedMetric.values) {
      if (m.id == value) return m;
    }
    return null;
  }

  bool get isTimeBased => this != SpeedMetric.topSpeed;

  String formatValue(double? value) {
    if (value == null) return '-';
    if (this == SpeedMetric.topSpeed) {
      return '${value.round()} km/h';
    }
    return '${value.toStringAsFixed(2)} s';
  }
}
```

- [ ] **Step 4: Run tests, expect pass**

```bash
cd movile_app && flutter test test/services/speed/speed_metric_test.dart
```

Expected: all 5 tests pass.

- [ ] **Step 5: Commit**

```bash
git add movile_app/lib/src/services/speed/speed_metric.dart movile_app/test/services/speed/speed_metric_test.dart
git commit -m "feat(speed): add SpeedMetric enum with formatting"
```

---

## Task 4: SpeedSession model

**Files:**
- Create: `movile_app/lib/src/services/speed/speed_session.dart`
- Test: `movile_app/test/services/speed/speed_session_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/services/speed/speed_session_test.dart
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

    test('defaultName uses vehicle name + timestamp', () {
      final ts = DateTime.parse('2026-05-22T14:08:09.000');
      final name = SpeedSession.defaultName('Civic Type R', ts);
      expect(name, 'Civic Type R-2026-05-22_14-08-09');
    });
  });
}
```

- [ ] **Step 2: Run test, expect failure**

```bash
cd movile_app && flutter test test/services/speed/speed_session_test.dart
```

Expected: file missing.

- [ ] **Step 3: Implement `SpeedSession`**

```dart
// lib/src/services/speed/speed_session.dart
import 'package:intl/intl.dart';

import 'speed_metric.dart';

class SpeedSession {
  const SpeedSession({
    required this.id,
    required this.userId,
    required this.vehicleId,
    required this.name,
    required this.selectedMetrics,
    required this.results,
    required this.countdownSeconds,
    required this.isPartial,
    required this.startedAt,
    required this.finishedAt,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });

  final String id;
  final String? userId;
  final String? vehicleId;
  final String name;
  final Set<SpeedMetric> selectedMetrics;
  final Map<SpeedMetric, double?> results;
  final int countdownSeconds;
  final bool isPartial;
  final DateTime startedAt;
  final DateTime? finishedAt;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  static String defaultName(String vehicleName, DateTime ts) {
    final fmt = DateFormat('yyyy-MM-dd_HH-mm-ss');
    return '$vehicleName-${fmt.format(ts)}';
  }

  factory SpeedSession.fromJson(Map<String, dynamic> json) {
    final metricsRaw = (json['selected_metrics'] as List).cast<String>();
    final selected = metricsRaw
        .map(SpeedMetric.fromId)
        .whereType<SpeedMetric>()
        .toSet();

    final resultsRaw = (json['results'] as Map?) ?? const {};
    final results = <SpeedMetric, double?>{};
    for (final entry in resultsRaw.entries) {
      final metric = SpeedMetric.fromId(entry.key as String);
      if (metric != null) {
        final v = entry.value;
        results[metric] = v == null ? null : (v as num).toDouble();
      }
    }

    return SpeedSession(
      id: json['id'] as String,
      userId: json['user_id'] as String?,
      vehicleId: json['vehicle_id'] as String?,
      name: json['name'] as String,
      selectedMetrics: selected,
      results: results,
      countdownSeconds: (json['countdown_seconds'] as num).toInt(),
      isPartial: (json['is_partial'] as bool?) ?? false,
      startedAt: DateTime.parse(json['started_at'] as String),
      finishedAt: json['finished_at'] == null
          ? null
          : DateTime.parse(json['finished_at'] as String),
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
      deletedAt: json['deleted_at'] == null
          ? null
          : DateTime.parse(json['deleted_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'vehicle_id': vehicleId,
      'name': name,
      'selected_metrics': selectedMetrics.map((m) => m.id).toList(),
      'results': {
        for (final entry in results.entries) entry.key.id: entry.value,
      },
      'countdown_seconds': countdownSeconds,
      'is_partial': isPartial,
      'started_at': startedAt.toUtc().toIso8601String(),
      'finished_at': finishedAt?.toUtc().toIso8601String(),
      'created_at': createdAt.toUtc().toIso8601String(),
      'updated_at': updatedAt.toUtc().toIso8601String(),
      'deleted_at': deletedAt?.toUtc().toIso8601String(),
    };
  }
}
```

- [ ] **Step 4: Run tests, expect pass**

```bash
cd movile_app && flutter test test/services/speed/speed_session_test.dart
```

- [ ] **Step 5: Commit**

```bash
git add movile_app/lib/src/services/speed/speed_session.dart movile_app/test/services/speed/speed_session_test.dart
git commit -m "feat(speed): add SpeedSession model with JSON serialization"
```

---

## Task 5: Local SQLite schema bump + speed_session_dao

**Files:**
- Modify: `movile_app/lib/src/data/local/splitway_local_database.dart`
- Create: `movile_app/lib/src/data/local/speed_session_dao.dart`
- Test: `movile_app/test/data/local/speed_session_dao_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/data/local/speed_session_dao_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_common_ffi.dart';
import 'package:splitway_mobile/src/data/local/speed_session_dao.dart';
import 'package:splitway_mobile/src/data/local/splitway_local_database.dart';
import 'package:splitway_mobile/src/services/speed/speed_metric.dart';
import 'package:splitway_mobile/src/services/speed/speed_session.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late SplitwayLocalDatabase db;
  late SpeedSessionDao dao;

  setUp(() async {
    db = await SplitwayLocalDatabase.open(overridePath: inMemoryDatabasePath);
    dao = SpeedSessionDao(db.raw);
  });

  tearDown(() async => db.close());

  test('insert and listForUser', () async {
    final now = DateTime.now();
    final session = SpeedSession(
      id: 's1',
      userId: 'u1',
      vehicleId: 'v1',
      name: 'Run 1',
      selectedMetrics: {SpeedMetric.zeroTo100, SpeedMetric.topSpeed},
      results: {SpeedMetric.zeroTo100: 5.4, SpeedMetric.topSpeed: 180.0},
      countdownSeconds: 3,
      isPartial: false,
      startedAt: now,
      finishedAt: now.add(const Duration(seconds: 20)),
      createdAt: now,
      updatedAt: now,
    );

    await dao.upsert(session);
    final all = await dao.listForUser('u1');
    expect(all, hasLength(1));
    expect(all.first.id, 's1');
    expect(all.first.results[SpeedMetric.zeroTo100], 5.4);
  });

  test('soft delete excludes from listForUser', () async {
    final now = DateTime.now();
    final session = SpeedSession(
      id: 's2',
      userId: 'u1',
      vehicleId: null,
      name: 'x',
      selectedMetrics: {SpeedMetric.topSpeed},
      results: {SpeedMetric.topSpeed: 100.0},
      countdownSeconds: 3,
      isPartial: false,
      startedAt: now,
      finishedAt: now,
      createdAt: now,
      updatedAt: now,
    );
    await dao.upsert(session);
    await dao.softDelete('s2');
    final all = await dao.listForUser('u1');
    expect(all, isEmpty);
  });
}
```

- [ ] **Step 2: Run test, expect failure (file missing, schema missing)**

```bash
cd movile_app && flutter test test/data/local/speed_session_dao_test.dart
```

- [ ] **Step 3: Bump local DB schema and add the speed_sessions table**

In `movile_app/lib/src/data/local/splitway_local_database.dart`:

Change `static const int _schemaVersion = 7;` to `static const int _schemaVersion = 8;`.

At the end of `_migrate` (after the `if (from < 7 ...)` block), add:

```dart
    if (from < 8 && to >= 8) {
      await db.execute('''
        CREATE TABLE speed_sessions (
          id TEXT PRIMARY KEY NOT NULL,
          user_id TEXT,
          vehicle_id TEXT,
          name TEXT NOT NULL,
          selected_metrics TEXT NOT NULL,
          results_json TEXT NOT NULL,
          countdown_seconds INTEGER NOT NULL,
          is_partial INTEGER NOT NULL DEFAULT 0,
          started_at INTEGER NOT NULL,
          finished_at INTEGER,
          created_at INTEGER NOT NULL,
          updated_at INTEGER NOT NULL,
          deleted_at INTEGER
        )
      ''');
      await db.execute(
        'CREATE INDEX idx_speed_sessions_user_created ON speed_sessions(user_id, created_at DESC)',
      );
    }
```

- [ ] **Step 4: Create the DAO**

```dart
// lib/src/data/local/speed_session_dao.dart
import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../../services/speed/speed_metric.dart';
import '../../services/speed/speed_session.dart';

class SpeedSessionDao {
  SpeedSessionDao(this._db);

  final Database _db;

  Future<void> upsert(SpeedSession session) async {
    await _db.insert(
      'speed_sessions',
      _toRow(session),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<SpeedSession>> listForUser(String userId) async {
    final rows = await _db.query(
      'speed_sessions',
      where: 'user_id = ? AND deleted_at IS NULL',
      whereArgs: [userId],
      orderBy: 'created_at DESC',
    );
    return rows.map(_fromRow).toList();
  }

  Future<SpeedSession?> getById(String id) async {
    final rows = await _db.query(
      'speed_sessions',
      where: 'id = ? AND deleted_at IS NULL',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _fromRow(rows.first);
  }

  Future<void> softDelete(String id) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.update(
      'speed_sessions',
      {'deleted_at': now, 'updated_at': now},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Map<String, Object?> _toRow(SpeedSession s) => {
        'id': s.id,
        'user_id': s.userId,
        'vehicle_id': s.vehicleId,
        'name': s.name,
        'selected_metrics':
            s.selectedMetrics.map((m) => m.id).toList().join(','),
        'results_json': jsonEncode({
          for (final entry in s.results.entries) entry.key.id: entry.value,
        }),
        'countdown_seconds': s.countdownSeconds,
        'is_partial': s.isPartial ? 1 : 0,
        'started_at': s.startedAt.millisecondsSinceEpoch,
        'finished_at': s.finishedAt?.millisecondsSinceEpoch,
        'created_at': s.createdAt.millisecondsSinceEpoch,
        'updated_at': s.updatedAt.millisecondsSinceEpoch,
        'deleted_at': s.deletedAt?.millisecondsSinceEpoch,
      };

  SpeedSession _fromRow(Map<String, Object?> row) {
    final metricsCsv = row['selected_metrics'] as String;
    final selected = metricsCsv.isEmpty
        ? <SpeedMetric>{}
        : metricsCsv
            .split(',')
            .map(SpeedMetric.fromId)
            .whereType<SpeedMetric>()
            .toSet();

    final rawResults =
        jsonDecode(row['results_json'] as String) as Map<String, dynamic>;
    final results = <SpeedMetric, double?>{};
    for (final entry in rawResults.entries) {
      final m = SpeedMetric.fromId(entry.key);
      if (m != null) {
        final v = entry.value;
        results[m] = v == null ? null : (v as num).toDouble();
      }
    }

    return SpeedSession(
      id: row['id'] as String,
      userId: row['user_id'] as String?,
      vehicleId: row['vehicle_id'] as String?,
      name: row['name'] as String,
      selectedMetrics: selected,
      results: results,
      countdownSeconds: row['countdown_seconds'] as int,
      isPartial: (row['is_partial'] as int) == 1,
      startedAt:
          DateTime.fromMillisecondsSinceEpoch(row['started_at'] as int),
      finishedAt: row['finished_at'] == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(row['finished_at'] as int),
      createdAt:
          DateTime.fromMillisecondsSinceEpoch(row['created_at'] as int),
      updatedAt:
          DateTime.fromMillisecondsSinceEpoch(row['updated_at'] as int),
      deletedAt: row['deleted_at'] == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(row['deleted_at'] as int),
    );
  }
}
```

- [ ] **Step 5: Run tests, expect pass**

```bash
cd movile_app && flutter test test/data/local/speed_session_dao_test.dart
```

- [ ] **Step 6: Commit**

```bash
git add movile_app/lib/src/data/local/splitway_local_database.dart movile_app/lib/src/data/local/speed_session_dao.dart movile_app/test/data/local/speed_session_dao_test.dart
git commit -m "feat(db): bump schema to 8 with speed_sessions table and DAO"
```

---

## Task 6: SpeedRepository (local + Supabase mirror)

**Files:**
- Create: `movile_app/lib/src/data/repositories/speed_repository.dart`
- Test: `movile_app/test/data/repositories/speed_repository_test.dart`

- [ ] **Step 1: Write the failing test (local-only path)**

```dart
// test/data/repositories/speed_repository_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_common_ffi.dart';
import 'package:splitway_mobile/src/data/local/speed_session_dao.dart';
import 'package:splitway_mobile/src/data/local/splitway_local_database.dart';
import 'package:splitway_mobile/src/data/repositories/speed_repository.dart';
import 'package:splitway_mobile/src/services/speed/speed_metric.dart';
import 'package:splitway_mobile/src/services/speed/speed_session.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late SplitwayLocalDatabase db;
  late SpeedRepository repo;

  setUp(() async {
    db = await SplitwayLocalDatabase.open(overridePath: inMemoryDatabasePath);
    repo = SpeedRepository(
      localDao: SpeedSessionDao(db.raw),
      supabase: null,
    );
  });

  tearDown(() async => db.close());

  test('save persists locally and listForUser returns it', () async {
    final now = DateTime.now();
    final session = SpeedSession(
      id: 'a',
      userId: 'u',
      vehicleId: null,
      name: 'n',
      selectedMetrics: {SpeedMetric.topSpeed},
      results: {SpeedMetric.topSpeed: 90.0},
      countdownSeconds: 3,
      isPartial: false,
      startedAt: now,
      finishedAt: now,
      createdAt: now,
      updatedAt: now,
    );
    await repo.save(session);
    final list = await repo.listForUser('u');
    expect(list.single.name, 'n');
  });
}
```

- [ ] **Step 2: Run test, expect failure**

```bash
cd movile_app && flutter test test/data/repositories/speed_repository_test.dart
```

- [ ] **Step 3: Implement the repository**

```dart
// lib/src/data/repositories/speed_repository.dart
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/speed/speed_session.dart';
import '../local/speed_session_dao.dart';

class SpeedRepository {
  SpeedRepository({required this.localDao, required this.supabase});

  final SpeedSessionDao localDao;
  final SupabaseClient? supabase;

  Future<void> save(SpeedSession session) async {
    await localDao.upsert(session);
    final client = supabase;
    if (client != null && client.auth.currentUser != null) {
      try {
        await client.from('speed_sessions').upsert(session.toJson());
      } catch (_) {
        // Network failure or RLS — keep local copy; SyncService will retry.
      }
    }
  }

  Future<List<SpeedSession>> listForUser(String userId) =>
      localDao.listForUser(userId);

  Future<SpeedSession?> getById(String id) => localDao.getById(id);

  Future<void> softDelete(String id) async {
    await localDao.softDelete(id);
    final client = supabase;
    if (client != null && client.auth.currentUser != null) {
      try {
        await client
            .from('speed_sessions')
            .update({'deleted_at': DateTime.now().toUtc().toIso8601String()})
            .eq('id', id);
      } catch (_) {/* sync will reconcile */}
    }
  }
}
```

- [ ] **Step 4: Run tests**

```bash
cd movile_app && flutter test test/data/repositories/speed_repository_test.dart
```

- [ ] **Step 5: Commit**

```bash
git add movile_app/lib/src/data/repositories/speed_repository.dart movile_app/test/data/repositories/speed_repository_test.dart
git commit -m "feat(speed): add SpeedRepository (local + Supabase mirror)"
```

---

## Task 7: BeepPlayer

**Files:**
- Create: `movile_app/lib/src/services/speed/beep_player.dart`

- [ ] **Step 1: Implement the player (no test — pure side effect on audio hardware)**

```dart
// lib/src/services/speed/beep_player.dart
import 'package:audioplayers/audioplayers.dart';

class BeepPlayer {
  BeepPlayer();

  final AudioPlayer _tick = AudioPlayer();
  final AudioPlayer _go = AudioPlayer();
  final AudioPlayer _falseStart = AudioPlayer();

  Future<void> preload() async {
    await _tick.setSource(AssetSource('sounds/beep.mp3'));
    await _go.setSource(AssetSource('sounds/beep_go.mp3'));
    await _falseStart.setSource(AssetSource('sounds/beep_false.mp3'));
    await _tick.setReleaseMode(ReleaseMode.stop);
    await _go.setReleaseMode(ReleaseMode.stop);
    await _falseStart.setReleaseMode(ReleaseMode.stop);
  }

  Future<void> tick() async {
    await _tick.stop();
    await _tick.resume();
  }

  Future<void> go() async {
    await _go.stop();
    await _go.resume();
  }

  Future<void> falseStart() async {
    await _falseStart.stop();
    await _falseStart.resume();
  }

  Future<void> dispose() async {
    await _tick.dispose();
    await _go.dispose();
    await _falseStart.dispose();
  }
}
```

- [ ] **Step 2: Commit**

```bash
git add movile_app/lib/src/services/speed/beep_player.dart
git commit -m "feat(speed): add BeepPlayer for countdown and false-start cues"
```

---

## Task 8: SpeedSample data class and SpeedMeasurementService skeleton

**Files:**
- Create: `movile_app/lib/src/services/speed/speed_sample.dart`
- Create: `movile_app/lib/src/services/speed/speed_measurement_service.dart`
- Test: `movile_app/test/services/speed/speed_measurement_service_test.dart`

- [ ] **Step 1: Write the failing test (skeleton: arm, start, manual sample injection)**

```dart
// test/services/speed/speed_measurement_service_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:splitway_mobile/src/services/speed/speed_measurement_service.dart';
import 'package:splitway_mobile/src/services/speed/speed_metric.dart';
import 'package:splitway_mobile/src/services/speed/speed_sample.dart';

void main() {
  group('SpeedMeasurementService (skeleton)', () {
    late SpeedMeasurementService svc;

    setUp(() {
      svc = SpeedMeasurementService.forTesting(
        targets: {SpeedMetric.topSpeed},
      );
    });

    tearDown(() => svc.dispose());

    test('starts with all targets unresolved (null)', () {
      svc.start();
      expect(svc.results.value[SpeedMetric.topSpeed], null);
    });

    test('topSpeed updates as samples come in', () {
      svc.start();
      svc.debugInjectSample(SpeedSample(
        tSinceStart: const Duration(milliseconds: 100),
        speedKmh: 50,
        distanceM: 1.5,
        accelMs2: 4,
      ));
      svc.debugInjectSample(SpeedSample(
        tSinceStart: const Duration(milliseconds: 200),
        speedKmh: 80,
        distanceM: 3.7,
        accelMs2: 4,
      ));
      svc.stop();
      expect(svc.results.value[SpeedMetric.topSpeed], 80.0);
    });
  });
}
```

- [ ] **Step 2: Create `SpeedSample`**

```dart
// lib/src/services/speed/speed_sample.dart
class SpeedSample {
  const SpeedSample({
    required this.tSinceStart,
    required this.speedKmh,
    required this.distanceM,
    required this.accelMs2,
  });

  final Duration tSinceStart;
  final double speedKmh;
  final double distanceM;
  final double accelMs2;
}
```

- [ ] **Step 3: Create the service skeleton (no fusion yet — only manual injection)**

```dart
// lib/src/services/speed/speed_measurement_service.dart
import 'dart:async';

import 'package:flutter/foundation.dart';

import 'speed_metric.dart';
import 'speed_sample.dart';

enum SpeedPhase { idle, armed, running, finished }

class FalseStartDetected {
  const FalseStartDetected();
}

class SpeedMeasurementService {
  SpeedMeasurementService({required this.targets});

  SpeedMeasurementService.forTesting({required this.targets})
      : _isTestMode = true;

  final Set<SpeedMetric> targets;
  final bool _isTestMode = false;

  final ValueNotifier<Map<SpeedMetric, double?>> results = ValueNotifier(
    {},
  );
  final ValueNotifier<SpeedPhase> phase = ValueNotifier(SpeedPhase.idle);
  final ValueNotifier<double> instantaneousKmh = ValueNotifier(0);
  final StreamController<FalseStartDetected> _falseStart =
      StreamController.broadcast();

  Stream<FalseStartDetected> get falseStartStream => _falseStart.stream;

  SpeedSample? _previousSample;
  bool _topSpeedDirty = false;

  void arm() {
    phase.value = SpeedPhase.armed;
    _resetResults();
  }

  void start() {
    phase.value = SpeedPhase.running;
    _resetResults();
    _previousSample = null;
  }

  void stop() {
    phase.value = SpeedPhase.finished;
  }

  void cancel() {
    phase.value = SpeedPhase.idle;
  }

  void dispose() {
    _falseStart.close();
    results.dispose();
    phase.dispose();
    instantaneousKmh.dispose();
  }

  @visibleForTesting
  void debugInjectSample(SpeedSample sample) {
    if (!_isTestMode) return;
    _onSample(sample);
  }

  void _resetResults() {
    final base = <SpeedMetric, double?>{
      for (final t in targets) t: null,
    };
    results.value = base;
  }

  void _onSample(SpeedSample s) {
    instantaneousKmh.value = s.speedKmh;
    if (phase.value == SpeedPhase.running) {
      _detectMilestones(s);
    }
    _previousSample = s;
  }

  void _detectMilestones(SpeedSample s) {
    final updated = Map<SpeedMetric, double?>.from(results.value);

    if (targets.contains(SpeedMetric.topSpeed)) {
      final current = updated[SpeedMetric.topSpeed] ?? 0;
      if (s.speedKmh > current) {
        updated[SpeedMetric.topSpeed] = s.speedKmh;
        _topSpeedDirty = true;
      }
    }

    if (!_mapEquals(updated, results.value)) {
      results.value = updated;
    }
  }

  bool _mapEquals(
    Map<SpeedMetric, double?> a,
    Map<SpeedMetric, double?> b,
  ) {
    if (a.length != b.length) return false;
    for (final k in a.keys) {
      if (a[k] != b[k]) return false;
    }
    return true;
  }
}
```

- [ ] **Step 4: Run tests, expect pass**

```bash
cd movile_app && flutter test test/services/speed/speed_measurement_service_test.dart
```

- [ ] **Step 5: Commit**

```bash
git add movile_app/lib/src/services/speed/speed_sample.dart movile_app/lib/src/services/speed/speed_measurement_service.dart movile_app/test/services/speed/speed_measurement_service_test.dart
git commit -m "feat(speed): add SpeedMeasurementService skeleton with topSpeed"
```

---

## Task 9: Milestone detection (distance and velocity crossings)

**Files:**
- Modify: `movile_app/lib/src/services/speed/speed_measurement_service.dart`
- Modify: `movile_app/test/services/speed/speed_measurement_service_test.dart`

- [ ] **Step 1: Write the new failing tests**

Append to the existing test file (inside the same `main()`):

```dart
  group('SpeedMeasurementService milestones', () {
    test('zeroTo100 resolved by linear interpolation', () {
      final svc = SpeedMeasurementService.forTesting(
        targets: {SpeedMetric.zeroTo100},
      );
      svc.start();
      svc.debugInjectSample(SpeedSample(
        tSinceStart: const Duration(milliseconds: 4000),
        speedKmh: 90,
        distanceM: 30,
        accelMs2: 8,
      ));
      svc.debugInjectSample(SpeedSample(
        tSinceStart: const Duration(milliseconds: 4500),
        speedKmh: 110,
        distanceM: 50,
        accelMs2: 8,
      ));
      svc.stop();
      // 100 km/h crossed between 4000 and 4500ms;
      // linear interp: 4000 + (100-90)/(110-90) * 500 = 4250 ms => 4.25 s
      expect(svc.results.value[SpeedMetric.zeroTo100], closeTo(4.25, 1e-6));
      svc.dispose();
    });

    test('sixtyFoot resolved by distance crossing', () {
      final svc = SpeedMeasurementService.forTesting(
        targets: {SpeedMetric.sixtyFoot},
      );
      svc.start();
      svc.debugInjectSample(SpeedSample(
        tSinceStart: const Duration(milliseconds: 1500),
        speedKmh: 40,
        distanceM: 10,
        accelMs2: 5,
      ));
      svc.debugInjectSample(SpeedSample(
        tSinceStart: const Duration(milliseconds: 2500),
        speedKmh: 60,
        distanceM: 30,
        accelMs2: 5,
      ));
      svc.stop();
      // 18.29 m crossed between 1500 and 2500 ms;
      // interp: 1500 + (18.29-10)/(30-10) * 1000 = 1500 + 414.5 = 1914.5 ms => 1.9145
      expect(
        svc.results.value[SpeedMetric.sixtyFoot],
        closeTo(1.9145, 1e-3),
      );
      svc.dispose();
    });

    test('quarterMile resolved by distance crossing', () {
      final svc = SpeedMeasurementService.forTesting(
        targets: {SpeedMetric.quarterMile},
      );
      svc.start();
      svc.debugInjectSample(SpeedSample(
        tSinceStart: const Duration(milliseconds: 10000),
        speedKmh: 180,
        distanceM: 380,
        accelMs2: 4,
      ));
      svc.debugInjectSample(SpeedSample(
        tSinceStart: const Duration(milliseconds: 11000),
        speedKmh: 200,
        distanceM: 430,
        accelMs2: 4,
      ));
      svc.stop();
      // 402.34 crossed: 10000 + (402.34-380)/(430-380) * 1000 = 10000 + 446.8 = 10446.8
      expect(
        svc.results.value[SpeedMetric.quarterMile],
        closeTo(10.4468, 1e-3),
      );
      svc.dispose();
    });
  });
```

- [ ] **Step 2: Run tests, expect failures (only topSpeed implemented)**

```bash
cd movile_app && flutter test test/services/speed/speed_measurement_service_test.dart
```

- [ ] **Step 3: Implement milestone detection**

In `speed_measurement_service.dart`, add these constants at the top of the class:

```dart
  static const double _sixtyFeetMeters = 18.29;
  static const double _eighthMileMeters = 201.168;
  static const double _quarterMileMeters = 402.336;
```

Replace `_detectMilestones` with:

```dart
  void _detectMilestones(SpeedSample s) {
    final prev = _previousSample;
    final updated = Map<SpeedMetric, double?>.from(results.value);

    // top speed
    if (targets.contains(SpeedMetric.topSpeed)) {
      final current = updated[SpeedMetric.topSpeed] ?? 0;
      if (s.speedKmh > current) updated[SpeedMetric.topSpeed] = s.speedKmh;
    }

    if (prev != null) {
      _resolveDistanceCrossing(
        updated, prev, s, SpeedMetric.sixtyFoot, _sixtyFeetMeters,
      );
      _resolveDistanceCrossing(
        updated, prev, s, SpeedMetric.eighthMile, _eighthMileMeters,
      );
      _resolveDistanceCrossing(
        updated, prev, s, SpeedMetric.quarterMile, _quarterMileMeters,
      );
      _resolveSpeedCrossing(updated, prev, s, SpeedMetric.zeroTo50, 50);
      _resolveSpeedCrossing(updated, prev, s, SpeedMetric.zeroTo100, 100);
      _resolveSpeedCrossing(updated, prev, s, SpeedMetric.zeroTo200, 200);
    }

    if (!_mapEquals(updated, results.value)) {
      results.value = updated;
    }
  }

  void _resolveDistanceCrossing(
    Map<SpeedMetric, double?> out,
    SpeedSample prev,
    SpeedSample curr,
    SpeedMetric metric,
    double thresholdM,
  ) {
    if (!targets.contains(metric)) return;
    if (out[metric] != null) return;
    if (prev.distanceM < thresholdM && curr.distanceM >= thresholdM) {
      final ratio = (thresholdM - prev.distanceM) /
          (curr.distanceM - prev.distanceM);
      final dtMs = curr.tSinceStart.inMicroseconds -
          prev.tSinceStart.inMicroseconds;
      final tMicros = prev.tSinceStart.inMicroseconds + ratio * dtMs;
      out[metric] = tMicros / 1e6;
    }
  }

  void _resolveSpeedCrossing(
    Map<SpeedMetric, double?> out,
    SpeedSample prev,
    SpeedSample curr,
    SpeedMetric metric,
    double thresholdKmh,
  ) {
    if (!targets.contains(metric)) return;
    if (out[metric] != null) return;
    if (prev.speedKmh < thresholdKmh && curr.speedKmh >= thresholdKmh) {
      final ratio = (thresholdKmh - prev.speedKmh) /
          (curr.speedKmh - prev.speedKmh);
      final dtMicros = curr.tSinceStart.inMicroseconds -
          prev.tSinceStart.inMicroseconds;
      final tMicros = prev.tSinceStart.inMicroseconds + ratio * dtMicros;
      out[metric] = tMicros / 1e6;
    }
  }
```

- [ ] **Step 4: Run tests, expect pass**

```bash
cd movile_app && flutter test test/services/speed/speed_measurement_service_test.dart
```

- [ ] **Step 5: Add reaction time detection**

Append the failing test first:

```dart
    test('reactionTime resolved when sustained speed exceeds threshold', () {
      final svc = SpeedMeasurementService.forTesting(
        targets: {SpeedMetric.reactionTime},
      );
      svc.start();
      // Below threshold first
      svc.debugInjectSample(SpeedSample(
        tSinceStart: const Duration(milliseconds: 100),
        speedKmh: 0.2,
        distanceM: 0.01,
        accelMs2: 0,
      ));
      // Cross threshold at 250ms
      svc.debugInjectSample(SpeedSample(
        tSinceStart: const Duration(milliseconds: 250),
        speedKmh: 1,
        distanceM: 0.05,
        accelMs2: 4,
      ));
      // Sustain for 150ms
      svc.debugInjectSample(SpeedSample(
        tSinceStart: const Duration(milliseconds: 420),
        speedKmh: 4,
        distanceM: 0.3,
        accelMs2: 4,
      ));
      svc.stop();
      // Reaction logged at first crossing time: 0.25 s
      expect(
        svc.results.value[SpeedMetric.reactionTime],
        closeTo(0.25, 1e-3),
      );
      svc.dispose();
    });
```

Run, expect failure, then add fields and logic in the service:

Add to class fields:

```dart
  static const double _reactionSpeedKmh = 0.5;
  static const Duration _reactionSustain = Duration(milliseconds: 150);
  Duration? _reactionCandidateTime;
```

In `_resetResults`, also clear `_reactionCandidateTime = null;`.

In `_detectMilestones`, before the distance/speed crossing block, add:

```dart
    if (targets.contains(SpeedMetric.reactionTime) &&
        updated[SpeedMetric.reactionTime] == null) {
      if (s.speedKmh >= _reactionSpeedKmh) {
        _reactionCandidateTime ??= s.tSinceStart;
        final sustained = s.tSinceStart - _reactionCandidateTime!;
        if (sustained >= _reactionSustain) {
          updated[SpeedMetric.reactionTime] =
              _reactionCandidateTime!.inMicroseconds / 1e6;
        }
      } else {
        _reactionCandidateTime = null;
      }
    }
```

Run tests again, expect pass.

- [ ] **Step 6: Commit**

```bash
git add movile_app/lib/src/services/speed/speed_measurement_service.dart movile_app/test/services/speed/speed_measurement_service_test.dart
git commit -m "feat(speed): detect distance, speed and reaction-time milestones"
```

---

## Task 10: False-start detection in arm mode

**Files:**
- Modify: `movile_app/lib/src/services/speed/speed_measurement_service.dart`
- Modify: `movile_app/test/services/speed/speed_measurement_service_test.dart`

- [ ] **Step 1: Write the failing test**

Add to the test file:

```dart
  group('SpeedMeasurementService false start', () {
    test('emits FalseStartDetected when speed sustained over threshold in arm', () async {
      final svc = SpeedMeasurementService.forTesting(
        targets: {SpeedMetric.zeroTo100},
      );
      final events = <FalseStartDetected>[];
      svc.falseStartStream.listen(events.add);

      svc.arm();
      svc.debugInjectSample(SpeedSample(
        tSinceStart: const Duration(milliseconds: 50),
        speedKmh: 2,
        distanceM: 0.1,
        accelMs2: 2,
      ));
      svc.debugInjectSample(SpeedSample(
        tSinceStart: const Duration(milliseconds: 220),
        speedKmh: 3,
        distanceM: 0.3,
        accelMs2: 2,
      ));
      await Future<void>.delayed(Duration.zero);
      expect(events, hasLength(1));
      svc.dispose();
    });

    test('does not trigger on brief sub-threshold jitter', () async {
      final svc = SpeedMeasurementService.forTesting(
        targets: {SpeedMetric.zeroTo100},
      );
      final events = <FalseStartDetected>[];
      svc.falseStartStream.listen(events.add);

      svc.arm();
      svc.debugInjectSample(SpeedSample(
        tSinceStart: const Duration(milliseconds: 50),
        speedKmh: 0.4,
        distanceM: 0.0,
        accelMs2: 0.2,
      ));
      await Future<void>.delayed(Duration.zero);
      expect(events, isEmpty);
      svc.dispose();
    });
  });
```

- [ ] **Step 2: Run tests, expect failure**

- [ ] **Step 3: Add false-start logic to the service**

Add fields:

```dart
  static const double _falseStartSpeedKmh = 1.5;
  static const double _falseStartAccelMs2 = 1.5;
  static const Duration _falseStartSustain = Duration(milliseconds: 150);
  Duration? _falseStartCandidateTime;
```

In `arm()`, also reset:

```dart
    _falseStartCandidateTime = null;
```

Modify `_onSample` to branch:

```dart
  void _onSample(SpeedSample s) {
    instantaneousKmh.value = s.speedKmh;
    switch (phase.value) {
      case SpeedPhase.armed:
        _checkFalseStart(s);
        break;
      case SpeedPhase.running:
        _detectMilestones(s);
        break;
      case SpeedPhase.idle:
      case SpeedPhase.finished:
        break;
    }
    _previousSample = s;
  }

  void _checkFalseStart(SpeedSample s) {
    final exceeded = s.speedKmh >= _falseStartSpeedKmh ||
        s.accelMs2 >= _falseStartAccelMs2;
    if (!exceeded) {
      _falseStartCandidateTime = null;
      return;
    }
    _falseStartCandidateTime ??= s.tSinceStart;
    final sustained = s.tSinceStart - _falseStartCandidateTime!;
    if (sustained >= _falseStartSustain) {
      _falseStart.add(const FalseStartDetected());
      // Don't fire again until rearmed.
      phase.value = SpeedPhase.idle;
    }
  }
```

- [ ] **Step 4: Run tests, expect pass**

```bash
cd movile_app && flutter test test/services/speed/speed_measurement_service_test.dart
```

- [ ] **Step 5: Commit**

```bash
git add movile_app/lib/src/services/speed/speed_measurement_service.dart movile_app/test/services/speed/speed_measurement_service_test.dart
git commit -m "feat(speed): detect false start during arm phase"
```

---

## Task 11: Sensor wiring (GPS + IMU) with simple fusion

**Files:**
- Modify: `movile_app/lib/src/services/speed/speed_measurement_service.dart`

The fusion is intentionally simple to ship: GPS speed dominates whenever a fresh GPS sample is available; the IMU is used for short-term integration between GPS ticks. This is enough for the milestones at the precision the spec calls out. A full Kalman filter is out of scope.

- [ ] **Step 1: Add live subscriptions**

Add imports:

```dart
import 'package:geolocator/geolocator.dart';
import 'package:sensors_plus/sensors_plus.dart';
```

Add fields:

```dart
  StreamSubscription<Position>? _gpsSub;
  StreamSubscription<AccelerometerEvent>? _accelSub;

  double _liveSpeedKmh = 0;
  double _liveDistanceM = 0;
  double _liveAccelMs2 = 0;
  Stopwatch _sessionClock = Stopwatch();
  DateTime? _lastImuTickAt;
```

Add a `liveStart()` method that subscribes to real sensors and emits synthetic `SpeedSample`s via `_onSample`. Keep `start()` as the pure-state setter for tests; live mode calls `liveStart()`.

```dart
  Future<void> liveStart() async {
    _sessionClock = Stopwatch()..start();
    _lastImuTickAt = DateTime.now();
    _liveSpeedKmh = 0;
    _liveDistanceM = 0;
    start();

    _gpsSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 0,
      ),
    ).listen((p) {
      if (p.speed >= 0) {
        _liveSpeedKmh = p.speed * 3.6;
      }
    });

    _accelSub = accelerometerEventStream().listen((e) {
      final now = DateTime.now();
      final dt = (now.difference(_lastImuTickAt!)).inMicroseconds / 1e6;
      _lastImuTickAt = now;
      if (dt <= 0 || dt > 0.5) return;
      // Use vector magnitude minus gravity as a crude longitudinal estimate.
      final mag = (e.x * e.x + e.y * e.y + e.z * e.z);
      final accel = (mag > 0 ? (mag - 9.81 * 9.81).abs() : 0).toDouble();
      _liveAccelMs2 = accel < 0.5 ? 0 : accel * 0.1;
      // Integrate distance from current live speed (m/s)
      final speedMs = _liveSpeedKmh / 3.6;
      _liveDistanceM += speedMs * dt;
      _onSample(SpeedSample(
        tSinceStart: Duration(microseconds: _sessionClock.elapsedMicroseconds),
        speedKmh: _liveSpeedKmh,
        distanceM: _liveDistanceM,
        accelMs2: _liveAccelMs2,
      ));
    });
  }

  Future<void> liveArm() async {
    arm();
    _sessionClock = Stopwatch()..start();
    _lastImuTickAt = DateTime.now();
    _gpsSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 0,
      ),
    ).listen((p) {
      if (p.speed >= 0) _liveSpeedKmh = p.speed * 3.6;
    });
    _accelSub = accelerometerEventStream().listen((e) {
      final now = DateTime.now();
      final dt = (now.difference(_lastImuTickAt!)).inMicroseconds / 1e6;
      _lastImuTickAt = now;
      if (dt <= 0 || dt > 0.5) return;
      final mag = (e.x * e.x + e.y * e.y + e.z * e.z);
      final accel = (mag > 0 ? (mag - 9.81 * 9.81).abs() : 0).toDouble();
      _liveAccelMs2 = accel < 0.5 ? 0 : accel * 0.1;
      _onSample(SpeedSample(
        tSinceStart: Duration(microseconds: _sessionClock.elapsedMicroseconds),
        speedKmh: _liveSpeedKmh,
        distanceM: _liveDistanceM,
        accelMs2: _liveAccelMs2,
      ));
    });
  }

  Future<void> liveStop() async {
    await _gpsSub?.cancel();
    await _accelSub?.cancel();
    _gpsSub = null;
    _accelSub = null;
    _sessionClock.stop();
    stop();
  }
```

Update `dispose()`:

```dart
  Future<void> disposeAsync() async {
    await _gpsSub?.cancel();
    await _accelSub?.cancel();
    _falseStart.close();
    results.dispose();
    phase.dispose();
    instantaneousKmh.dispose();
  }
```

Keep the synchronous `dispose()` from before for tests.

- [ ] **Step 2: Manual smoke check**

```bash
cd movile_app && flutter analyze
```

Expected: no errors.

- [ ] **Step 3: Commit**

```bash
git add movile_app/lib/src/services/speed/speed_measurement_service.dart
git commit -m "feat(speed): wire live GPS+IMU sample emission"
```

---

## Task 12: L10n strings for the Velocidad feature

**Files:**
- Modify: `movile_app/lib/l10n/app_en.arb`
- Modify: `movile_app/lib/l10n/app_es.arb`

- [ ] **Step 1: Append the following keys to `app_en.arb`** (before the closing `}`)

```json
  ,
  "navSpeed": "Speed",
  "drawerSpeed": "Speed",
  "speedSetupTitle": "Speed",
  "speedSetupVehicleSection": "Vehicle",
  "speedSetupMetricsSection": "What to measure",
  "speedSetupCountdownSection": "Countdown",
  "speedSetupNameSection": "Name (optional)",
  "speedSetupViewSection": "Results view",
  "speedSetupViewList": "List",
  "speedSetupViewGrid": "Grid",
  "speedSetupContinue": "Continue",
  "speedSetupSecondsValue": "{n}s",
  "@speedSetupSecondsValue": { "placeholders": { "n": { "type": "int" } } },
  "speedReadyMessage": "When you are ready, press Start",
  "speedReadyStart": "START",
  "speedSessionGo": "GO!",
  "speedFinishedTitle": "Session complete",
  "speedFinishedSave": "Save",
  "speedFinishedDiscard": "Discard",
  "speedFalseStartTitle": "FALSE START",
  "speedFalseStartSubtitle": "You moved before the final beep",
  "speedFalseStartRetry": "RETRY",
  "speedFalseStartCancel": "Cancel",
  "speedMetricReactionTime": "Reaction time",
  "speedMetricSixtyFoot": "60 ft",
  "speedMetricEighthMile": "1/8 mile",
  "speedMetricQuarterMile": "1/4 mile",
  "speedMetricZeroTo50": "0-50",
  "speedMetricZeroTo100": "0-100",
  "speedMetricZeroTo200": "0-200",
  "speedMetricTopSpeed": "Top speed",
  "speedHistoryTab": "Speed",
  "speedHistoryEmpty": "No speed sessions yet"
```

- [ ] **Step 2: Append parallel keys to `app_es.arb`** (Spanish translations)

```json
  ,
  "navSpeed": "Velocidad",
  "drawerSpeed": "Velocidad",
  "speedSetupTitle": "Velocidad",
  "speedSetupVehicleSection": "Vehículo",
  "speedSetupMetricsSection": "Qué medir",
  "speedSetupCountdownSection": "Cuenta atrás",
  "speedSetupNameSection": "Nombre (opcional)",
  "speedSetupViewSection": "Vista de resultados",
  "speedSetupViewList": "Lista",
  "speedSetupViewGrid": "Cuadrícula",
  "speedSetupContinue": "Continuar",
  "speedSetupSecondsValue": "{n}s",
  "@speedSetupSecondsValue": { "placeholders": { "n": { "type": "int" } } },
  "speedReadyMessage": "Cuando estés listo, pulsa Start",
  "speedReadyStart": "START",
  "speedSessionGo": "¡YA!",
  "speedFinishedTitle": "Sesión completada",
  "speedFinishedSave": "Guardar",
  "speedFinishedDiscard": "Descartar",
  "speedFalseStartTitle": "SALIDA EN FALSO",
  "speedFalseStartSubtitle": "Has arrancado antes del pitido final",
  "speedFalseStartRetry": "REINTENTAR",
  "speedFalseStartCancel": "Cancelar",
  "speedMetricReactionTime": "Tiempo de reacción",
  "speedMetricSixtyFoot": "60 pies",
  "speedMetricEighthMile": "1/8 milla",
  "speedMetricQuarterMile": "1/4 milla",
  "speedMetricZeroTo50": "0-50",
  "speedMetricZeroTo100": "0-100",
  "speedMetricZeroTo200": "0-200",
  "speedMetricTopSpeed": "Velocidad máxima",
  "speedHistoryTab": "Velocidad",
  "speedHistoryEmpty": "Aún no hay sesiones de velocidad"
```

- [ ] **Step 3: Regenerate l10n bindings**

```bash
cd movile_app && flutter gen-l10n
```

Expected: `app_localizations*.dart` regenerated.

- [ ] **Step 4: Commit**

```bash
git add movile_app/lib/l10n/app_en.arb movile_app/lib/l10n/app_es.arb movile_app/lib/l10n/app_localizations*.dart
git commit -m "feat(l10n): add Velocidad strings (en/es)"
```

---

## Task 13: Speed metric label extension

**Files:**
- Create: `movile_app/lib/src/services/speed/speed_metric_labels.dart`

- [ ] **Step 1: Add label extension**

```dart
// lib/src/services/speed/speed_metric_labels.dart
import 'package:splitway_mobile/l10n/app_localizations.dart';

import 'speed_metric.dart';

extension SpeedMetricLabel on SpeedMetric {
  String label(AppLocalizations l) {
    switch (this) {
      case SpeedMetric.reactionTime:
        return l.speedMetricReactionTime;
      case SpeedMetric.sixtyFoot:
        return l.speedMetricSixtyFoot;
      case SpeedMetric.eighthMile:
        return l.speedMetricEighthMile;
      case SpeedMetric.quarterMile:
        return l.speedMetricQuarterMile;
      case SpeedMetric.zeroTo50:
        return l.speedMetricZeroTo50;
      case SpeedMetric.zeroTo100:
        return l.speedMetricZeroTo100;
      case SpeedMetric.zeroTo200:
        return l.speedMetricZeroTo200;
      case SpeedMetric.topSpeed:
        return l.speedMetricTopSpeed;
    }
  }
}
```

- [ ] **Step 2: Commit**

```bash
git add movile_app/lib/src/services/speed/speed_metric_labels.dart
git commit -m "feat(speed): add localized labels for SpeedMetric"
```

---

## Task 14: Metric tile widgets (list + grid)

**Files:**
- Create: `movile_app/lib/src/features/speed/widgets/speed_metric_tile.dart`
- Create: `movile_app/lib/src/features/speed/widgets/speed_metric_card.dart`

- [ ] **Step 1: Add `speed_metric_tile.dart`**

```dart
// lib/src/features/speed/widgets/speed_metric_tile.dart
import 'package:flutter/material.dart';

import '../../../services/speed/speed_metric.dart';
import '../../../services/speed/speed_metric_labels.dart';
import 'package:splitway_mobile/l10n/app_localizations.dart';

class SpeedMetricTile extends StatelessWidget {
  const SpeedMetricTile({
    super.key,
    required this.metric,
    required this.value,
  });

  final SpeedMetric metric;
  final double? value;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              metric.formatValue(value),
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Text(
            metric.label(l),
            style: TextStyle(
              fontSize: 14,
              color: Theme.of(context).hintColor,
            ),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 2: Add `speed_metric_card.dart`**

```dart
// lib/src/features/speed/widgets/speed_metric_card.dart
import 'package:flutter/material.dart';

import '../../../services/speed/speed_metric.dart';
import '../../../services/speed/speed_metric_labels.dart';
import 'package:splitway_mobile/l10n/app_localizations.dart';

class SpeedMetricCard extends StatelessWidget {
  const SpeedMetricCard({
    super.key,
    required this.metric,
    required this.value,
  });

  final SpeedMetric metric;
  final double? value;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            metric.label(l),
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).hintColor,
            ),
          ),
          const Spacer(),
          Text(
            metric.formatValue(value),
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 3: Commit**

```bash
git add movile_app/lib/src/features/speed/widgets/speed_metric_tile.dart movile_app/lib/src/features/speed/widgets/speed_metric_card.dart
git commit -m "feat(speed): add metric tile and card widgets"
```

---

## Task 15: Countdown overlay and false-start overlay

**Files:**
- Create: `movile_app/lib/src/features/speed/widgets/countdown_overlay.dart`
- Create: `movile_app/lib/src/features/speed/widgets/false_start_overlay.dart`

- [ ] **Step 1: Countdown overlay**

```dart
// lib/src/features/speed/widgets/countdown_overlay.dart
import 'package:flutter/material.dart';
import 'package:splitway_mobile/l10n/app_localizations.dart';

class CountdownOverlay extends StatelessWidget {
  const CountdownOverlay({super.key, required this.value});

  /// `value` is null on the GO frame.
  final int? value;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final text = value == null ? l.speedSessionGo : '$value';
    return IgnorePointer(
      child: Center(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          child: Text(
            text,
            key: ValueKey(text),
            style: const TextStyle(
              fontSize: 180,
              fontWeight: FontWeight.w900,
              color: Colors.white,
              shadows: [
                Shadow(blurRadius: 24, color: Colors.black54),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: False-start overlay**

```dart
// lib/src/features/speed/widgets/false_start_overlay.dart
import 'package:flutter/material.dart';
import 'package:splitway_mobile/l10n/app_localizations.dart';

class FalseStartOverlay extends StatelessWidget {
  const FalseStartOverlay({
    super.key,
    required this.onRetry,
    required this.onCancel,
  });

  final VoidCallback onRetry;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Container(
      color: Colors.red.withValues(alpha: 0.85),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(),
              Text(
                l.speedFalseStartTitle,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 56,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                l.speedFalseStartSubtitle,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 18,
                  color: Colors.white70,
                ),
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: FilledButton(
                  onPressed: onRetry,
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.red,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    l.speedFalseStartRetry,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: onCancel,
                child: Text(
                  l.speedFalseStartCancel,
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 3: Commit**

```bash
git add movile_app/lib/src/features/speed/widgets/countdown_overlay.dart movile_app/lib/src/features/speed/widgets/false_start_overlay.dart
git commit -m "feat(speed): add countdown and false-start overlays"
```

---

## Task 16: Speed setup screen

**Files:**
- Create: `movile_app/lib/src/features/speed/speed_setup_screen.dart`
- Test: `movile_app/test/features/speed/speed_setup_screen_test.dart`

The setup screen builds the configuration that drives the session. The Continue button stays disabled until both a vehicle is chosen and at least one metric is selected.

- [ ] **Step 1: Write a widget test that asserts the Continue button disabled state**

```dart
// test/features/speed/speed_setup_screen_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:splitway_mobile/l10n/app_localizations.dart';
import 'package:splitway_mobile/src/features/speed/speed_setup_screen.dart';

void main() {
  testWidgets('Continue disabled without metrics', (tester) async {
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const SpeedSetupScreen(
        garageService: null,
        onContinue: _noop,
      ),
    ));
    await tester.pumpAndSettle();
    final btn = find.byKey(const Key('speed-continue'));
    expect(tester.widget<FilledButton>(btn).onPressed, isNull);
  });
}

void _noop(SpeedSetupResult _) {}
```

- [ ] **Step 2: Implement the setup screen**

```dart
// lib/src/features/speed/speed_setup_screen.dart
import 'package:flutter/material.dart';
import 'package:splitway_mobile/l10n/app_localizations.dart';

import '../../services/garage/garage_service.dart';
import '../../services/garage/vehicle.dart';
import '../../services/speed/speed_metric.dart';
import '../../services/speed/speed_metric_labels.dart';

enum SpeedView { list, grid }

class SpeedSetupResult {
  const SpeedSetupResult({
    required this.vehicle,
    required this.metrics,
    required this.countdownSeconds,
    required this.name,
    required this.view,
  });

  final Vehicle vehicle;
  final Set<SpeedMetric> metrics;
  final int countdownSeconds;
  final String? name;
  final SpeedView view;
}

class SpeedSetupScreen extends StatefulWidget {
  const SpeedSetupScreen({
    super.key,
    required this.garageService,
    required this.onContinue,
  });

  final GarageService? garageService;
  final void Function(SpeedSetupResult) onContinue;

  @override
  State<SpeedSetupScreen> createState() => _SpeedSetupScreenState();
}

class _SpeedSetupScreenState extends State<SpeedSetupScreen> {
  Vehicle? _vehicle;
  final Set<SpeedMetric> _metrics = {};
  int _countdown = 3;
  final TextEditingController _name = TextEditingController();
  SpeedView _view = SpeedView.list;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  bool get _canContinue => _vehicle != null && _metrics.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l.speedSetupTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _section(l.speedSetupVehicleSection, _vehiclePicker()),
          _section(l.speedSetupMetricsSection, _metricChecks(l)),
          _section(l.speedSetupCountdownSection, _countdownChips(l)),
          _section(l.speedSetupNameSection, TextField(
            controller: _name,
            decoration: const InputDecoration(border: OutlineInputBorder()),
          )),
          _section(l.speedSetupViewSection, _viewChips(l)),
          const SizedBox(height: 24),
          FilledButton(
            key: const Key('speed-continue'),
            onPressed: _canContinue ? _go : null,
            child: Text(l.speedSetupContinue),
          ),
        ],
      ),
    );
  }

  Widget _vehiclePicker() {
    final vehicles = widget.garageService?.vehicles ?? const <Vehicle>[];
    if (vehicles.isEmpty) {
      return Text(AppLocalizations.of(context).speedSetupVehicleSection);
    }
    return DropdownButton<Vehicle>(
      value: _vehicle,
      isExpanded: true,
      hint: Text(AppLocalizations.of(context).speedSetupVehicleSection),
      items: vehicles
          .where((v) => v.type != VehicleType.bicycle) // motorized only
          .map(
            (v) => DropdownMenuItem(value: v, child: Text(v.name)),
          )
          .toList(),
      onChanged: (v) => setState(() => _vehicle = v),
    );
  }

  Widget _metricChecks(AppLocalizations l) {
    return Column(
      children: SpeedMetric.values.map((m) {
        return CheckboxListTile(
          title: Text(m.label(l)),
          value: _metrics.contains(m),
          onChanged: (v) {
            setState(() {
              if (v == true) {
                _metrics.add(m);
              } else {
                _metrics.remove(m);
              }
            });
          },
        );
      }).toList(),
    );
  }

  Widget _countdownChips(AppLocalizations l) {
    return Wrap(
      spacing: 8,
      children: [3, 5, 10].map((n) {
        return ChoiceChip(
          label: Text(l.speedSetupSecondsValue(n)),
          selected: _countdown == n,
          onSelected: (_) => setState(() => _countdown = n),
        );
      }).toList(),
    );
  }

  Widget _viewChips(AppLocalizations l) {
    return Wrap(
      spacing: 8,
      children: [
        ChoiceChip(
          label: Text(l.speedSetupViewList),
          selected: _view == SpeedView.list,
          onSelected: (_) => setState(() => _view = SpeedView.list),
        ),
        ChoiceChip(
          label: Text(l.speedSetupViewGrid),
          selected: _view == SpeedView.grid,
          onSelected: (_) => setState(() => _view = SpeedView.grid),
        ),
      ],
    );
  }

  Widget _section(String title, Widget child) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }

  void _go() {
    widget.onContinue(SpeedSetupResult(
      vehicle: _vehicle!,
      metrics: Set.unmodifiable(_metrics),
      countdownSeconds: _countdown,
      name: _name.text.trim().isEmpty ? null : _name.text.trim(),
      view: _view,
    ));
  }
}
```

- [ ] **Step 3: Run tests, expect pass**

```bash
cd movile_app && flutter test test/features/speed/speed_setup_screen_test.dart
```

- [ ] **Step 4: Commit**

```bash
git add movile_app/lib/src/features/speed/speed_setup_screen.dart movile_app/test/features/speed/speed_setup_screen_test.dart
git commit -m "feat(speed): add SpeedSetupScreen"
```

---

## Task 17: Ready screen

**Files:**
- Create: `movile_app/lib/src/features/speed/speed_ready_screen.dart`

- [ ] **Step 1: Implement**

```dart
// lib/src/features/speed/speed_ready_screen.dart
import 'package:flutter/material.dart';
import 'package:splitway_mobile/l10n/app_localizations.dart';

class SpeedReadyScreen extends StatelessWidget {
  const SpeedReadyScreen({super.key, required this.onStart});

  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l.speedSetupTitle)),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const Spacer(),
              Text(
                l.speedReadyMessage,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                height: 64,
                child: FilledButton(
                  onPressed: onStart,
                  style: FilledButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: Text(
                    l.speedReadyStart,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 2,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Commit**

```bash
git add movile_app/lib/src/features/speed/speed_ready_screen.dart
git commit -m "feat(speed): add SpeedReadyScreen"
```

---

## Task 18: Speed session controller

**Files:**
- Create: `movile_app/lib/src/features/speed/speed_session_controller.dart`

The controller owns the phase machine, the measurement service, the beep player, and the countdown timer. Screens listen via `ChangeNotifier`.

- [ ] **Step 1: Implement**

```dart
// lib/src/features/speed/speed_session_controller.dart
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import '../../data/repositories/speed_repository.dart';
import '../../services/speed/beep_player.dart';
import '../../services/speed/speed_measurement_service.dart';
import '../../services/speed/speed_metric.dart';
import '../../services/speed/speed_session.dart';

enum SpeedScreenPhase { ready, arming, countdown, running, falseStart, finished }

class SpeedSessionController extends ChangeNotifier {
  SpeedSessionController({
    required this.userId,
    required this.vehicleId,
    required this.vehicleName,
    required this.metrics,
    required this.countdownSeconds,
    required this.userProvidedName,
    required this.repository,
  })  : service = SpeedMeasurementService(targets: metrics),
        beep = BeepPlayer();

  final String? userId;
  final String? vehicleId;
  final String vehicleName;
  final Set<SpeedMetric> metrics;
  final int countdownSeconds;
  final String? userProvidedName;
  final SpeedRepository repository;

  final SpeedMeasurementService service;
  final BeepPlayer beep;

  SpeedScreenPhase phase = SpeedScreenPhase.ready;
  int countdownValue = 0;
  DateTime? startedAt;
  DateTime? finishedAt;

  StreamSubscription<FalseStartDetected>? _falseStartSub;
  Timer? _countdownTimer;

  Future<void> begin() async {
    await beep.preload();
    _falseStartSub = service.falseStartStream.listen((_) {
      _onFalseStart();
    });
    await _arm();
  }

  Future<void> _arm() async {
    phase = SpeedScreenPhase.arming;
    countdownValue = countdownSeconds;
    notifyListeners();
    await service.liveArm();
    phase = SpeedScreenPhase.countdown;
    notifyListeners();
    _startCountdown();
  }

  void _startCountdown() {
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) async {
      if (countdownValue > 0) {
        await beep.tick();
        countdownValue--;
        notifyListeners();
      }
      if (countdownValue == 0) {
        _countdownTimer?.cancel();
        await beep.go();
        await _go();
      }
    });
  }

  Future<void> _go() async {
    startedAt = DateTime.now();
    phase = SpeedScreenPhase.running;
    notifyListeners();
    await service.liveStop(); // stop arm subscriptions
    await service.liveStart();
    service.results.addListener(_maybeFinish);
  }

  void _maybeFinish() {
    final allResolved =
        metrics.every((m) => service.results.value[m] != null);
    if (allResolved) {
      _finish();
    }
    notifyListeners();
  }

  Future<void> _finish() async {
    if (phase == SpeedScreenPhase.finished) return;
    finishedAt = DateTime.now();
    phase = SpeedScreenPhase.finished;
    await service.liveStop();
    notifyListeners();
  }

  Future<void> _onFalseStart() async {
    _countdownTimer?.cancel();
    await service.liveStop();
    await beep.falseStart();
    HapticFeedback.heavyImpact();
    phase = SpeedScreenPhase.falseStart;
    notifyListeners();
  }

  Future<void> retry() async {
    await _arm();
  }

  Future<void> manualStop() async {
    await _finish();
  }

  Future<SpeedSession> saveResult() async {
    final id = const Uuid().v4();
    final now = DateTime.now();
    final results = Map<SpeedMetric, double?>.from(service.results.value);
    final session = SpeedSession(
      id: id,
      userId: userId,
      vehicleId: vehicleId,
      name: userProvidedName ?? SpeedSession.defaultName(vehicleName, now),
      selectedMetrics: metrics,
      results: results,
      countdownSeconds: countdownSeconds,
      isPartial: !metrics.every((m) => results[m] != null),
      startedAt: startedAt ?? now,
      finishedAt: finishedAt ?? now,
      createdAt: now,
      updatedAt: now,
    );
    await repository.save(session);
    return session;
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _falseStartSub?.cancel();
    service.results.removeListener(_maybeFinish);
    service.disposeAsync();
    beep.dispose();
    super.dispose();
  }
}
```

- [ ] **Step 2: Commit**

```bash
git add movile_app/lib/src/features/speed/speed_session_controller.dart
git commit -m "feat(speed): add SpeedSessionController phase machine"
```

---

## Task 19: Speed session screen

**Files:**
- Create: `movile_app/lib/src/features/speed/speed_session_screen.dart`

- [ ] **Step 1: Implement**

```dart
// lib/src/features/speed/speed_session_screen.dart
import 'package:flutter/material.dart';
import 'package:splitway_mobile/l10n/app_localizations.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../services/speed/speed_metric.dart';
import 'speed_session_controller.dart';
import 'speed_setup_screen.dart';
import 'widgets/countdown_overlay.dart';
import 'widgets/false_start_overlay.dart';
import 'widgets/speed_metric_card.dart';
import 'widgets/speed_metric_tile.dart';

class SpeedSessionScreen extends StatefulWidget {
  const SpeedSessionScreen({
    super.key,
    required this.controller,
    required this.view,
    required this.onSaved,
    required this.onDiscarded,
    required this.onCancelled,
  });

  final SpeedSessionController controller;
  final SpeedView view;
  final void Function(String sessionId) onSaved;
  final VoidCallback onDiscarded;
  final VoidCallback onCancelled;

  @override
  State<SpeedSessionScreen> createState() => _SpeedSessionScreenState();
}

class _SpeedSessionScreenState extends State<SpeedSessionScreen> {
  @override
  void initState() {
    super.initState();
    WakelockPlus.enable();
    widget.controller.addListener(_onChange);
    widget.controller.begin();
  }

  void _onChange() => setState(() {});

  @override
  void dispose() {
    widget.controller.removeListener(_onChange);
    WakelockPlus.disable();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                _speedHeader(c),
                Expanded(child: _body(c)),
                if (c.phase == SpeedScreenPhase.finished) _finishBar(c),
              ],
            ),
            if (c.phase == SpeedScreenPhase.countdown ||
                c.phase == SpeedScreenPhase.arming)
              CountdownOverlay(value: c.countdownValue == 0 ? null : c.countdownValue),
            if (c.phase == SpeedScreenPhase.falseStart)
              FalseStartOverlay(
                onRetry: () => c.retry(),
                onCancel: widget.onCancelled,
              ),
          ],
        ),
      ),
    );
  }

  Widget _speedHeader(SpeedSessionController c) {
    return ValueListenableBuilder<double>(
      valueListenable: c.service.instantaneousKmh,
      builder: (_, v, __) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          children: [
            Text(
              '${v.round()}',
              style: const TextStyle(
                fontSize: 96,
                fontWeight: FontWeight.w900,
                color: Colors.white,
                height: 1,
              ),
            ),
            const Text(
              'km/h',
              style: TextStyle(color: Colors.white70, fontSize: 16),
            ),
          ],
        ),
      ),
    );
  }

  Widget _body(SpeedSessionController c) {
    final results = c.service.results.value;
    final metrics = c.metrics.toList();
    if (widget.view == SpeedView.grid) {
      return GridView.builder(
        padding: const EdgeInsets.all(12),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisExtent: 96,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
        ),
        itemCount: metrics.length,
        itemBuilder: (_, i) {
          final m = metrics[i];
          return SpeedMetricCard(metric: m, value: results[m]);
        },
      );
    }
    return ListView.builder(
      itemCount: metrics.length,
      itemBuilder: (_, i) {
        final m = metrics[i];
        return SpeedMetricTile(metric: m, value: results[m]);
      },
    );
  }

  Widget _finishBar(SpeedSessionController c) {
    final l = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: widget.onDiscarded,
              child: Text(l.speedFinishedDiscard),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: FilledButton(
              onPressed: () async {
                final s = await c.saveResult();
                widget.onSaved(s.id);
              },
              child: Text(l.speedFinishedSave),
            ),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 2: Commit**

```bash
git add movile_app/lib/src/features/speed/speed_session_screen.dart
git commit -m "feat(speed): add SpeedSessionScreen with phase rendering"
```

---

## Task 20: Speed session detail (history view)

**Files:**
- Create: `movile_app/lib/src/features/speed/speed_session_detail_screen.dart`

- [ ] **Step 1: Implement**

```dart
// lib/src/features/speed/speed_session_detail_screen.dart
import 'package:flutter/material.dart';
import 'package:splitway_mobile/l10n/app_localizations.dart';

import '../../services/speed/speed_session.dart';
import 'widgets/speed_metric_tile.dart';

class SpeedSessionDetailScreen extends StatelessWidget {
  const SpeedSessionDetailScreen({super.key, required this.session});

  final SpeedSession session;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(title: Text(session.name)),
      body: ListView(
        children: [
          for (final m in session.selectedMetrics)
            SpeedMetricTile(metric: m, value: session.results[m]),
        ],
      ),
    );
  }
}
```

- [ ] **Step 2: Commit**

```bash
git add movile_app/lib/src/features/speed/speed_session_detail_screen.dart
git commit -m "feat(speed): add SpeedSessionDetailScreen"
```

---

## Task 21: Wire routes and drawer

**Files:**
- Modify: `movile_app/lib/src/routing/app_router.dart`
- Modify: `movile_app/lib/src/shared/widgets/app_drawer.dart`
- Modify: `movile_app/lib/src/app.dart`

- [ ] **Step 1: Construct `SpeedRepository` at app startup**

In `movile_app/lib/src/app.dart`, locate where `GarageService` is built and add the `SpeedRepository`:

```dart
final speedRepository = SpeedRepository(
  localDao: SpeedSessionDao(localDb.raw),
  supabase: supabaseClient,
);
```

Pass it into the `AppRouter` constructor (see step 2).

- [ ] **Step 2: Add `/speed` and `/history/speed/:id` routes in `app_router.dart`**

Add to constructor parameters: `SpeedRepository? speedRepository`. Store it and pass through.

Add inside the top-level `routes:` (outside the shell, like `/garage`):

```dart
GoRoute(
  path: '/speed',
  builder: (context, _) => SpeedSetupScreen(
    garageService: garageService,
    onContinue: (result) {
      final controller = SpeedSessionController(
        userId: authService?.currentUser?.id,
        vehicleId: result.vehicle.id,
        vehicleName: result.vehicle.name,
        metrics: result.metrics,
        countdownSeconds: result.countdownSeconds,
        userProvidedName: result.name,
        repository: speedRepository!,
      );
      context.push(
        '/speed/ready',
        extra: _SpeedNavExtra(controller: controller, view: result.view),
      );
    },
  ),
),
GoRoute(
  path: '/speed/ready',
  builder: (context, state) {
    final extra = state.extra as _SpeedNavExtra;
    return SpeedReadyScreen(
      onStart: () => context.pushReplacement(
        '/speed/session',
        extra: extra,
      ),
    );
  },
),
GoRoute(
  path: '/speed/session',
  builder: (context, state) {
    final extra = state.extra as _SpeedNavExtra;
    return SpeedSessionScreen(
      controller: extra.controller,
      view: extra.view,
      onSaved: (id) => context.go('/history/speed/$id'),
      onDiscarded: () => context.go('/routes'),
      onCancelled: () => context.go('/routes'),
    );
  },
),
GoRoute(
  path: '/history/speed/:id',
  builder: (context, state) {
    final id = state.pathParameters['id']!;
    return FutureBuilder(
      future: speedRepository!.getById(id),
      builder: (_, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final s = snap.data;
        if (s == null) {
          return const Scaffold(body: Center(child: Text('Not found')));
        }
        return SpeedSessionDetailScreen(session: s);
      },
    );
  },
),
```

Add a private class at the bottom of `app_router.dart`:

```dart
class _SpeedNavExtra {
  const _SpeedNavExtra({required this.controller, required this.view});
  final SpeedSessionController controller;
  final SpeedView view;
}
```

Add the imports at the top of the file.

- [ ] **Step 3: Add the drawer entry**

In `movile_app/lib/src/shared/widgets/app_drawer.dart`, in the logged-in menu items list (inside `_LoggedInContent.build`), immediately after the existing Garaje `_MenuItem(...)` add:

```dart
_MenuItem(
  icon: Icons.speed_outlined,
  label: l.drawerSpeed,
  onTap: () {
    Navigator.pop(context);
    context.push('/speed');
  },
),
```

- [ ] **Step 4: Run analyze**

```bash
cd movile_app && flutter analyze
```

Expected: no errors.

- [ ] **Step 5: Commit**

```bash
git add movile_app/lib/src/app.dart movile_app/lib/src/routing/app_router.dart movile_app/lib/src/shared/widgets/app_drawer.dart
git commit -m "feat(speed): wire routes and drawer entry"
```

---

## Task 22: History tab for Velocidad

**Files:**
- Modify: `movile_app/lib/src/features/history/history_screen.dart`

History currently lists routes and free rides. We add a new top-level segmented control (or third tab) "Velocidad".

- [ ] **Step 1: Inspect current history layout**

Open `movile_app/lib/src/features/history/history_screen.dart` and identify the existing tab/segment implementation.

- [ ] **Step 2: Add a Velocidad section**

Inject a new pill/tab "Velocidad" that, when selected, calls `speedRepository.listForUser(userId)` and renders the result list. Each item is a `ListTile` with:
- Title: `session.name`
- Subtitle: `vehicleName` (resolved via `garageService`) + " · " + `DateFormat.yMd().add_Hm().format(session.startedAt)`
- Trailing: a small label like `TOP ${topSpeed.round()} km/h` if available, else the first available metric.
- onTap: `context.push('/history/speed/${session.id}')`

If the list is empty, show `l.speedHistoryEmpty`.

Concrete shape of the new branch in the existing `build`:

```dart
if (_selectedFilter == HistoryFilter.speed) {
  return FutureBuilder<List<SpeedSession>>(
    future: widget.speedRepository?.listForUser(userId),
    builder: (_, snap) {
      final items = snap.data ?? const <SpeedSession>[];
      if (items.isEmpty) {
        return Center(child: Text(AppLocalizations.of(context).speedHistoryEmpty));
      }
      return ListView.builder(
        itemCount: items.length,
        itemBuilder: (_, i) {
          final s = items[i];
          final top = s.results[SpeedMetric.topSpeed];
          return ListTile(
            title: Text(s.name),
            subtitle: Text(DateFormat.yMd().add_Hm().format(s.startedAt)),
            trailing: top == null ? null : Text('${top.round()} km/h'),
            onTap: () => context.push('/history/speed/${s.id}'),
          );
        },
      );
    },
  );
}
```

Add `SpeedRepository? speedRepository` to `HistoryScreen`'s constructor, propagate from `AppRouter`.

- [ ] **Step 3: Run analyze and tests**

```bash
cd movile_app && flutter analyze && flutter test
```

- [ ] **Step 4: Commit**

```bash
git add movile_app/lib/src/features/history/history_screen.dart movile_app/lib/src/routing/app_router.dart
git commit -m "feat(history): add Velocidad tab"
```

---

## Task 23: Sync push/pull for speed sessions

**Files:**
- Modify: `movile_app/lib/src/services/sync/sync_service.dart`

- [ ] **Step 1: Inspect existing free_rides push/pull**

Open `sync_service.dart` and locate the `_pushFreeRides()` and `_pullFreeRides()` private methods.

- [ ] **Step 2: Add analogous methods**

Add two new methods mirroring the free-rides pattern:

```dart
Future<void> _pushSpeedSessions() async {
  if (_speedRepository == null || _client == null) return;
  final userId = _client!.auth.currentUser?.id;
  if (userId == null) return;
  final local = await _speedRepository!.listForUser(userId);
  for (final s in local) {
    try {
      await _client!.from('speed_sessions').upsert(s.toJson());
    } catch (_) {/* keep trying next */}
  }
}

Future<void> _pullSpeedSessions() async {
  if (_speedRepository == null || _client == null) return;
  final userId = _client!.auth.currentUser?.id;
  if (userId == null) return;
  final rows = await _client!
      .from('speed_sessions')
      .select()
      .eq('user_id', userId)
      .filter('deleted_at', 'is', null)
      .order('updated_at', ascending: false);
  for (final row in (rows as List)) {
    final s = SpeedSession.fromJson(row as Map<String, dynamic>);
    await _speedRepository!.localDao.upsert(s);
  }
}
```

Call both from the main `sync()` orchestration (next to the free-rides calls).

Inject `SpeedRepository? _speedRepository` via the constructor and propagate from `app.dart`.

- [ ] **Step 3: Commit**

```bash
git add movile_app/lib/src/services/sync/sync_service.dart movile_app/lib/src/app.dart
git commit -m "feat(sync): push/pull speed_sessions"
```

---

## Task 24: Final E2E manual check

- [ ] **Step 1: `flutter pub get && flutter analyze && flutter test`**

```bash
cd movile_app && flutter pub get && flutter analyze && flutter test
```

Expected: no analyzer errors, all tests green.

- [ ] **Step 2: Run on a device or emulator**

```bash
cd movile_app && flutter run -d <device>
```

Manual checks:
- Drawer has a new "Velocidad" entry under Garaje when logged in.
- Setup screen: Continue disabled until vehicle + ≥1 metric selected.
- Ready screen shows the message and Start button.
- Countdown plays beeps; GO plays a different beep.
- Moving the phone vigorously during countdown triggers the red "SALIDA EN FALSO" overlay; Retry restarts the countdown; Cancel goes back to setup.
- After GO, instantaneous km/h refreshes (≥1 Hz).
- Saving navigates to `/history/speed/:id` and the detail screen renders.
- History screen has a new "Velocidad" tab with the saved session listed.

- [ ] **Step 3: Commit any polish fixes**

```bash
git add -A && git commit -m "chore(speed): minor polish from manual run" || true
```

---

## Out of scope (do NOT implement)

- Per-sample raw trace persistence (`telemetry_samples` table for speed).
- Multi-run comparison views.
- Custom user-defined distance/speed targets.
- Imperial-unit display.
- Result image/CSV export.
