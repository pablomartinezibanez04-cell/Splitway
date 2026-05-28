# Logging System Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Centralized logging system for Splitway mobile (Flutter): captures errors/warnings from Supabase, Mapbox/HTTP, auth and tracking, persists them locally in SQLite, syncs them to a Supabase `app_logs` table with a retry queue, and exposes a "Diagnóstico" in-app screen for filtering/sharing.

**Architecture:** A singleton `AppLogger` facade fans out `LogEntry`s to three sinks (`ConsoleSink`, `LocalSink`, `RemoteSink`). `LogUploader` drains pending rows in batches with exponential backoff. Global error handlers (`runZonedGuarded`, `FlutterError.onError`, `PlatformDispatcher.onError`) plus per-call helpers (`logSupabase`, `logHttp`) feed into the facade.

**Tech Stack:** Flutter 3 / Dart 3, `sqflite` (existing local DB), `supabase_flutter`, `http`, new deps `package_info_plus` and `device_info_plus`. Tests with `flutter_test` and `sqflite_common_ffi` (already in dev deps).

**Spec:** `docs/superpowers/specs/2026-05-27-logging-system-design.md`

---

## File map

### New files

```
movile_app/lib/src/services/logging/
  log_level.dart                 # enum LogLevel + helpers
  log_entry.dart                 # immutable model + JSON
  log_sanitizer.dart             # redacts tokens/secrets
  device_metadata.dart           # appVersion / platform / deviceModel cache
  sinks/log_sink.dart            # abstract interface
  sinks/console_sink.dart
  sinks/local_sink.dart          # uses SplitwayLocalDatabase
  sinks/remote_sink.dart         # delegates to LogUploader
  log_uploader.dart              # batched upload with backoff
  app_logger.dart                # singleton facade + init
  http_logging.dart              # logSupabase / logHttp wrappers

movile_app/lib/src/features/logs/
  logs_screen.dart
  log_detail_sheet.dart
  widgets/log_list_tile.dart
  widgets/log_filter_bar.dart

movile_app/test/services/logging/
  log_sanitizer_test.dart
  log_entry_test.dart
  local_sink_test.dart
  app_logger_test.dart
  http_logging_test.dart
  log_uploader_test.dart

movile_app/test/features/logs/
  logs_screen_test.dart

supabase/migrations/
  20260527000000_app_logs.sql
```

### Modified files

- `movile_app/pubspec.yaml` — add `package_info_plus`, `device_info_plus`.
- `movile_app/lib/src/data/local/splitway_local_database.dart` — bump schema to 9, create `app_logs` table.
- `movile_app/lib/src/services/settings/app_settings_controller.dart` — add `minLogLevel`, `remoteLogsEnabled`.
- `movile_app/lib/main.dart` — init `AppLogger` early, wire `runZonedGuarded`, register global handlers, start `LogUploader`.
- `movile_app/lib/src/data/repositories/supabase_repository.dart` — wrap Supabase calls with `logSupabase`.
- `movile_app/lib/src/services/auth/auth_service.dart` — log auth failures.
- `movile_app/lib/src/data/repositories/profile_repository.dart` — wrap with `logSupabase`.
- `movile_app/lib/src/data/repositories/garage_repository.dart` — wrap with `logSupabase`.
- `movile_app/lib/src/data/repositories/speed_repository.dart` — wrap with `logSupabase`.
- `movile_app/lib/src/services/sync/sync_service.dart` — log sync steps' errors.
- `movile_app/lib/src/services/geocoding/reverse_geocoding_service.dart`, `forward_geocoding_service.dart` — wrap with `logHttp`.
- `movile_app/lib/src/services/routing/routing_service.dart`, `elevation_service.dart` — wrap with `logHttp`.
- `movile_app/lib/src/data/services/route_thumbnail_service.dart` — wrap with `logHttp`.
- `movile_app/lib/src/services/tracking/location_service.dart` — log permission denials and stream errors.
- `movile_app/lib/src/routing/app_router.dart` — add `/settings/logs` route.
- `movile_app/lib/src/features/settings/settings_screen.dart` — add "Diagnóstico" entry that navigates to `/settings/logs`.
- `movile_app/lib/l10n/app_localizations_en.dart`, `app_localizations_es.dart`, plus `.arb` source files — add `logsScreen*` strings.

---

## Conventions

- **TDD always:** write the failing test, run it, make it pass with the minimum code, commit.
- **Commits in Spanish are fine** but keep prefixes (`feat`, `test`, `chore`, `docs`, `fix`).
- All Dart imports use single quotes, relative paths inside `lib/src`, trailing commas in multi-line arg lists (project convention — see existing files).
- Tests live under `movile_app/test/...` mirroring `lib/src/...`.
- Run tests with: `cd movile_app && flutter test test/path/to/test.dart` (or `flutter test` for all).
- For SQLite tests on Windows, the project already uses `sqflite_common_ffi` — see `movile_app/test` for examples; if no existing setup, use `sqfliteFfiInit(); databaseFactory = databaseFactoryFfi;` in `setUpAll`.

---

## Task 0: Confirm branch and add dependencies

**Files:**
- Modify: `movile_app/pubspec.yaml`

- [ ] **Step 1: Confirm we're on `feat/logging-system`**

Run:
```
git branch --show-current
```
Expected: `feat/logging-system`. If not, run `git checkout feat/logging-system`.

- [ ] **Step 2: Add `package_info_plus` and `device_info_plus` to `pubspec.yaml`**

Edit `movile_app/pubspec.yaml`. Inside `dependencies:`, after `audioplayers: ^6.1.0`, add:

```yaml
  package_info_plus: ^8.0.0
  device_info_plus: ^11.0.0
```

- [ ] **Step 3: Fetch packages**

Run from `movile_app/`:
```
flutter pub get
```
Expected: ends with `Got dependencies!` (or `Changed N dependencies!`).

- [ ] **Step 4: Commit**

```
git add movile_app/pubspec.yaml movile_app/pubspec.lock
git commit -m "chore(logging): add package_info_plus and device_info_plus deps"
```

---

## Task 1: `LogLevel` enum

**Files:**
- Create: `movile_app/lib/src/services/logging/log_level.dart`
- Test: `movile_app/test/services/logging/log_entry_test.dart` (combined with Task 2 model tests; this task adds the level part)

- [ ] **Step 1: Create the enum file**

`movile_app/lib/src/services/logging/log_level.dart`:

```dart
/// Severity levels for log entries. Ordered from least to most severe so they
/// can be compared numerically (`level.index >= minLevel.index`).
enum LogLevel {
  debug,
  info,
  warning,
  error;

  /// Parses a stored string back to a [LogLevel], defaulting to [error] if
  /// the value is unknown (so we never lose a noisy entry to a typo).
  static LogLevel fromName(String name) {
    for (final level in LogLevel.values) {
      if (level.name == name) return level;
    }
    return LogLevel.error;
  }

  /// Short single-letter code, used in `ConsoleSink` for compact output.
  String get shortCode => switch (this) {
        LogLevel.debug => 'D',
        LogLevel.info => 'I',
        LogLevel.warning => 'W',
        LogLevel.error => 'E',
      };
}
```

- [ ] **Step 2: Sanity-check it compiles**

Run from `movile_app/`:
```
flutter analyze lib/src/services/logging/log_level.dart
```
Expected: `No issues found!`

- [ ] **Step 3: Commit**

```
git add movile_app/lib/src/services/logging/log_level.dart
git commit -m "feat(logging): add LogLevel enum"
```

---

## Task 2: `LogEntry` model

**Files:**
- Create: `movile_app/lib/src/services/logging/log_entry.dart`
- Test: `movile_app/test/services/logging/log_entry_test.dart`

- [ ] **Step 1: Write the failing test**

`movile_app/test/services/logging/log_entry_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:splitway_mobile/src/services/logging/log_entry.dart';
import 'package:splitway_mobile/src/services/logging/log_level.dart';

void main() {
  group('LogEntry', () {
    final ts = DateTime.utc(2026, 5, 27, 12, 30, 15);

    test('toMap/fromMap round-trip preserves all fields', () {
      final entry = LogEntry(
        id: 'abc-123',
        timestamp: ts,
        level: LogLevel.error,
        tag: 'supabase',
        message: 'rpc failed',
        error: 'PostgrestException(...)',
        stackTrace: '#0 main',
        context: {'op': 'upsertSession', 'durationMs': 142},
        appVersion: '0.4.0+1',
        platform: 'android 14',
        deviceModel: 'Pixel 7',
        userId: 'user-1',
      );

      final round = LogEntry.fromMap(entry.toMap());

      expect(round.id, entry.id);
      expect(round.timestamp, entry.timestamp);
      expect(round.level, entry.level);
      expect(round.tag, entry.tag);
      expect(round.message, entry.message);
      expect(round.error, entry.error);
      expect(round.stackTrace, entry.stackTrace);
      expect(round.context, entry.context);
      expect(round.appVersion, entry.appVersion);
      expect(round.platform, entry.platform);
      expect(round.deviceModel, entry.deviceModel);
      expect(round.userId, entry.userId);
    });

    test('toMap stores timestamp as UTC milliseconds', () {
      final entry = _minimal(ts);
      expect(entry.toMap()['timestamp'], ts.millisecondsSinceEpoch);
    });

    test('fromMap handles null optional fields', () {
      final map = _minimal(ts).toMap();
      final round = LogEntry.fromMap(map);
      expect(round.error, isNull);
      expect(round.stackTrace, isNull);
      expect(round.context, isNull);
      expect(round.userId, isNull);
    });
  });
}

LogEntry _minimal(DateTime ts) => LogEntry(
      id: 'id',
      timestamp: ts,
      level: LogLevel.info,
      tag: 'app',
      message: 'm',
      appVersion: '0.0.0',
      platform: 'test',
      deviceModel: 'test',
    );
```

- [ ] **Step 2: Run the test to verify it fails**

Run from `movile_app/`:
```
flutter test test/services/logging/log_entry_test.dart
```
Expected: compile error or test failure because `LogEntry` does not exist yet.

- [ ] **Step 3: Implement `LogEntry`**

`movile_app/lib/src/services/logging/log_entry.dart`:

```dart
import 'dart:convert';

import 'log_level.dart';

/// Immutable log record. Persisted both locally (with `synced`/`sync_attempts`
/// added by `LocalSink`) and remotely (without those columns).
class LogEntry {
  const LogEntry({
    required this.id,
    required this.timestamp,
    required this.level,
    required this.tag,
    required this.message,
    required this.appVersion,
    required this.platform,
    required this.deviceModel,
    this.error,
    this.stackTrace,
    this.context,
    this.userId,
  });

  final String id;
  final DateTime timestamp;
  final LogLevel level;
  final String tag;
  final String message;
  final String? error;
  final String? stackTrace;
  final Map<String, dynamic>? context;
  final String appVersion;
  final String platform;
  final String deviceModel;
  final String? userId;

  /// Returns a map suitable for SQLite or Supabase. `context` is JSON-encoded
  /// to a string column.
  Map<String, dynamic> toMap() => {
        'id': id,
        'timestamp': timestamp.toUtc().millisecondsSinceEpoch,
        'level': level.name,
        'tag': tag,
        'message': message,
        'error': error,
        'stack_trace': stackTrace,
        'context_json': context == null ? null : jsonEncode(context),
        'app_version': appVersion,
        'platform': platform,
        'device_model': deviceModel,
        'user_id': userId,
      };

  /// Map for Supabase REST payload (timestamp as ISO-8601, context as JSON
  /// object rather than string).
  Map<String, dynamic> toRemoteJson() => {
        'id': id,
        'timestamp': timestamp.toUtc().toIso8601String(),
        'level': level.name,
        'tag': tag,
        'message': message,
        'error': error,
        'stack_trace': stackTrace,
        'context': context,
        'app_version': appVersion,
        'platform': platform,
        'device_model': deviceModel,
        'user_id': userId,
      };

  factory LogEntry.fromMap(Map<String, dynamic> m) {
    final ctx = m['context_json'];
    Map<String, dynamic>? parsedContext;
    if (ctx is String && ctx.isNotEmpty) {
      parsedContext = Map<String, dynamic>.from(
        jsonDecode(ctx) as Map<dynamic, dynamic>,
      );
    } else if (ctx is Map) {
      parsedContext = Map<String, dynamic>.from(ctx);
    }

    return LogEntry(
      id: m['id'] as String,
      timestamp: DateTime.fromMillisecondsSinceEpoch(
        m['timestamp'] as int,
        isUtc: true,
      ),
      level: LogLevel.fromName(m['level'] as String),
      tag: m['tag'] as String,
      message: m['message'] as String,
      error: m['error'] as String?,
      stackTrace: m['stack_trace'] as String?,
      context: parsedContext,
      appVersion: m['app_version'] as String,
      platform: m['platform'] as String,
      deviceModel: m['device_model'] as String,
      userId: m['user_id'] as String?,
    );
  }
}
```

