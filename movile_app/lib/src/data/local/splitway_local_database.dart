import 'dart:async';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

class SplitwayLocalDatabase {
  SplitwayLocalDatabase._(this._db);

  final Database _db;

  Database get raw => _db;

  static const int _schemaVersion = 10;

  static Future<SplitwayLocalDatabase> open({String? overridePath}) async {
    final path = overridePath ?? await _defaultPath();
    final db = await openDatabase(
      path,
      version: _schemaVersion,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (db, version) async {
        await _migrate(db, 0, version);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        await _migrate(db, oldVersion, newVersion);
      },
    );
    return SplitwayLocalDatabase._(db);
  }

  Future<void> close() => _db.close();

  static Future<String> _defaultPath() async {
    final dir = await getApplicationDocumentsDirectory();
    return p.join(dir.path, 'splitway.db');
  }

  static Future<void> _migrate(Database db, int from, int to) async {
    if (from < 1 && to >= 1) {
      await db.execute('''
        CREATE TABLE route_templates (
          id TEXT PRIMARY KEY NOT NULL,
          name TEXT NOT NULL,
          description TEXT,
          path_json TEXT NOT NULL,
          start_finish_gate_json TEXT NOT NULL,
          difficulty TEXT NOT NULL DEFAULT 'medium',
          created_at INTEGER NOT NULL
        )
      ''');
      await db.execute('''
        CREATE TABLE sectors (
          id TEXT PRIMARY KEY NOT NULL,
          route_id TEXT NOT NULL,
          order_index INTEGER NOT NULL,
          label TEXT NOT NULL,
          gate_json TEXT NOT NULL,
          FOREIGN KEY (route_id) REFERENCES route_templates(id) ON DELETE CASCADE
        )
      ''');
      await db.execute('''
        CREATE TABLE session_runs (
          id TEXT PRIMARY KEY NOT NULL,
          route_id TEXT NOT NULL,
          started_at INTEGER NOT NULL,
          ended_at INTEGER,
          status TEXT NOT NULL,
          lap_summaries_json TEXT NOT NULL,
          sector_summaries_json TEXT NOT NULL,
          total_distance_m REAL NOT NULL,
          max_speed_mps REAL NOT NULL,
          avg_speed_mps REAL NOT NULL,
          FOREIGN KEY (route_id) REFERENCES route_templates(id) ON DELETE CASCADE
        )
      ''');
      await db.execute('''
        CREATE TABLE telemetry_points (
          session_id TEXT NOT NULL,
          ts INTEGER NOT NULL,
          lat REAL NOT NULL,
          lng REAL NOT NULL,
          speed_mps REAL,
          accuracy_m REAL,
          bearing_deg REAL,
          altitude_m REAL,
          FOREIGN KEY (session_id) REFERENCES session_runs(id) ON DELETE CASCADE
        )
      ''');
      await db.execute(
        'CREATE INDEX idx_telemetry_session_ts ON telemetry_points(session_id, ts)',
      );
      await db.execute(
        'CREATE INDEX idx_sectors_route ON sectors(route_id, order_index)',
      );
      await db.execute(
        'CREATE INDEX idx_sessions_route_started ON session_runs(route_id, started_at DESC)',
      );
    }
    if (from < 2 && to >= 2) {
      await db.execute(
        'ALTER TABLE route_templates ADD COLUMN location_label TEXT',
      );
    }
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
    if (from < 4 && to >= 4) {
      await db.execute(
        'ALTER TABLE route_templates ADD COLUMN owner_id TEXT',
      );
      await db.execute(
        'ALTER TABLE session_runs ADD COLUMN owner_id TEXT',
      );
      await db.execute(
        'ALTER TABLE free_rides ADD COLUMN owner_id TEXT',
      );
    }
    if (from < 5 && to >= 5) {
      await db.execute(
        'ALTER TABLE route_templates ADD COLUMN thumbnail_url TEXT',
      );
    }
    if (from < 6 && to >= 6) {
      await db.execute(
        'ALTER TABLE session_runs ADD COLUMN vehicle_id TEXT',
      );
      await db.execute(
        'ALTER TABLE free_rides ADD COLUMN vehicle_id TEXT',
      );
    }
    if (from < 7 && to >= 7) {
      await db.execute(
        'ALTER TABLE route_templates ADD COLUMN elevation_range_m REAL',
      );
    }
    if (from < 8 && to >= 8) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS speed_sessions (
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
        'CREATE INDEX IF NOT EXISTS idx_speed_sessions_user_created ON speed_sessions(user_id, created_at DESC)',
      );
    }
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
    if (from < 10 && to >= 10) {
      await db.execute(
        'ALTER TABLE route_templates ADD COLUMN is_official INTEGER NOT NULL DEFAULT 0',
      );
      await db.execute(
        'ALTER TABLE route_templates ADD COLUMN updated_at INTEGER',
      );
    }
  }
}
