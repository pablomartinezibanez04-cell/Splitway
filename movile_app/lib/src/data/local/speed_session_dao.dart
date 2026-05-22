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