- [ ] **Step 4: Run the test to verify it passes**

```
flutter test test/services/logging/log_entry_test.dart
```
Expected: `All tests passed!`

- [ ] **Step 5: Commit**

```
git add movile_app/lib/src/services/logging/log_entry.dart movile_app/test/services/logging/log_entry_test.dart
git commit -m "feat(logging): add LogEntry model with map round-trip"
```

---

## Task 3: `LogSanitizer`

**Files:**
- Create: `movile_app/lib/src/services/logging/log_sanitizer.dart`
- Test: `movile_app/test/services/logging/log_sanitizer_test.dart`

- [ ] **Step 1: Write the failing test**

`movile_app/test/services/logging/log_sanitizer_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:splitway_mobile/src/services/logging/log_sanitizer.dart';

void main() {
  group('LogSanitizer', () {
    test('redacts access_token query param in URLs', () {
      const input =
          'https://api.mapbox.com/geocode?access_token=pk.abc123&q=x';
      final out = LogSanitizer.sanitizeText(input);
      expect(out, isNot(contains('pk.abc123')));
      expect(out, contains('access_token=***REDACTED***'));
    });

    test('redacts apikey and Bearer tokens', () {
      const input = 'Authorization: Bearer eyJabc.def\napikey=supersecret';
      final out = LogSanitizer.sanitizeText(input);
      expect(out, isNot(contains('eyJabc.def')));
      expect(out, isNot(contains('supersecret')));
      expect(out, contains('***REDACTED***'));
    });

    test('returns text unchanged when no secrets present', () {
      const input = 'rpc upsert_session_with_telemetry failed';
      expect(LogSanitizer.sanitizeText(input), input);
    });

    test('sanitizeContext redacts blacklisted keys', () {
      final input = {
        'url': 'https://x.test',
        'password': 'hunter2',
        'token': 'abc',
        'apikey': 'k',
        'authorization': 'Bearer x',
        'refresh_token': 'r',
        'access_token': 'a',
        'safe': 1,
      };
      final out = LogSanitizer.sanitizeContext(input);
      expect(out['password'], '***REDACTED***');
      expect(out['token'], '***REDACTED***');
      expect(out['apikey'], '***REDACTED***');
      expect(out['authorization'], '***REDACTED***');
      expect(out['refresh_token'], '***REDACTED***');
      expect(out['access_token'], '***REDACTED***');
      expect(out['safe'], 1);
      expect(out['url'], 'https://x.test');
    });

    test('sanitizeContext also sanitizes string values for tokens in URLs', () {
      final out = LogSanitizer.sanitizeContext({
        'url': 'https://api.test?access_token=secret&foo=1',
      });
      expect(out['url'], contains('access_token=***REDACTED***'));
      expect(out['url'], contains('foo=1'));
    });

    test('sanitizeContext returns null when input is null', () {
      expect(LogSanitizer.sanitizeContext(null), isNull);
    });
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

```
flutter test test/services/logging/log_sanitizer_test.dart
```
Expected: compile error — class missing.

- [ ] **Step 3: Implement `LogSanitizer`**

`movile_app/lib/src/services/logging/log_sanitizer.dart`:

```dart
/// Redacts secrets from log strings and context maps before persistence.
class LogSanitizer {
  static const String _redacted = '***REDACTED***';

  static const _blacklistKeys = <String>{
    'password',
    'token',
    'apikey',
    'authorization',
    'refresh_token',
    'access_token',
  };

  // Matches `access_token=...`, `apikey=...`, `api_key=...` query/form values.
  static final _queryParamRegex = RegExp(
    r'(access_token|apikey|api_key|token|refresh_token)=([^&\s"\\]+)',
    caseSensitive: false,
  );

  // Matches `Bearer <jwt>` and `Authorization: Bearer ...`.
  static final _bearerRegex = RegExp(
    r'Bearer\s+[A-Za-z0-9._\-]+',
    caseSensitive: false,
  );

  /// Replaces token values in [input] with the redacted placeholder.
  static String sanitizeText(String input) {
    var out = input.replaceAllMapped(
      _queryParamRegex,
      (m) => '${m.group(1)}=$_redacted',
    );
    out = out.replaceAll(_bearerRegex, 'Bearer $_redacted');
    return out;
  }

  /// Returns a new map where blacklisted keys are redacted and string values
  /// are run through [sanitizeText].
  static Map<String, dynamic>? sanitizeContext(Map<String, dynamic>? input) {
    if (input == null) return null;
    final out = <String, dynamic>{};
    for (final entry in input.entries) {
      final keyLower = entry.key.toLowerCase();
      if (_blacklistKeys.contains(keyLower)) {
        out[entry.key] = _redacted;
        continue;
      }
      final value = entry.value;
      if (value is String) {
        out[entry.key] = sanitizeText(value);
      } else {
        out[entry.key] = value;
      }
    }
    return out;
  }
}
```

- [ ] **Step 4: Run the test to verify it passes**

```
flutter test test/services/logging/log_sanitizer_test.dart
```
Expected: `All tests passed!`

- [ ] **Step 5: Commit**

```
git add movile_app/lib/src/services/logging/log_sanitizer.dart movile_app/test/services/logging/log_sanitizer_test.dart
git commit -m "feat(logging): add LogSanitizer for token redaction"
```

---

## Task 4: `DeviceMetadata` provider

**Files:**
- Create: `movile_app/lib/src/services/logging/device_metadata.dart`

There's no easy unit test for the real plugin reads (they require platform channels). We design it with an explicit constructor so consumers can inject fake values in tests.

- [ ] **Step 1: Implement `DeviceMetadata`**

`movile_app/lib/src/services/logging/device_metadata.dart`:

```dart
import 'dart:io' show Platform;

import 'package:device_info_plus/device_info_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Immutable snapshot of app + device identity, captured once at startup
/// and attached to every [LogEntry].
class DeviceMetadata {
  const DeviceMetadata({
    required this.appVersion,
    required this.platform,
    required this.deviceModel,
  });

  final String appVersion;
  final String platform;
  final String deviceModel;

  /// Returns a metadata snapshot, swallowing any plugin failure into safe
  /// fallback strings so logging never breaks because of metadata.
  static Future<DeviceMetadata> capture({
    PackageInfo? packageInfoOverride,
    DeviceInfoPlugin? deviceInfoOverride,
  }) async {
    String appVersion = 'unknown';
    String platform = 'unknown';
    String deviceModel = 'unknown';

    try {
      final pkg = packageInfoOverride ?? await PackageInfo.fromPlatform();
      appVersion = '${pkg.version}+${pkg.buildNumber}';
    } catch (_) {}

    try {
      final info = deviceInfoOverride ?? DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final a = await info.androidInfo;
        platform = 'android ${a.version.release}';
        deviceModel = '${a.manufacturer} ${a.model}'.trim();
      } else if (Platform.isIOS) {
        final i = await info.iosInfo;
        platform = 'ios ${i.systemVersion}';
        deviceModel = i.utsname.machine;
      } else if (Platform.isMacOS) {
        final m = await info.macOsInfo;
        platform = 'macos ${m.osRelease}';
        deviceModel = m.model;
      } else if (Platform.isWindows) {
        final w = await info.windowsInfo;
        platform = 'windows ${w.majorVersion}.${w.minorVersion}';
        deviceModel = w.computerName;
      } else if (Platform.isLinux) {
        final l = await info.linuxInfo;
        platform = 'linux ${l.versionId ?? ''}'.trim();
        deviceModel = l.prettyName;
      }
    } catch (_) {}

    return DeviceMetadata(
      appVersion: appVersion,
      platform: platform,
      deviceModel: deviceModel,
    );
  }
}
```

- [ ] **Step 2: Sanity-check it compiles**

```
flutter analyze lib/src/services/logging/device_metadata.dart
```
Expected: `No issues found!`

- [ ] **Step 3: Commit**

```
git add movile_app/lib/src/services/logging/device_metadata.dart
git commit -m "feat(logging): add DeviceMetadata snapshot helper"
```

---

## Task 5: `LogSink` interface and `ConsoleSink`

**Files:**
- Create: `movile_app/lib/src/services/logging/sinks/log_sink.dart`
- Create: `movile_app/lib/src/services/logging/sinks/console_sink.dart`

- [ ] **Step 1: Create the interface**

`movile_app/lib/src/services/logging/sinks/log_sink.dart`:

```dart
import '../log_entry.dart';

/// A destination for log entries. Implementations must be safe to call from
/// any isolate and must not throw — they should swallow their own errors
/// (we cannot afford to crash the logger).
abstract class LogSink {
  Future<void> write(LogEntry entry);
}
```

- [ ] **Step 2: Implement `ConsoleSink`**

`movile_app/lib/src/services/logging/sinks/console_sink.dart`:

```dart
import 'package:flutter/foundation.dart';

import '../log_entry.dart';
import 'log_sink.dart';

/// Prints log entries to the dev console via `debugPrint`. No-op in release
/// builds to keep the device log clean.
class ConsoleSink implements LogSink {
  const ConsoleSink();

  @override
  Future<void> write(LogEntry entry) async {
    if (kReleaseMode) return;
    final ts = entry.timestamp.toIso8601String();
    final ctx =
        entry.context == null || entry.context!.isEmpty ? '' : ' ${entry.context}';
    debugPrint(
      '[${entry.level.shortCode}] $ts ${entry.tag}: ${entry.message}$ctx',
    );
    if (entry.error != null) debugPrint('  error: ${entry.error}');
    if (entry.stackTrace != null) debugPrint(entry.stackTrace);
  }
}
```

- [ ] **Step 3: Sanity-check**

```
flutter analyze lib/src/services/logging/sinks/
```
Expected: `No issues found!`

- [ ] **Step 4: Commit**

```
git add movile_app/lib/src/services/logging/sinks/log_sink.dart movile_app/lib/src/services/logging/sinks/console_sink.dart
git commit -m "feat(logging): add LogSink interface and ConsoleSink"
```

---

## Task 6: SQLite schema bump for `app_logs`

**Files:**
- Modify: `movile_app/lib/src/data/local/splitway_local_database.dart`

- [ ] **Step 1: Bump schema version and add migration block**

In `movile_app/lib/src/data/local/splitway_local_database.dart`:

Replace the line `static const int _schemaVersion = 8;` with:

```dart
  static const int _schemaVersion = 9;
