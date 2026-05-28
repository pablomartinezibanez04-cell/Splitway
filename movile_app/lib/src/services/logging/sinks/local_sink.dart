import 'dart:async';

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

  int _writesSinceSweep = 0;
  static const int _sweepEvery = 100;
  static const int _maxRows = 2000;
  static const Duration _retention = Duration(days: 7);

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
      _writesSinceSweep++;
      if (_writesSinceSweep >= _sweepEvery) {
        _writesSinceSweep = 0;
        unawaited(_sweep());
      }
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

  /// Keeps only the [maxCount] most recent rows.
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
      final allowed = _levelsAtOrAbove(level);
      where.add('level IN (${allowed.map((_) => '?').join(',')})');
      args.addAll(allowed.map((l) => l.name));
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

  Future<void> _sweep() async {
    try {
      await purgeOlderThan(DateTime.now().toUtc().subtract(_retention));
      await trimToMaxCount(_maxRows);
    } catch (_) {}
  }

  List<LogLevel> _levelsAtOrAbove(LogLevel min) =>
      LogLevel.values.where((l) => l.index >= min.index).toList();
}