```

Inside `_migrate`, after the `if (from < 8 && to >= 8) { ... }` block (just before the closing `}` of `_migrate`), append:

```dart
    if (from < 9 && to >= 9) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS app_logs (
          id TEXT PRIMARY KEY NOT NULL,
          timestamp INTEGER NOT NULL,
          level TEXT NOT NULL,
          tag TEXT NOT NULL,
          message TEXT NOT NULL,
          error TEXT,
          stack_trace TEXT,
          context_json TEXT,
          app_version TEXT NOT NULL,
          platform TEXT NOT NULL,
          device_model TEXT NOT NULL,
          user_id TEXT,
          synced INTEGER NOT NULL DEFAULT 0,
          sync_attempts INTEGER NOT NULL DEFAULT 0
        )
      ''');
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_app_logs_synced_ts ON app_logs(synced, timestamp)',
      );
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_app_logs_ts ON app_logs(timestamp DESC)',
      );
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_app_logs_level_tag ON app_logs(level, tag)',
      );
    }
```

- [ ] **Step 2: Run all existing DB tests to verify nothing else broke**

```
cd movile_app && flutter test test/data/local
```
Expected: existing tests pass (or, if no tests in that folder, command exits cleanly).

If that folder doesn't exist, run:
```
flutter test
```
Expected: existing suite still green.

- [ ] **Step 3: Commit**

```
git add movile_app/lib/src/data/local/splitway_local_database.dart
git commit -m "feat(logging): add app_logs table to local DB (schema v9)"
```

---

## Task 7: `LocalSink`

**Files:**
- Create: `movile_app/lib/src/services/logging/sinks/local_sink.dart`
- Test: `movile_app/test/services/logging/local_sink_test.dart`

- [ ] **Step 1: Write the failing tests**

`movile_app/test/services/logging/local_sink_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_common_ffi.dart';
import 'package:splitway_mobile/src/data/local/splitway_local_database.dart';
import 'package:splitway_mobile/src/services/logging/log_entry.dart';
import 'package:splitway_mobile/src/services/logging/log_level.dart';
import 'package:splitway_mobile/src/services/logging/sinks/local_sink.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late SplitwayLocalDatabase db;
  late LocalSink sink;

  setUp(() async {
    db = await SplitwayLocalDatabase.open(overridePath: inMemoryDatabasePath);
    sink = LocalSink(db);
  });

  tearDown(() async {
    await db.close();
  });

  LogEntry sample(String id, {DateTime? ts, LogLevel level = LogLevel.error}) =>
      LogEntry(
        id: id,
        timestamp: ts ?? DateTime.utc(2026, 5, 27, 12),
        level: level,
        tag: 'supabase',
        message: 'm $id',
        appVersion: '0.4.0+1',
        platform: 'test',
        deviceModel: 'test',
      );

  test('write inserts the entry as unsynced with 0 attempts', () async {
    await sink.write(sample('a'));
    final rows = await db.raw.query('app_logs');
    expect(rows, hasLength(1));
    expect(rows.first['synced'], 0);
    expect(rows.first['sync_attempts'], 0);
    expect(rows.first['id'], 'a');
  });

  test('write ignores duplicate id (idempotent)', () async {
    await sink.write(sample('a'));
    await sink.write(sample('a'));
    final rows = await db.raw.query('app_logs');
    expect(rows, hasLength(1));
  });

  test('pendingSync returns unsynced rows oldest-first', () async {
    await sink.write(sample('old', ts: DateTime.utc(2026, 5, 27, 10)));
    await sink.write(sample('new', ts: DateTime.utc(2026, 5, 27, 14)));
    final pending = await sink.pendingSync(limit: 50);
    expect(pending.map((e) => e.id), ['old', 'new']);
  });

  test('markSynced flips the synced flag', () async {
    await sink.write(sample('a'));
    await sink.markSynced(['a']);
    final pending = await sink.pendingSync(limit: 50);
    expect(pending, isEmpty);
  });

  test('incrementAttempts bumps the counter', () async {
    await sink.write(sample('a'));
    await sink.incrementAttempts(['a']);
    await sink.incrementAttempts(['a']);
    final rows = await db.raw.query('app_logs', where: 'id = ?', whereArgs: ['a']);
    expect(rows.first['sync_attempts'], 2);
  });

  test('purgeOlderThan deletes only synced rows past the threshold', () async {
    final old = DateTime.utc(2026, 5, 20);
    final recent = DateTime.utc(2026, 5, 27);
    await sink.write(sample('old-synced', ts: old));
    await sink.write(sample('old-unsynced', ts: old));
    await sink.write(sample('recent', ts: recent));
    await sink.markSynced(['old-synced']);
    await sink.purgeOlderThan(DateTime.utc(2026, 5, 25));
    final ids = (await db.raw.query('app_logs'))
        .map((r) => r['id'] as String)
        .toList()
      ..sort();
    expect(ids, ['old-unsynced', 'recent']);
  });

  test('purgeOlderThan also drops dead rows (>=5 attempts)', () async {
    final old = DateTime.utc(2026, 5, 20);
    await sink.write(sample('dead', ts: old));
    for (var i = 0; i < 5; i++) {
      await sink.incrementAttempts(['dead']);
    }
    await sink.purgeOlderThan(DateTime.utc(2026, 5, 25));
    final rows = await db.raw.query('app_logs');
    expect(rows, isEmpty);
  });

  test('trimToMaxCount keeps only the newest N rows', () async {
    for (var i = 0; i < 10; i++) {
      await sink.write(
        sample('id$i', ts: DateTime.utc(2026, 5, 27, 12, i)),
      );
    }
    await sink.trimToMaxCount(3);
    final ids = (await db.raw
            .query('app_logs', orderBy: 'timestamp DESC'))
        .map((r) => r['id'] as String)
        .toList();
    expect(ids, ['id9', 'id8', 'id7']);
  });

  test('list applies level and tag filters', () async {
    await sink.write(sample('a', level: LogLevel.error));
    await sink.write(sample('b', level: LogLevel.info));
    final errors = await sink.list(level: LogLevel.warning, limit: 100);
    expect(errors.map((e) => e.id), ['a']);
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

```
flutter test test/services/logging/local_sink_test.dart
```
Expected: compile error — `LocalSink` does not exist.

- [ ] **Step 3: Implement `LocalSink`**

`movile_app/lib/src/services/logging/sinks/local_sink.dart`:

```dart
import 'package:sqflite/sqflite.dart';

import '../../../data/local/splitway_local_database.dart';
import '../log_entry.dart';
import '../log_level.dart';
import 'log_sink.dart';

/// Persists log entries to the local SQLite `app_logs` table.
class LocalSink implements LogSink {
  LocalSink(this._db);

  final SplitwayLocalDatabase _db;

  Database get _raw => _db.raw;

  @override
  Future<void> write(LogEntry entry) async {
    try {
      final map = entry.toMap()
        ..['synced'] = 0
        ..['sync_attempts'] = 0;
      await _raw.insert(
        'app_logs',
        map,
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    } catch (_) {
      // never throw from a sink
    }
  }

  /// Returns up to [limit] unsynced rows ordered oldest-first.
  Future<List<LogEntry>> pendingSync({required int limit}) async {
    final rows = await _raw.query(
      'app_logs',
      where: 'synced = 0 AND sync_attempts < 5',
      orderBy: 'timestamp ASC',
      limit: limit,
    );
    return rows.map(LogEntry.fromMap).toList();
  }

  Future<int> countPending() async {
    final rows = await _raw.rawQuery(
      'SELECT COUNT(*) AS c FROM app_logs WHERE synced = 0 AND sync_attempts < 5',
    );
    return (rows.first['c'] as int?) ?? 0;
  }

  Future<void> markSynced(List<String> ids) async {
    if (ids.isEmpty) return;
    final placeholders = List.filled(ids.length, '?').join(',');
    await _raw.rawUpdate(
      'UPDATE app_logs SET synced = 1 WHERE id IN ($placeholders)',
      ids,
    );
  }

  Future<void> incrementAttempts(List<String> ids) async {
    if (ids.isEmpty) return;
    final placeholders = List.filled(ids.length, '?').join(',');
    await _raw.rawUpdate(
      'UPDATE app_logs SET sync_attempts = sync_attempts + 1 '
      'WHERE id IN ($placeholders)',
      ids,
    );
  }

  /// Deletes synced rows older than [cutoff] and "dead" rows whose attempts
  /// have exceeded the max retry count.
  Future<void> purgeOlderThan(DateTime cutoff) async {
    final cutoffMs = cutoff.toUtc().millisecondsSinceEpoch;
    await _raw.rawDelete(
      'DELETE FROM app_logs '
      'WHERE timestamp < ? AND (synced = 1 OR sync_attempts >= 5)',
      [cutoffMs],
    );
  }

  /// Keeps only the [maxCount] most recent rows (unsynced rows are still
  /// dropped if they are older than the cutoff).
  Future<void> trimToMaxCount(int maxCount) async {
    final rows = await _raw.rawQuery(
      'SELECT COUNT(*) AS c FROM app_logs',
    );
    final count = (rows.first['c'] as int?) ?? 0;
    if (count <= maxCount) return;
    final excess = count - maxCount;
    await _raw.rawDelete(
      'DELETE FROM app_logs WHERE id IN ('
      '  SELECT id FROM app_logs ORDER BY timestamp ASC LIMIT ?'
      ')',
      [excess],
    );
  }

  /// Reads log entries for the UI. Filters are optional and combine with AND.
  Future<List<LogEntry>> list({
    LogLevel? level,
    String? tag,
    String? search,
    int limit = 500,
  }) async {
    final where = <String>[];
    final args = <Object?>[];
    if (level != null) {
      where.add('level IN (${_levelsAtOrAbove(level).map((_) => '?').join(',')})');
      args.addAll(_levelsAtOrAbove(level).map((l) => l.name));
    }
    if (tag != null && tag.isNotEmpty) {
      where.add('tag = ?');
      args.add(tag);
    }
    if (search != null && search.isNotEmpty) {
      where.add('(message LIKE ? OR error LIKE ?)');
      args.add('%$search%');
      args.add('%$search%');
    }
    final rows = await _raw.query(
      'app_logs',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'timestamp DESC',
      limit: limit,
    );
    return rows.map(LogEntry.fromMap).toList();
  }

  Future<void> deleteAll() async {
    await _raw.delete('app_logs');
  }

  List<LogLevel> _levelsAtOrAbove(LogLevel min) =>
      LogLevel.values.where((l) => l.index >= min.index).toList();
}
```

- [ ] **Step 4: Run tests to verify they pass**

```
flutter test test/services/logging/local_sink_test.dart
```
Expected: `All tests passed!`

- [ ] **Step 5: Commit**

```
git add movile_app/lib/src/services/logging/sinks/local_sink.dart movile_app/test/services/logging/local_sink_test.dart
git commit -m "feat(logging): add LocalSink with sync/retention helpers"
```

---

## Task 8: `LogUploader`

**Files:**
- Create: `movile_app/lib/src/services/logging/log_uploader.dart`
- Test: `movile_app/test/services/logging/log_uploader_test.dart`

The uploader receives a callback `Future<void> Function(List<LogEntry>) uploader` so tests can inject behavior without touching Supabase. The real Supabase call wiring lives in `RemoteSink` (Task 9).

- [ ] **Step 1: Write the failing tests**

`movile_app/test/services/logging/log_uploader_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_common_ffi.dart';
import 'package:splitway_mobile/src/data/local/splitway_local_database.dart';
import 'package:splitway_mobile/src/services/logging/log_entry.dart';
import 'package:splitway_mobile/src/services/logging/log_level.dart';
import 'package:splitway_mobile/src/services/logging/log_uploader.dart';
import 'package:splitway_mobile/src/services/logging/sinks/local_sink.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late SplitwayLocalDatabase db;
  late LocalSink sink;

  setUp(() async {
    db = await SplitwayLocalDatabase.open(overridePath: inMemoryDatabasePath);
    sink = LocalSink(db);
  });

  tearDown(() async {
    await db.close();
  });

  LogEntry sample(String id) => LogEntry(
        id: id,
        timestamp: DateTime.utc(2026, 5, 27, 12),
        level: LogLevel.error,
        tag: 'supabase',
        message: id,
        appVersion: '0.4.0+1',
        platform: 'test',
        deviceModel: 'test',
      );

  test('drain uploads pending rows in batches and marks them synced', () async {
    for (var i = 0; i < 3; i++) {
      await sink.write(sample('id$i'));
    }
    final calls = <int>[];
    final uploader = LogUploader(
      sink: sink,
      upload: (batch) async => calls.add(batch.length),
      batchSize: 2,
    );

    await uploader.drain();

    expect(calls, [2, 1]);
    expect(await sink.countPending(), 0);
  });

  test('drain increments attempts when upload throws', () async {
    await sink.write(sample('id0'));
    final uploader = LogUploader(
      sink: sink,
      upload: (_) async => throw Exception('boom'),
      batchSize: 10,
    );

    await uploader.drain();

    expect(await sink.countPending(), 1);
    final rows = await db.raw.query('app_logs');
    expect(rows.first['sync_attempts'], 1);
    expect(rows.first['synced'], 0);
  });

  test('drain is a no-op when upload is disabled', () async {
    await sink.write(sample('id0'));
    var called = false;
    final uploader = LogUploader(
      sink: sink,
      upload: (_) async => called = true,
      batchSize: 10,
      enabled: () => false,
    );

    await uploader.drain();

    expect(called, isFalse);
    expect(await sink.countPending(), 1);
  });

  test('scheduleDrain debounces concurrent triggers', () async {
    await sink.write(sample('id0'));
    var calls = 0;
    final uploader = LogUploader(
      sink: sink,
      upload: (_) async => calls++,
      batchSize: 10,
      debounce: const Duration(milliseconds: 10),
    );

    uploader.scheduleDrain();
    uploader.scheduleDrain();
    uploader.scheduleDrain();
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(calls, 1);
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

```
flutter test test/services/logging/log_uploader_test.dart
```
Expected: compile error — `LogUploader` missing.

- [ ] **Step 3: Implement `LogUploader`**

`movile_app/lib/src/services/logging/log_uploader.dart`:

```dart
import 'dart:async';

import 'log_entry.dart';
import 'sinks/local_sink.dart';

typedef LogBatchUploader = Future<void> Function(List<LogEntry> batch);

/// Drains unsynced rows from a [LocalSink] and pushes them through [upload]
/// in batches. Independent of any concrete remote backend.
class LogUploader {
  LogUploader({
    required LocalSink sink,
    required LogBatchUploader upload,
    int batchSize = 50,
    Duration debounce = const Duration(seconds: 5),
    bool Function()? enabled,
  })  : _sink = sink,
        _upload = upload,
        _batchSize = batchSize,
        _debounce = debounce,
        _enabled = enabled ?? (() => true);

  final LocalSink _sink;
  final LogBatchUploader _upload;
  final int _batchSize;
  final Duration _debounce;
  final bool Function() _enabled;

  Timer? _timer;
  bool _running = false;

  /// Schedules a drain after the debounce window. Multiple calls during the
  /// window collapse into a single run.
  void scheduleDrain() {
    _timer?.cancel();
    _timer = Timer(_debounce, () {
      _timer = null;
      drain();
    });
  }

  /// Uploads pending rows immediately. Safe to await; concurrent calls return
  /// fast (only one drain runs at a time).
  Future<void> drain() async {
    if (_running) return;
    if (!_enabled()) return;
    _running = true;
    try {
      while (true) {
        final batch = await _sink.pendingSync(limit: _batchSize);
        if (batch.isEmpty) break;
        try {
          await _upload(batch);
          await _sink.markSynced(batch.map((e) => e.id).toList());
        } catch (_) {
          await _sink.incrementAttempts(batch.map((e) => e.id).toList());
          // Stop draining on first error so we don't hammer Supabase.
          break;
        }
      }
    } finally {
      _running = false;
    }
  }

  void dispose() {
    _timer?.cancel();
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

```
flutter test test/services/logging/log_uploader_test.dart
```
Expected: `All tests passed!`

- [ ] **Step 5: Commit**

```
git add movile_app/lib/src/services/logging/log_uploader.dart movile_app/test/services/logging/log_uploader_test.dart
git commit -m "feat(logging): add LogUploader with batching, retry and debounce"
```

---

## Task 9: `RemoteSink`

**Files:**
- Create: `movile_app/lib/src/services/logging/sinks/remote_sink.dart`

`RemoteSink` is a thin adapter: it kicks off a debounced drain on every write. It does not block the caller. No dedicated test — its behavior is covered by `LogUploader`'s tests and integration via `AppLogger`.

- [ ] **Step 1: Implement `RemoteSink`**

`movile_app/lib/src/services/logging/sinks/remote_sink.dart`:

```dart
import '../log_entry.dart';
import '../log_uploader.dart';
import 'log_sink.dart';

/// Trigger-only sink. Persistence happens in [LocalSink] (the caller wires
/// both sinks into `AppLogger`); this sink just nudges the uploader.
class RemoteSink implements LogSink {
  const RemoteSink(this._uploader);

  final LogUploader _uploader;

  @override
  Future<void> write(LogEntry entry) async {
    _uploader.scheduleDrain();
  }
}
```

- [ ] **Step 2: Sanity-check**

```
flutter analyze lib/src/services/logging/sinks/remote_sink.dart
```
Expected: `No issues found!`

- [ ] **Step 3: Commit**

```
git add movile_app/lib/src/services/logging/sinks/remote_sink.dart
git commit -m "feat(logging): add RemoteSink that triggers the uploader"
```

---

## Task 10: `AppLogger` singleton facade

**Files:**
- Create: `movile_app/lib/src/services/logging/app_logger.dart`
- Test: `movile_app/test/services/logging/app_logger_test.dart`

- [ ] **Step 1: Write the failing tests**

`movile_app/test/services/logging/app_logger_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:splitway_mobile/src/services/logging/app_logger.dart';
import 'package:splitway_mobile/src/services/logging/device_metadata.dart';
import 'package:splitway_mobile/src/services/logging/log_entry.dart';
import 'package:splitway_mobile/src/services/logging/log_level.dart';
import 'package:splitway_mobile/src/services/logging/sinks/log_sink.dart';

class _RecordingSink implements LogSink {
  final List<LogEntry> entries = [];
  @override
  Future<void> write(LogEntry entry) async => entries.add(entry);
}

void main() {
  late _RecordingSink sink;
  late AppLogger logger;

  setUp(() {
    sink = _RecordingSink();
    logger = AppLogger.test(
      sinks: [sink],
      metadata: const DeviceMetadata(
        appVersion: '0.4.0+1',
        platform: 'test',
        deviceModel: 'test',
      ),
      minLevel: () => LogLevel.warning,
      userId: () => 'user-1',
    );
  });

  test('drops entries below minLevel', () async {
    await logger.info('app', 'noise');
    expect(sink.entries, isEmpty);
  });

  test('emits entries at or above minLevel', () async {
    await logger.warning('app', 'careful');
    expect(sink.entries, hasLength(1));
    expect(sink.entries.first.level, LogLevel.warning);
  });

  test('attaches metadata and user id', () async {
    await logger.error('supabase', 'rpc failed');
    final e = sink.entries.first;
    expect(e.appVersion, '0.4.0+1');
    expect(e.platform, 'test');
    expect(e.deviceModel, 'test');
    expect(e.userId, 'user-1');
  });

  test('sanitizes message, error, stack and context', () async {
    await logger.error(
      'mapbox',
      'GET https://api.mapbox.com?access_token=pk.secret',
      error: Exception('Bearer eyJabc'),
      stackTrace: StackTrace.fromString('apikey=secret\n'),
      context: {
        'url': 'https://api.test?access_token=pk.x',
        'token': 'sensitive',
      },
    );
    final e = sink.entries.first;
    expect(e.message, isNot(contains('pk.secret')));
    expect(e.error, isNot(contains('eyJabc')));
    expect(e.stackTrace, isNot(contains('secret')));
    expect(e.context!['url'], contains('***REDACTED***'));
    expect(e.context!['token'], '***REDACTED***');
  });

  test('rate-limits identical (level,tag) above the threshold', () async {
    for (var i = 0; i < 15; i++) {
      await logger.error('flutter', 'boom $i');
    }
    expect(sink.entries.length, lessThanOrEqualTo(10));
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

```
flutter test test/services/logging/app_logger_test.dart
```
Expected: compile error.

- [ ] **Step 3: Implement `AppLogger`**

`movile_app/lib/src/services/logging/app_logger.dart`:

```dart
import 'dart:async';

import 'package:uuid/uuid.dart';

import 'device_metadata.dart';
import 'log_entry.dart';
import 'log_level.dart';
import 'log_sanitizer.dart';
import 'sinks/log_sink.dart';

/// Central entrypoint for the logging system. Application code calls
/// `AppLogger.instance.error(...)` (or the level-specific shortcuts).
class AppLogger {
  AppLogger._({
    required List<LogSink> sinks,
    required DeviceMetadata metadata,
    required LogLevel Function() minLevel,
    required String? Function() userId,
  })  : _sinks = sinks,
        _metadata = metadata,
        _minLevel = minLevel,
        _userId = userId;

  /// Test-only constructor with explicit dependencies.
  factory AppLogger.test({
    required List<LogSink> sinks,
    required DeviceMetadata metadata,
    required LogLevel Function() minLevel,
    String? Function()? userId,
  }) =>
      AppLogger._(
        sinks: sinks,
        metadata: metadata,
        minLevel: minLevel,
        userId: userId ?? (() => null),
      );

  static AppLogger? _instance;

  /// The singleton. Throws if [install] has not run yet.
  static AppLogger get instance {
    final i = _instance;
    if (i == null) {
      throw StateError('AppLogger.install() has not been called yet');
    }
    return i;
  }

  /// Returns the singleton if it has been installed, otherwise null. Use this
  /// during early bootstrap before [install] runs.
  static AppLogger? get maybeInstance => _instance;

  /// Installs a singleton. Subsequent calls replace the previous instance
  /// (useful for hot restart in development).
  static void install({
    required List<LogSink> sinks,
    required DeviceMetadata metadata,
    required LogLevel Function() minLevel,
    required String? Function() userId,
  }) {
    _instance = AppLogger._(
      sinks: sinks,
      metadata: metadata,
      minLevel: minLevel,
      userId: userId,
    );
  }

  final List<LogSink> _sinks;
  final DeviceMetadata _metadata;
  final LogLevel Function() _minLevel;
  final String? Function() _userId;
  final Uuid _uuid = const Uuid();

  // Rate limit: max 10 entries per (level,tag) per second.
  final Map<String, _RateBucket> _buckets = {};

  Future<void> debug(String tag, String message,
          {Object? error, StackTrace? stackTrace, Map<String, dynamic>? context}) =>
      log(LogLevel.debug, tag, message,
          error: error, stackTrace: stackTrace, context: context);

  Future<void> info(String tag, String message,
          {Object? error, StackTrace? stackTrace, Map<String, dynamic>? context}) =>
      log(LogLevel.info, tag, message,
          error: error, stackTrace: stackTrace, context: context);

  Future<void> warning(String tag, String message,
          {Object? error, StackTrace? stackTrace, Map<String, dynamic>? context}) =>
      log(LogLevel.warning, tag, message,
          error: error, stackTrace: stackTrace, context: context);

  Future<void> error(String tag, String message,
          {Object? error, StackTrace? stackTrace, Map<String, dynamic>? context}) =>
      log(LogLevel.error, tag, message,
          error: error, stackTrace: stackTrace, context: context);

  Future<void> log(
    LogLevel level,
    String tag,
    String message, {
    Object? error,
    StackTrace? stackTrace,
    Map<String, dynamic>? context,
  }) async {
    if (level.index < _minLevel().index) return;
    if (!_allowByRateLimit(level, tag)) return;

    final entry = LogEntry(
      id: _uuid.v4(),
      timestamp: DateTime.now().toUtc(),
      level: level,
      tag: tag,
      message: LogSanitizer.sanitizeText(message),
      error: error == null ? null : LogSanitizer.sanitizeText(error.toString()),
      stackTrace: stackTrace == null
          ? null
          : LogSanitizer.sanitizeText(stackTrace.toString()),
      context: LogSanitizer.sanitizeContext(context),
      appVersion: _metadata.appVersion,
      platform: _metadata.platform,
      deviceModel: _metadata.deviceModel,
      userId: _userId(),
    );

    for (final sink in _sinks) {
      try {
        await sink.write(entry);
      } catch (_) {
        // sinks must not throw, but be defensive anyway
      }
    }
  }

  bool _allowByRateLimit(LogLevel level, String tag) {
    final key = '${level.name}:$tag';
    final now = DateTime.now();
    final bucket = _buckets.putIfAbsent(key, () => _RateBucket());
    if (now.difference(bucket.windowStart).inSeconds >= 1) {
      bucket.windowStart = now;
      bucket.count = 0;
    }
    bucket.count += 1;
    return bucket.count <= 10;
  }
}

class _RateBucket {
  DateTime windowStart = DateTime.now();
  int count = 0;
}
```

- [ ] **Step 4: Run tests to verify they pass**

```
flutter test test/services/logging/app_logger_test.dart
```
Expected: `All tests passed!`

- [ ] **Step 5: Commit**

```
git add movile_app/lib/src/services/logging/app_logger.dart movile_app/test/services/logging/app_logger_test.dart
git commit -m "feat(logging): add AppLogger singleton with rate limiting"
```

---

## Task 11: `logSupabase` and `logHttp` helpers

**Files:**
- Create: `movile_app/lib/src/services/logging/http_logging.dart`
- Test: `movile_app/test/services/logging/http_logging_test.dart`

- [ ] **Step 1: Write the failing tests**

`movile_app/test/services/logging/http_logging_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:splitway_mobile/src/services/logging/app_logger.dart';
import 'package:splitway_mobile/src/services/logging/device_metadata.dart';
import 'package:splitway_mobile/src/services/logging/http_logging.dart';
import 'package:splitway_mobile/src/services/logging/log_entry.dart';
import 'package:splitway_mobile/src/services/logging/log_level.dart';
import 'package:splitway_mobile/src/services/logging/sinks/log_sink.dart';

class _Recording implements LogSink {
  final List<LogEntry> entries = [];
  @override
  Future<void> write(LogEntry e) async => entries.add(e);
}

void main() {
  late _Recording sink;
  setUp(() {
    sink = _Recording();
    AppLogger.install(
      sinks: [sink],
      metadata: const DeviceMetadata(
        appVersion: 't',
        platform: 't',
        deviceModel: 't',
      ),
      minLevel: () => LogLevel.debug,
      userId: () => null,
    );
  });

  test('logSupabase logs error and rethrows on exception', () async {
    Future<int> body() async => throw Exception('rpc down');
    await expectLater(
      logSupabase('upsertRoute', body),
      throwsA(isA<Exception>()),
    );
    expect(sink.entries, hasLength(1));
    final e = sink.entries.first;
    expect(e.level, LogLevel.error);
    expect(e.tag, 'supabase');
    expect(e.context!['op'], 'upsertRoute');
    expect(e.context!['durationMs'], isA<int>());
  });

  test('logSupabase does not log on success', () async {
    final out = await logSupabase('fetchAll', () async => 42);
    expect(out, 42);
    expect(sink.entries, isEmpty);
  });

  test('logHttp logs warning when status >= 400', () async {
    final response = http.Response('boom', 500);
    final out = await logHttp(
      'mapbox',
      Uri.parse('https://api.mapbox.com/x?access_token=pk.s'),
      () async => response,
    );
    expect(out, response);
    expect(sink.entries, hasLength(1));
    final e = sink.entries.first;
    expect(e.level, LogLevel.warning);
    expect(e.tag, 'mapbox');
    expect(e.context!['statusCode'], 500);
    expect(e.context!['url'], contains('***REDACTED***'));
  });

  test('logHttp logs error and rethrows on exception', () async {
    Future<http.Response> body() async => throw Exception('no network');
    await expectLater(
      logHttp('mapbox', Uri.parse('https://x'), body),
      throwsA(isA<Exception>()),
    );
    expect(sink.entries.first.level, LogLevel.error);
  });

  test('logHttp does not log on 2xx', () async {
    final r = http.Response('ok', 200);
    await logHttp('mapbox', Uri.parse('https://x'), () async => r);
    expect(sink.entries, isEmpty);
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

```
flutter test test/services/logging/http_logging_test.dart
```
Expected: compile error.

- [ ] **Step 3: Implement the helpers**

`movile_app/lib/src/services/logging/http_logging.dart`:

```dart
import 'package:http/http.dart' as http;

import 'app_logger.dart';
import 'log_level.dart';

/// Wraps a Supabase call. Logs and rethrows on failure with the operation
/// name and elapsed milliseconds. No-op on success.
Future<T> logSupabase<T>(String op, Future<T> Function() body) async {
  final sw = Stopwatch()..start();
  try {
    return await body();
  } catch (e, st) {
    final logger = AppLogger.maybeInstance;
    if (logger != null) {
      await logger.error(
        'supabase',
        '$op failed',
        error: e,
        stackTrace: st,
        context: {
          'op': op,
          'durationMs': sw.elapsedMilliseconds,
        },
      );
    }
    rethrow;
  }
}

/// Wraps an HTTP call. Logs at WARNING for status >= 400, at ERROR on throw.
/// Returns the response unchanged.
Future<http.Response> logHttp(
  String tag,
  Uri url,
  Future<http.Response> Function() send,
) async {
  final sw = Stopwatch()..start();
  try {
    final response = await send();
    if (response.statusCode >= 400) {
      final logger = AppLogger.maybeInstance;
      if (logger != null) {
        await logger.log(
          LogLevel.warning,
          tag,
          'HTTP ${response.statusCode} ${url.path}',
          context: {
            'url': url.toString(),
            'statusCode': response.statusCode,
            'durationMs': sw.elapsedMilliseconds,
          },
        );
      }
    }
    return response;
  } catch (e, st) {
    final logger = AppLogger.maybeInstance;
    if (logger != null) {
      await logger.error(
        tag,
        'HTTP request threw on ${url.path}',
        error: e,
        stackTrace: st,
        context: {
          'url': url.toString(),
          'durationMs': sw.elapsedMilliseconds,
        },
      );
    }
    rethrow;
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

```
flutter test test/services/logging/http_logging_test.dart
```
Expected: `All tests passed!`

- [ ] **Step 5: Commit**

```
git add movile_app/lib/src/services/logging/http_logging.dart movile_app/test/services/logging/http_logging_test.dart
git commit -m "feat(logging): add logSupabase and logHttp wrappers"
```

---

## Task 12: Settings for log level and remote toggle

**Files:**
- Modify: `movile_app/lib/src/services/settings/app_settings_controller.dart`

- [ ] **Step 1: Add fields, getters and setters**

In `movile_app/lib/src/services/settings/app_settings_controller.dart`:

1. Add the import at the top with other imports:

```dart
import '../logging/log_level.dart';
```

2. After the existing private constants, add:

```dart
  static const _kMinLogLevel = 'min_log_level';
  static const _kRemoteLogsEnabled = 'remote_logs_enabled';
```

3. Inside the private constructor (`AppSettingsController._`), after `_defaultRoutingProfile = ...` lines, add:

```dart
    _minLogLevel = LogLevel.fromName(
      _prefs.getString(_kMinLogLevel) ?? LogLevel.warning.name,
    );
    _remoteLogsEnabled = _prefs.getBool(_kRemoteLogsEnabled) ?? true;
```

4. With the other `late` fields, add:

```dart
  late LogLevel _minLogLevel;
  late bool _remoteLogsEnabled;
```

5. With the other getters, add:

```dart
  LogLevel get minLogLevel => _minLogLevel;
  bool get remoteLogsEnabled => _remoteLogsEnabled;
```

6. At the bottom of the class, add setters:

```dart
  Future<void> setMinLogLevel(LogLevel v) async {
    if (_minLogLevel == v) return;
    _minLogLevel = v;
    await _prefs.setString(_kMinLogLevel, v.name);
    notifyListeners();
  }

  Future<void> setRemoteLogsEnabled(bool v) async {
    if (_remoteLogsEnabled == v) return;
    _remoteLogsEnabled = v;
    await _prefs.setBool(_kRemoteLogsEnabled, v);
    notifyListeners();
  }
```

- [ ] **Step 2: Run analyzer**

```
flutter analyze lib/src/services/settings/app_settings_controller.dart
```
Expected: `No issues found!`

- [ ] **Step 3: Commit**

```
git add movile_app/lib/src/services/settings/app_settings_controller.dart
git commit -m "feat(logging): expose minLogLevel and remoteLogsEnabled in settings"
```

---

## Task 13: Supabase migration for `app_logs`

**Files:**
- Create: `supabase/migrations/20260527000000_app_logs.sql`

- [ ] **Step 1: Write the SQL migration**

`supabase/migrations/20260527000000_app_logs.sql`:

```sql
-- App diagnostic logs uploaded from the mobile client.
create table if not exists public.app_logs (
  id           uuid primary key,
  timestamp    timestamptz not null,
  level        text not null check (level in ('debug','info','warning','error')),
  tag          text not null,
  message      text not null,
  error        text,
  stack_trace  text,
  context      jsonb,
  app_version  text not null,
  platform     text not null,
  device_model text not null,
  user_id      uuid references auth.users(id) on delete set null
);

create index if not exists idx_app_logs_user_ts on public.app_logs (user_id, timestamp desc);
create index if not exists idx_app_logs_level_ts on public.app_logs (level, timestamp desc);

alter table public.app_logs enable row level security;

-- Anyone authenticated can insert their own logs (or anonymous pre-login logs).
drop policy if exists "app_logs_insert_own" on public.app_logs;
create policy "app_logs_insert_own"
  on public.app_logs
  for insert
  to authenticated
  with check (user_id = auth.uid() or user_id is null);

-- Reading is restricted to service_role (we inspect logs via the dashboard).
drop policy if exists "app_logs_select_service" on public.app_logs;
create policy "app_logs_select_service"
  on public.app_logs
  for select
  to service_role
  using (true);

-- Daily purge of logs older than 30 days. Requires pg_cron to be enabled in
-- the project; the unschedule guards against duplicate jobs on re-runs.
do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.unschedule('purge_app_logs')
      where exists (select 1 from cron.job where jobname = 'purge_app_logs');
    perform cron.schedule(
      'purge_app_logs',
      '0 3 * * *',
      $$delete from public.app_logs where timestamp < now() - interval '30 days'$$
    );
  end if;
end
$$;
```

- [ ] **Step 2: Sanity-check no syntax errors locally**

If the Supabase CLI is installed, run:
```
supabase db lint
```
Expected: no errors. If the CLI is not installed, skip this step — the migration runs on the next `supabase db push`.

- [ ] **Step 3: Commit**

```
git add supabase/migrations/20260527000000_app_logs.sql
git commit -m "feat(logging): add app_logs table migration with RLS and pg_cron purge"
```

---

## Task 14: Wire `AppLogger` into `main.dart`

**Files:**
- Modify: `movile_app/lib/main.dart`

- [ ] **Step 1: Replace `main` to install the logger and capture global errors**

Replace the entire body of `movile_app/lib/main.dart` with:

```dart
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mbx;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'src/app.dart';
import 'src/config/app_config.dart';
import 'src/data/demo/demo_seed.dart';
import 'src/data/local/splitway_local_database.dart';
import 'src/data/repositories/local_draft_repository.dart';
import 'src/services/locale/locale_controller.dart';
import 'src/services/logging/app_logger.dart';
import 'src/services/logging/device_metadata.dart';
import 'src/services/logging/log_uploader.dart';
import 'src/services/logging/sinks/console_sink.dart';
import 'src/services/logging/sinks/local_sink.dart';
import 'src/services/logging/sinks/log_sink.dart';
import 'src/services/logging/sinks/remote_sink.dart';
import 'src/services/routing/elevation_service.dart';
import 'src/services/settings/app_settings_controller.dart';
import 'src/services/tracking/background_tracking_service.dart';

Future<void> main() async {
  await runZonedGuarded<Future<void>>(() async {
    WidgetsFlutterBinding.ensureInitialized();

    // Pre-load date formatting symbols for every supported locale.
    await initializeDateFormatting('es_ES');
    await initializeDateFormatting('en_US');

    BackgroundTrackingService.init();

    final database = await SplitwayLocalDatabase.open();
    final settingsController = await AppSettingsController.load();
    final metadata = await DeviceMetadata.capture();

    // Logger must come BEFORE Supabase/Mapbox init so we capture their errors.
    final localSink = LocalSink(database);
    LogUploader? uploader;
    final sinks = <LogSink>[const ConsoleSink(), localSink];

    AppLogger.install(
      sinks: sinks,
      metadata: metadata,
      minLevel: () => settingsController.minLogLevel,
      userId: () =>
          Supabase.instance.isInitialized ? Supabase.instance.client.auth.currentUser?.id : null,
    );

    FlutterError.onError = (details) {
      AppLogger.instance.error(
        'flutter',
        details.exceptionAsString(),
        error: details.exception,
        stackTrace: details.stack,
        context: {'library': details.library},
      );
      if (!kReleaseMode) FlutterError.presentError(details);
    };

    PlatformDispatcher.instance.onError = (error, stack) {
      AppLogger.instance.error('dart', error.toString(),
          error: error, stackTrace: stack);
      return true;
    };

    final config = await AppConfig.load();
    if (config.hasMapbox) {
      mbx.MapboxOptions.setAccessToken(config.mapboxToken!);
    }

    if (config.hasSupabase) {
      try {
        await Supabase.initialize(
          url: config.supabaseUrl!,
          anonKey: config.supabaseAnonKey!,
        );
      } catch (e, st) {
        await AppLogger.instance.error('supabase', 'Supabase.initialize failed',
            error: e, stackTrace: st);
      }
    }

    // Wire the remote uploader now that Supabase has had a chance to init.
    uploader = LogUploader(
      sink: localSink,
      upload: (batch) async {
        if (!Supabase.instance.isInitialized) {
          throw StateError('Supabase not initialized');
        }
        await Supabase.instance.client.from('app_logs').insert(
              batch.map((e) => e.toRemoteJson()).toList(),
            );
      },
      enabled: () => settingsController.remoteLogsEnabled,
    );
    sinks.add(RemoteSink(uploader));
    // Initial drain in case there are leftovers from a previous run.
    unawaited(uploader.drain());

    final seedRepo = LocalDraftRepository(database);
    await DemoSeed.ensureSeeded(
      seedRepo,
      settingsController,
      elevationService: ElevationService(),
    );
    await seedRepo.dispose();

    final deviceLocale =
        WidgetsBinding.instance.platformDispatcher.locale;
    final localeController =
        await LocaleController.load(deviceLocale: deviceLocale);

    runApp(SplitwayApp(
      config: config,
      database: database,
      localeController: localeController,
      settingsController: settingsController,
    ));
  }, (error, stack) {
    final logger = AppLogger.maybeInstance;
    if (logger != null) {
      logger.error('zone', error.toString(), error: error, stackTrace: stack);
    } else {
      debugPrint('Uncaught zone error before logger init: $error\n$stack');
    }
  });
}
```

Note: `Supabase.instance.isInitialized` is exposed by `supabase_flutter` 2.x — if your version doesn't have it, replace those occurrences with a `try { Supabase.instance.client; return true; } catch (_) { return false; }` helper.

- [ ] **Step 2: Build to verify it compiles**

```
cd movile_app && flutter build apk --debug --target-platform android-arm64
```

(If you don't have Android tooling locally, run instead:)
```
cd movile_app && flutter analyze
```
Expected: `No issues found!` (or `flutter build` succeeds).

- [ ] **Step 3: Commit**

```
git add movile_app/lib/main.dart
git commit -m "feat(logging): install AppLogger and global error handlers in main"
```

---

## Task 15: Wrap Supabase repositories with `logSupabase`

**Files:**
- Modify: `movile_app/lib/src/data/repositories/supabase_repository.dart`
- Modify: `movile_app/lib/src/services/auth/auth_service.dart`
- Modify: `movile_app/lib/src/data/repositories/profile_repository.dart`
- Modify: `movile_app/lib/src/data/repositories/garage_repository.dart`
- Modify: `movile_app/lib/src/data/repositories/speed_repository.dart`
- Modify: `movile_app/lib/src/services/sync/sync_service.dart`

For each file, add the import `import '../../services/logging/http_logging.dart';` (adjust relative depth) and wrap every `await _client...` call (except the in-memory parsers) with `logSupabase('<methodName>', () => ...)`.

Below are the concrete edits for `supabase_repository.dart`; the other files follow the same pattern.

- [ ] **Step 1: Wrap `supabase_repository.dart`**

In `movile_app/lib/src/data/repositories/supabase_repository.dart`:

1. Add at the top with other imports:

```dart
import '../../services/logging/http_logging.dart';
```

2. Replace each `await _client.from(...)...` call body with `logSupabase`. Example for `upsertRoute`:

```dart
    await logSupabase('upsertRoute', () => _client.from('route_templates').upsert({
      'id': route.id,
      // ... rest unchanged
    }));

    await logSupabase('deleteSectors', () => _client.from('sectors').delete().eq('route_id', route.id));
    if (route.sectors.isNotEmpty) {
      await logSupabase('insertSectors', () => _client.from('sectors').insert(
        route.sectors.map((s) => { /* unchanged */ }).toList(),
      ));
    }
```

Apply the same pattern to:
- `fetchAllRoutes` → wrap the two `.select()` calls as `logSupabase('fetchAllRoutes:templates', …)` and `logSupabase('fetchAllRoutes:sectors', …)`.
- `deleteRoute` → wrap the storage `.remove(...)` as `logSupabase('deleteRouteThumbnail', …)` and the table delete as `logSupabase('deleteRoute', …)`. The existing `try { … } catch (_) {}` around the storage call must be preserved.
- `upsertSession` → wrap the `_client.rpc(...)` as `logSupabase('upsertSession', …)`.
- `fetchAllSessions` → wrap the outer `.select()` and the per-row telemetry select.
- `fetchSession` → wrap the two queries.
- `deleteSession` → wrap.
- `upsertFreeRide` → wrap the rpc.
- `fetchAllFreeRides` → wrap.
- `fetchFreeRide` → wrap.
- `fetchRouteTimestamps`, `fetchSessionTimestamps`, `fetchFreeRideTimestamps` → wrap each.

- [ ] **Step 2: Wrap `auth_service.dart`**

Open `movile_app/lib/src/services/auth/auth_service.dart`. Add the same import. For each public method that calls Supabase auth (`signIn…`, `signUp…`, `signOut`, `signInWithGoogle`, …) wrap the call in a `try { … } catch (e, st) { AppLogger.maybeInstance?.warning('auth', '<method> failed', error: e, stackTrace: st, context: {'method': '<method>'}); rethrow; }`. Do NOT include email/password in the context.

Required import:
```dart
import '../logging/app_logger.dart';
```

- [ ] **Step 3: Wrap the remaining repositories**

For `profile_repository.dart`, `garage_repository.dart`, `speed_repository.dart`, add the import:
```dart
import '../../services/logging/http_logging.dart';
```
and wrap every method that does `await _client.from(...)` or `_client.rpc(...)` with `logSupabase('<file>.<method>', () => …)`.

For `sync_service.dart` add:
```dart
import '../logging/app_logger.dart';
```
and around each `try { ... } catch (e, st)` of a sync step add `AppLogger.maybeInstance?.warning('sync', '<step> failed', error: e, stackTrace: st);` BEFORE the existing handling. If a step doesn't have try/catch yet, add one that logs then rethrows.

- [ ] **Step 4: Run existing tests**

```
cd movile_app && flutter test
```
Expected: all tests still green. If any test injected a mock `SupabaseClient`, the helper still works because `logSupabase` only forwards the future.

- [ ] **Step 5: Commit**

```
git add movile_app/lib/src/data/repositories/supabase_repository.dart movile_app/lib/src/services/auth/auth_service.dart movile_app/lib/src/data/repositories/profile_repository.dart movile_app/lib/src/data/repositories/garage_repository.dart movile_app/lib/src/data/repositories/speed_repository.dart movile_app/lib/src/services/sync/sync_service.dart
git commit -m "feat(logging): instrument Supabase repositories and auth with logSupabase"
```

---

## Task 16: Wrap Mapbox / HTTP services with `logHttp`

**Files:**
- Modify: `movile_app/lib/src/services/geocoding/reverse_geocoding_service.dart`
- Modify: `movile_app/lib/src/services/geocoding/forward_geocoding_service.dart`
- Modify: `movile_app/lib/src/services/routing/routing_service.dart`
- Modify: `movile_app/lib/src/services/routing/elevation_service.dart`
- Modify: `movile_app/lib/src/data/services/route_thumbnail_service.dart`

- [ ] **Step 1: Update `reverse_geocoding_service.dart`**

Add import:
```dart
import '../logging/app_logger.dart';
import '../logging/http_logging.dart';
```

Replace the body of `reverseGeocode` (lines 26–47) with:

```dart
    try {
      final client = _client ?? http.Client();
      final response = await logHttp(
        'mapbox',
        url,
        () => client.get(url).timeout(const Duration(seconds: 5)),
      );
      if (_client == null) client.close();

      if (response.statusCode != 200) return null;

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final features = json['features'] as List<dynamic>?;
      if (features == null || features.isEmpty) return null;

      final properties = (features.first as Map<String, dynamic>)['properties']
          as Map<String, dynamic>?;
      if (properties == null) return null;

      final placeName = properties['full_address'] as String? ??
          properties['name'] as String?;
      return placeName;
    } catch (e, st) {
      AppLogger.maybeInstance?.warning(
        'mapbox',
        'reverseGeocode failed',
        error: e,
        stackTrace: st,
        context: {'url': url.toString()},
      );
      return null;
    }
```

- [ ] **Step 2: Apply the same pattern to the other four files**

For `forward_geocoding_service.dart`, `routing_service.dart`, `elevation_service.dart`, `route_thumbnail_service.dart`:
- Add the two imports above.
- Replace each `await client.get(url)` / `await client.post(url, ...)` call with `await logHttp('mapbox', url, () => client.get(url))` (use `'mapbox'` for geocoding/routing/elevation/thumbnail since they all hit Mapbox/Mapbox-adjacent APIs; if any uses a different host, use `'http'`).
- Replace any silent `catch (_) {}` blocks with `catch (e, st) { AppLogger.maybeInstance?.warning('<tag>', '<method> failed', error: e, stackTrace: st); /* preserve existing fallback */ }`.

- [ ] **Step 3: Run all tests**

```
cd movile_app && flutter test
```
Expected: green.

- [ ] **Step 4: Commit**

```
git add movile_app/lib/src/services/geocoding/ movile_app/lib/src/services/routing/ movile_app/lib/src/data/services/route_thumbnail_service.dart
git commit -m "feat(logging): instrument Mapbox/HTTP services with logHttp"
```

---

## Task 17: Log GPS permission failures

**Files:**
- Modify: `movile_app/lib/src/services/tracking/location_service.dart`

- [ ] **Step 1: Add logging around permission checks and stream errors**

Open `movile_app/lib/src/services/tracking/location_service.dart`. Add at the top:

```dart
import '../logging/app_logger.dart';
```

Locate the spot where `Geolocator.requestPermission()` is awaited (or any `LocationPermission.denied` branch). Wrap as follows:

```dart
final permission = await Geolocator.requestPermission();
if (permission == LocationPermission.denied ||
    permission == LocationPermission.deniedForever) {
  await AppLogger.maybeInstance?.warning(
    'location',
    'GPS permission denied',
    context: {'permission': permission.name},
  );
}
```

If the file exposes a position stream, wrap its error handler:

```dart
stream.listen(
  onData,
  onError: (e, st) {
    AppLogger.maybeInstance?.warning(
      'location',
      'Position stream error',
      error: e,
      stackTrace: st,
    );
    // ... existing handling
  },
);
```

If the existing structure is significantly different, instead of forcing a rewrite, locate any `catch` block currently swallowing errors and add an `AppLogger.maybeInstance?.warning('location', '...', error: e, stackTrace: st)` line.

- [ ] **Step 2: Run all tests**

```
cd movile_app && flutter test
```
Expected: green.

- [ ] **Step 3: Commit**

```
git add movile_app/lib/src/services/tracking/location_service.dart
git commit -m "feat(logging): log GPS permission denials and stream errors"
```

---

## Task 18: Localization strings

**Files:**
- Modify: `movile_app/lib/l10n/app_localizations.dart`
- Modify: `movile_app/lib/l10n/app_localizations_es.dart`
- Modify: `movile_app/lib/l10n/app_localizations_en.dart`
- Modify: `movile_app/lib/l10n/` `.arb` files if present

- [ ] **Step 1: Identify whether `.arb` files exist**

Run from `movile_app/`:
```
ls lib/l10n
```

If `app_en.arb` / `app_es.arb` exist, edit those and re-run codegen (`flutter gen-l10n`). If only the generated Dart files exist, edit them directly — the project's `l10n.yaml` may or may not regenerate them.

- [ ] **Step 2: Add the following key/value pairs**

For Spanish (`app_es.arb` or `app_localizations_es.dart`):
- `logsScreenTitle` → "Diagnóstico"
- `logsScreenEmpty` → "No hay logs todavía"
- `logsScreenPendingBadge` → "{count} pendientes" (with `count` placeholder)
- `logsScreenUploadNow` → "Subir ahora"
- `logsScreenShareAll` → "Compartir todo"
- `logsScreenClearAll` → "Borrar todo"
- `logsScreenClearConfirmTitle` → "¿Borrar todos los logs?"
- `logsScreenClearConfirmBody` → "Esta acción no se puede deshacer."
- `logsScreenFilterLevel` → "Nivel"
- `logsScreenFilterTag` → "Categoría"
- `logsScreenFilterSearchHint` → "Buscar en mensajes…"
- `logsScreenDetailMessage` → "Mensaje"
- `logsScreenDetailError` → "Error"
- `logsScreenDetailStack` → "Stack trace"
- `logsScreenDetailContext` → "Contexto"
- `logsScreenDetailCopy` → "Copiar"
- `logsScreenDetailShare` → "Compartir"
- `settingsDiagnosticsSection` → "Diagnóstico"
- `settingsDiagnosticsOpen` → "Ver logs"
- `settingsRemoteLogsEnabled` → "Subir logs al servidor"
- `settingsMinLogLevel` → "Nivel mínimo de log"

For English (`app_en.arb` or `app_localizations_en.dart`):
- Same keys, with English translations (`"Diagnostics"`, `"No logs yet"`, etc.).

For the `AppLocalizations` abstract class (`app_localizations.dart`), add an abstract getter for each new key, e.g.:
```dart
String get logsScreenTitle;
String logsScreenPendingBadge(int count);
String get logsScreenUploadNow;
// ... etc
```

- [ ] **Step 3: Regenerate (if `.arb` based)**

If `.arb` files were edited:
```
flutter gen-l10n
```
Expected: succeeds. Otherwise skip.

- [ ] **Step 4: Run analyzer**

```
flutter analyze lib/l10n
```
Expected: `No issues found!`

- [ ] **Step 5: Commit**

```
git add movile_app/lib/l10n/
git commit -m "feat(logging): add i18n strings for diagnostics screen"
```

---

## Task 19: Build `logs_screen.dart`

**Files:**
- Create: `movile_app/lib/src/features/logs/widgets/log_list_tile.dart`
- Create: `movile_app/lib/src/features/logs/widgets/log_filter_bar.dart`
- Create: `movile_app/lib/src/features/logs/log_detail_sheet.dart`
- Create: `movile_app/lib/src/features/logs/logs_screen.dart`

- [ ] **Step 1: Implement `log_list_tile.dart`**

`movile_app/lib/src/features/logs/widgets/log_list_tile.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../services/logging/log_entry.dart';
import '../../../services/logging/log_level.dart';

class LogListTile extends StatelessWidget {
  const LogListTile({super.key, required this.entry, required this.onTap});

  final LogEntry entry;
  final VoidCallback onTap;

  static final _fmt = DateFormat('HH:mm:ss');

  Color _colorFor(LogLevel l) => switch (l) {
        LogLevel.debug => Colors.grey,
        LogLevel.info => Colors.blue,
        LogLevel.warning => Colors.orange,
        LogLevel.error => Colors.red,
      };

  @override
  Widget build(BuildContext context) {
    final color = _colorFor(entry.level);
    return InkWell(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          border: Border(left: BorderSide(color: color, width: 4)),
        ),
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(entry.level.shortCode,
                    style: TextStyle(color: color, fontWeight: FontWeight.bold)),
                const SizedBox(width: 8),
                Text(entry.tag,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                const Spacer(),
                Text(_fmt.format(entry.timestamp.toLocal())),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              entry.message,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Implement `log_filter_bar.dart`**

`movile_app/lib/src/features/logs/widgets/log_filter_bar.dart`:

```dart
import 'package:flutter/material.dart';

import '../../../services/logging/log_level.dart';

class LogFilterBar extends StatelessWidget {
  const LogFilterBar({
    super.key,
    required this.level,
    required this.tag,
    required this.search,
    required this.onLevelChanged,
    required this.onTagChanged,
    required this.onSearchChanged,
  });

  final LogLevel level;
  final String? tag;
  final String search;
  final ValueChanged<LogLevel> onLevelChanged;
  final ValueChanged<String?> onTagChanged;
  final ValueChanged<String> onSearchChanged;

  static const _tags = <String>[
    'supabase',
    'mapbox',
    'auth',
    'sync',
    'flutter',
    'dart',
    'http',
    'location',
    'app',
    'zone',
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Column(
        children: [
          Row(
            children: [
              for (final l in LogLevel.values)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text(l.shortCode),
                    selected: l == level,
                    onSelected: (_) => onLevelChanged(l),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                ChoiceChip(
                  label: const Text('all'),
                  selected: tag == null,
                  onSelected: (_) => onTagChanged(null),
                ),
                const SizedBox(width: 6),
                for (final t in _tags) ...[
                  ChoiceChip(
                    label: Text(t),
                    selected: tag == t,
                    onSelected: (_) => onTagChanged(t),
                  ),
                  const SizedBox(width: 6),
                ],
              ],
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Buscar…',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: onSearchChanged,
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 3: Implement `log_detail_sheet.dart`**

`movile_app/lib/src/features/logs/log_detail_sheet.dart`:

```dart
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../../services/logging/log_entry.dart';

class LogDetailSheet extends StatelessWidget {
  const LogDetailSheet({super.key, required this.entry});

  final LogEntry entry;

  String _format() {
    final buf = StringBuffer()
      ..writeln('[${entry.level.name.toUpperCase()}] ${entry.timestamp.toIso8601String()}')
      ..writeln('tag: ${entry.tag}')
      ..writeln('app: ${entry.appVersion}  platform: ${entry.platform}  device: ${entry.deviceModel}')
      ..writeln('user: ${entry.userId ?? '(anon)'}')
      ..writeln()
      ..writeln('message:')
      ..writeln(entry.message);
    if (entry.error != null) {
      buf
        ..writeln()
        ..writeln('error:')
        ..writeln(entry.error);
    }
    if (entry.stackTrace != null) {
      buf
        ..writeln()
        ..writeln('stack:')
        ..writeln(entry.stackTrace);
    }
    if (entry.context != null && entry.context!.isNotEmpty) {
      buf
        ..writeln()
        ..writeln('context:')
        ..writeln(const JsonEncoder.withIndent('  ').convert(entry.context));
    }
    return buf.toString();
  }

  @override
  Widget build(BuildContext context) {
    final text = _format();
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.copy),
                  tooltip: 'Copiar',
                  onPressed: () =>
                      Clipboard.setData(ClipboardData(text: text)),
                ),
                IconButton(
                  icon: const Icon(Icons.share),
                  tooltip: 'Compartir',
                  onPressed: () => SharePlus.instance.share(
                    ShareParams(text: text),
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const Divider(),
            Flexible(
              child: SingleChildScrollView(
                child: SelectableText(
                  text,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
```

Note: if `share_plus`'s `SharePlus.instance.share(ShareParams(...))` API differs in the version installed, fall back to the older static call `Share.share(text)`. Verify with `cat pubspec.lock | grep share_plus`.

- [ ] **Step 4: Implement `logs_screen.dart`**

`movile_app/lib/src/features/logs/logs_screen.dart`:

```dart
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../services/logging/app_logger.dart';
import '../../services/logging/log_entry.dart';
import '../../services/logging/log_level.dart';
import '../../services/logging/log_uploader.dart';
import '../../services/logging/sinks/local_sink.dart';
import 'log_detail_sheet.dart';
import 'widgets/log_filter_bar.dart';
import 'widgets/log_list_tile.dart';

class LogsScreen extends StatefulWidget {
  const LogsScreen({
    super.key,
    required this.sink,
    required this.uploader,
  });

  final LocalSink sink;
  final LogUploader uploader;

  @override
  State<LogsScreen> createState() => _LogsScreenState();
}

class _LogsScreenState extends State<LogsScreen> {
  LogLevel _level = LogLevel.debug;
  String? _tag;
  String _search = '';
  List<LogEntry> _entries = const [];
  int _pending = 0;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final entries = await widget.sink.list(
      level: _level,
      tag: _tag,
      search: _search,
      limit: 500,
    );
    final pending = await widget.sink.countPending();
    if (!mounted) return;
    setState(() {
      _entries = entries;
      _pending = pending;
    });
  }

  Future<void> _uploadNow() async {
    await widget.uploader.drain();
    await _reload();
  }

  Future<void> _shareAll() async {
    final dir = await getTemporaryDirectory();
    final file = File(p.join(dir.path, 'splitway-logs.txt'));
    final text = _entries.map(_format).join('\n---\n');
    await file.writeAsString(text);
    await SharePlus.instance.share(
      ShareParams(files: [XFile(file.path)]),
    );
  }

  Future<void> _clearAll() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('¿Borrar todos los logs?'),
        content: const Text('Esta acción no se puede deshacer.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Borrar'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await widget.sink.deleteAll();
      await _reload();
    }
  }

  String _format(LogEntry e) =>
      '[${e.level.name.toUpperCase()}] ${e.timestamp.toIso8601String()} ${e.tag} :: ${e.message}'
      '${e.error == null ? '' : '\n  error: ${e.error}'}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Diagnóstico'),
        actions: [
          IconButton(
            tooltip: 'Subir ahora',
            icon: const Icon(Icons.cloud_upload),
            onPressed: _uploadNow,
          ),
          IconButton(
            tooltip: 'Compartir todo',
            icon: const Icon(Icons.share),
            onPressed: _shareAll,
          ),
          IconButton(
            tooltip: 'Borrar todo',
            icon: const Icon(Icons.delete_forever),
            onPressed: _clearAll,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: Chip(label: Text('$_pending pendientes de subir')),
          ),
          LogFilterBar(
            level: _level,
            tag: _tag,
            search: _search,
            onLevelChanged: (v) {
              setState(() => _level = v);
              _reload();
            },
            onTagChanged: (v) {
              setState(() => _tag = v);
              _reload();
            },
            onSearchChanged: (v) {
              setState(() => _search = v);
              _reload();
            },
          ),
          const Divider(height: 1),
          Expanded(
            child: _entries.isEmpty
                ? const Center(child: Text('No hay logs todavía'))
                : ListView.separated(
                    itemCount: _entries.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) => LogListTile(
                      entry: _entries[i],
                      onTap: () => showModalBottomSheet(
                        context: context,
                        isScrollControlled: true,
                        builder: (_) => LogDetailSheet(entry: _entries[i]),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 5: Run analyzer**

```
cd movile_app && flutter analyze lib/src/features/logs
```
Expected: `No issues found!`

- [ ] **Step 6: Commit**

```
git add movile_app/lib/src/features/logs/
git commit -m "feat(logging): add Diagnostics screen with filters, share and clear"
```

---

## Task 20: Widget test for `LogsScreen`

**Files:**
- Test: `movile_app/test/features/logs/logs_screen_test.dart`

- [ ] **Step 1: Write the failing test**

`movile_app/test/features/logs/logs_screen_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_common_ffi.dart';
import 'package:splitway_mobile/src/data/local/splitway_local_database.dart';
import 'package:splitway_mobile/src/features/logs/logs_screen.dart';
import 'package:splitway_mobile/src/services/logging/log_entry.dart';
import 'package:splitway_mobile/src/services/logging/log_level.dart';
import 'package:splitway_mobile/src/services/logging/log_uploader.dart';
import 'package:splitway_mobile/src/services/logging/sinks/local_sink.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late SplitwayLocalDatabase db;
  late LocalSink sink;
  late LogUploader uploader;

  setUp(() async {
    db = await SplitwayLocalDatabase.open(overridePath: inMemoryDatabasePath);
    sink = LocalSink(db);
    uploader = LogUploader(sink: sink, upload: (_) async {});
    await sink.write(LogEntry(
      id: '1',
      timestamp: DateTime.now().toUtc(),
      level: LogLevel.error,
      tag: 'supabase',
      message: 'upsert failed',
      appVersion: '0.4.0+1',
      platform: 'test',
      deviceModel: 'test',
    ));
  });

  tearDown(() async => db.close());

  testWidgets('renders the only log entry', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: LogsScreen(sink: sink, uploader: uploader),
    ));
    await tester.pumpAndSettle();
    expect(find.text('upsert failed'), findsOneWidget);
    expect(find.text('supabase'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run it to verify it passes (or compiles)**

```
cd movile_app && flutter test test/features/logs/logs_screen_test.dart
```
Expected: `All tests passed!` If it fails because of platform-channel issues with `share_plus`, mark the widget test as skipping the share button interaction (the test above only checks rendering and avoids it).

- [ ] **Step 3: Commit**

```
git add movile_app/test/features/logs/logs_screen_test.dart
git commit -m "test(logging): widget test for LogsScreen rendering"
```

---

## Task 21: Add `/settings/logs` route and Settings entrypoint

**Files:**
- Modify: `movile_app/lib/src/routing/app_router.dart`
- Modify: `movile_app/lib/src/features/settings/settings_screen.dart`
- Modify: `movile_app/lib/src/app.dart` (if `LocalSink`/`LogUploader` need to be exposed)

`LogsScreen` needs `LocalSink` and `LogUploader`. The simplest path: expose them as static `AppLogger.localSink` / `AppLogger.uploader` getters set by `main.dart` after install. We extend `AppLogger.install` to accept these optional handles (purely for UI access).

- [ ] **Step 1: Extend `AppLogger` with optional UI handles**

In `movile_app/lib/src/services/logging/app_logger.dart`, add private static fields and a setter:

```dart
  static LocalSink? _localSink;
  static LogUploader? _uploader;

  static LocalSink? get localSink => _localSink;
  static LogUploader? get uploader => _uploader;

  static void attachUiHandles({LocalSink? sink, LogUploader? uploader}) {
    _localSink = sink;
    _uploader = uploader;
  }
```

Add the imports inside the file:
```dart
import 'sinks/local_sink.dart';
import 'log_uploader.dart';
```

- [ ] **Step 2: Wire them in `main.dart`**

In `movile_app/lib/main.dart`, after the `RemoteSink(uploader)` line and before `runApp`, add:

```dart
    AppLogger.attachUiHandles(sink: localSink, uploader: uploader);
```

- [ ] **Step 3: Add the GoRoute**

In `movile_app/lib/src/routing/app_router.dart`:

Add import:
```dart
import '../features/logs/logs_screen.dart';
import '../services/logging/app_logger.dart';
```

Inside the `routes:` list of the `GoRouter`, next to the existing `/settings` route, add:

```dart
      GoRoute(
        path: '/settings/logs',
        builder: (_, __) {
          final sink = AppLogger.localSink;
          final uploader = AppLogger.uploader;
          if (sink == null || uploader == null) {
            return const Scaffold(
              body: Center(child: Text('Logger not initialized')),
            );
          }
          return LogsScreen(sink: sink, uploader: uploader);
        },
      ),
```

- [ ] **Step 4: Add a tile in `settings_screen.dart`**

In `movile_app/lib/src/features/settings/settings_screen.dart`, inside the `ListView`'s `children:` (anywhere near the bottom), add:

```dart
            const Divider(),
            _SectionHeader('Diagnóstico'),
            ListTile(
              leading: const Icon(Icons.bug_report_outlined),
              title: const Text('Ver logs'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/settings/logs'),
            ),
            SwitchListTile(
              title: const Text('Subir logs al servidor'),
              value: settingsController.remoteLogsEnabled,
              onChanged: settingsController.setRemoteLogsEnabled,
            ),
```

(Use the localized strings from Task 18 if you wired them up; otherwise the inline Spanish is fine as a placeholder until i18n is regenerated.)

- [ ] **Step 5: Run analyzer + tests**

```
cd movile_app && flutter analyze && flutter test
```
Expected: green.

- [ ] **Step 6: Commit**

```
git add movile_app/lib/src/services/logging/app_logger.dart movile_app/lib/main.dart movile_app/lib/src/routing/app_router.dart movile_app/lib/src/features/settings/settings_screen.dart
git commit -m "feat(logging): expose /settings/logs route and Diagnostics entry"
```

---

## Task 22: Periodic retention sweep

**Files:**
- Modify: `movile_app/lib/src/services/logging/sinks/local_sink.dart` (add counter)
- Modify: `movile_app/lib/src/services/logging/app_logger.dart` (trigger sweep)

We sweep once every 100 writes to stay within the spec's 7d / 2000 rows budget.

- [ ] **Step 1: Add counter + sweep in `LocalSink`**

In `movile_app/lib/src/services/logging/sinks/local_sink.dart`, add a private counter at the top of the class:

```dart
  int _writesSinceSweep = 0;
  static const int _sweepEvery = 100;
  static const int _maxRows = 2000;
  static const Duration _retention = Duration(days: 7);
```

Inside `write`, after the successful `_raw.insert(...)`, add:

```dart
      _writesSinceSweep++;
      if (_writesSinceSweep >= _sweepEvery) {
        _writesSinceSweep = 0;
        unawaited(_sweep());
      }
```

Add `import 'dart:async';` at the top if not present.

Add the helper at the bottom of the class:

```dart
  Future<void> _sweep() async {
    try {
      await purgeOlderThan(DateTime.now().toUtc().subtract(_retention));
      await trimToMaxCount(_maxRows);
    } catch (_) {}
  }
```

- [ ] **Step 2: Re-run `LocalSink` tests to make sure nothing broke**

```
cd movile_app && flutter test test/services/logging/local_sink_test.dart
```
Expected: `All tests passed!`

- [ ] **Step 3: Commit**

```
git add movile_app/lib/src/services/logging/sinks/local_sink.dart
git commit -m "feat(logging): periodic retention sweep every 100 writes"
```

---

## Task 23: Manual smoke test

- [ ] **Step 1: Build a debug APK and install**

```
cd movile_app && flutter run
```

- [ ] **Step 2: Force an error to verify the flow**

Sign in with a Supabase user, then either:
- Disconnect the network and trigger a route upsert (should log a Supabase warning).
- Edit `env/local.json` temporarily to a wrong `MAPBOX_ACCESS_TOKEN` and trigger a geocode (should log an HTTP 401 warning).

- [ ] **Step 3: Open Settings → Diagnóstico → Ver logs**

Expected: see at least one entry. Tap it: detail sheet renders with sanitized URL (no token in plain text). Tap "Subir ahora": pending count drops to 0.

- [ ] **Step 4: Verify in Supabase**

In the Supabase dashboard SQL editor:
```sql
select id, timestamp, level, tag, message
from public.app_logs
order by timestamp desc limit 10;
```

Expected: the entries from step 2 appear with `user_id` populated.

- [ ] **Step 5: Restore env/local.json and commit anything pending**

```
git status
```
If `env/local.json` is dirty, restore: `git checkout -- movile_app/env/local.json`.

---

## Task 24: Final verification and PR

- [ ] **Step 1: Run the full test suite**

```
cd movile_app && flutter test
```
Expected: all green.

- [ ] **Step 2: Run analyzer end to end**

```
cd movile_app && flutter analyze
```
Expected: `No issues found!`

- [ ] **Step 3: Push the branch and open a PR**

```
git push -u origin feat/logging-system
gh pr create --title "feat: sistema de logs (in-app + Supabase)" --body "$(cat <<'EOF'
## Summary
- Add centralized `AppLogger` capturing Supabase, Mapbox/HTTP, auth, GPS and Flutter framework errors.
- Persist locally in SQLite with retention (7d / 2000 rows) and sync to a new `app_logs` table in Supabase via a retry queue.
- Add "Diagnóstico" screen under Settings: filter, share, copy, upload, clear.

## Test plan
- [ ] `flutter test` is green.
- [ ] Smoke test: disconnect network → trigger a route upsert → see entry in `/settings/logs`.
- [ ] Smoke test: wrong Mapbox token → reverse geocode → 401 logged.
- [ ] Supabase dashboard shows entries with `user_id` populated.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

Expected: PR URL printed.

---

## Self-review notes

This plan covers, in order against the spec:

| Spec section                  | Tasks                  |
| ----------------------------- | ---------------------- |
| Arquitectura (3 capas)        | 5, 7, 9, 10            |
| Captura automática (global)   | 14                     |
| Helpers `logSupabase`/`logHttp` | 11, 15, 16            |
| Modelo `LogEntry`             | 1, 2                   |
| Tabla SQLite + migración      | 6                      |
| Tabla Supabase + RLS + cron   | 13                     |
| Sanitización                  | 3, 10                  |
| Puntos de captura concretos   | 15, 16, 17             |
| Pantalla in-app               | 18, 19, 20, 21         |
| Retención local               | 7, 22                  |
| Configuración                 | 12, 21                 |
| Testing                       | 2, 3, 7, 8, 10, 11, 20 |

Risks of "log storms" and PII in stack traces are addressed by the rate limiter (Task 10) and the sanitizer (Task 3). Migration risk is contained by adding only a new table guarded with `IF NOT EXISTS` (Task 6).
