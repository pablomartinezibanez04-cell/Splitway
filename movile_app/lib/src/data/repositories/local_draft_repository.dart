import 'dart:async';
import 'dart:convert';

import 'package:splitway_core/splitway_core.dart';
import 'package:sqflite/sqflite.dart';

import '../local/splitway_local_database.dart';

class LocalDraftRepository {
  LocalDraftRepository(this._database);

  final SplitwayLocalDatabase _database;
  Database get _db => _database.raw;

  final StreamController<void> _changes =
      StreamController<void>.broadcast();
  Stream<void> get changes => _changes.stream;

  // ---------- Routes ----------

  Future<void> saveRouteTemplate(RouteTemplate route) async {
    await _db.transaction((txn) async {
      await txn.insert(
        'route_templates',
        {
          'id': route.id,
          'name': route.name,
          'description': route.description,
          'path_json': jsonEncode(route.path.map((p) => p.toJson()).toList()),
          'start_finish_gate_json':
              jsonEncode(route.startFinishGate.toJson()),
          'difficulty': route.difficulty.id,
          'created_at': route.createdAt.toUtc().millisecondsSinceEpoch,
          'location_label': route.locationLabel,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await txn.delete('sectors', where: 'route_id = ?', whereArgs: [route.id]);
      for (final sector in route.sectors) {
        await txn.insert('sectors', {
          'id': sector.id,
          'route_id': route.id,
          'order_index': sector.order,
          'label': sector.label,
          'gate_json': jsonEncode(sector.gate.toJson()),
        });
      }
    });
    _changes.add(null);
  }

  Future<RouteTemplate?> getRouteTemplate(String id) async {
    final routes = await _db
        .query('route_templates', where: 'id = ?', whereArgs: [id], limit: 1);
    if (routes.isEmpty) return null;
    return _readRoute(routes.first);
  }

  Future<List<RouteTemplate>> getAllRoutes() async {
    final rows = await _db.query('route_templates', orderBy: 'created_at DESC');
    return Future.wait(rows.map(_readRoute));
  }

  Future<RouteTemplate> _readRoute(Map<String, Object?> row) async {
    final routeId = row['id']! as String;
    final sectorRows = await _db.query(
      'sectors',
      where: 'route_id = ?',
      whereArgs: [routeId],
      orderBy: 'order_index ASC',
    );
    final sectors = sectorRows.map((s) {
      final gateJson =
          jsonDecode(s['gate_json']! as String) as Map<String, dynamic>;
      return SectorDefinition(
        id: s['id']! as String,
        order: s['order_index']! as int,
        label: s['label']! as String,
        gate: GateDefinition.fromJson(gateJson),
      );
    }).toList();

    final pathJson =
        jsonDecode(row['path_json']! as String) as List<dynamic>;
    final gateJson = jsonDecode(row['start_finish_gate_json']! as String)
        as Map<String, dynamic>;

    return RouteTemplate(
      id: routeId,
      name: row['name']! as String,
      description: row['description'] as String?,
      path: pathJson
          .map((e) => GeoPoint.fromJson(e as Map<String, dynamic>))
          .toList(),
      startFinishGate: GateDefinition.fromJson(gateJson),
      sectors: sectors,
      difficulty: RouteDifficultyX.fromId(row['difficulty']! as String),
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        row['created_at']! as int,
        isUtc: true,
      ).toLocal(),
      locationLabel: row['location_label'] as String?,
    );
  }

  Future<void> updateRouteTemplateName(String id, String name) async {
    await _db.update(
      'route_templates',
      {'name': name},
      where: 'id = ?',
      whereArgs: [id],
    );
    _changes.add(null);
  }

  Future<void> deleteRoute(String id) async {
    await _db.delete('route_templates', where: 'id = ?', whereArgs: [id]);
    _changes.add(null);
  }

  // ---------- Sessions ----------

  Future<void> saveSessionRun(SessionRun session) async {
    await _db.transaction((txn) async {
      await txn.insert(
        'session_runs',
        {
          'id': session.id,
          'route_id': session.routeTemplateId,
          'started_at': session.startedAt.toUtc().millisecondsSinceEpoch,
          'ended_at':
              session.endedAt?.toUtc().millisecondsSinceEpoch,
          'status': session.status.id,
          'lap_summaries_json':
              jsonEncode(session.laps.map((l) => l.toJson()).toList()),
          'sector_summaries_json': jsonEncode(
              session.sectorSummaries.map((s) => s.toJson()).toList()),
          'total_distance_m': session.totalDistanceMeters,
          'max_speed_mps': session.maxSpeedMps,
          'avg_speed_mps': session.avgSpeedMps,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await txn.delete('telemetry_points',
          where: 'session_id = ?', whereArgs: [session.id]);
      final batch = txn.batch();
      for (final p in session.points) {
        batch.insert('telemetry_points', {
          'session_id': session.id,
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

  Future<SessionRun?> getSessionRun(String id) async {
    final rows = await _db
        .query('session_runs', where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return null;
    return _readSession(rows.first, includePoints: true);
  }

  Future<List<SessionRun>> getAllSessions({bool includePoints = false}) async {
    final rows = await _db.query('session_runs', orderBy: 'started_at DESC');
    return Future.wait(
      rows.map((r) => _readSession(r, includePoints: includePoints)),
    );
  }

  Future<List<SessionRun>> getSessionsByRoute(String routeId) async {
    final rows = await _db.query(
      'session_runs',
      where: 'route_id = ?',
      whereArgs: [routeId],
      orderBy: 'started_at DESC',
    );
    return Future.wait(rows.map((r) => _readSession(r)));
  }

  Future<SessionRun> _readSession(
    Map<String, Object?> row, {
    bool includePoints = false,
  }) async {
    final id = row['id']! as String;
    final laps = (jsonDecode(row['lap_summaries_json']! as String)
            as List<dynamic>)
        .map((e) => LapSummary.fromJson(e as Map<String, dynamic>))
        .toList();
    final sectorSummaries = (jsonDecode(row['sector_summaries_json']! as String)
            as List<dynamic>)
        .map((e) => SectorSummary.fromJson(e as Map<String, dynamic>))
        .toList();

    List<TelemetryPoint> points = const [];
    if (includePoints) {
      final tRows = await _db.query(
        'telemetry_points',
        where: 'session_id = ?',
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

    return SessionRun(
      id: id,
      routeTemplateId: row['route_id']! as String,
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
      status: SessionStatusX.fromId(row['status']! as String),
      points: points,
      laps: laps,
      sectorSummaries: sectorSummaries,
      totalDistanceMeters: (row['total_distance_m']! as num).toDouble(),
      maxSpeedMps: (row['max_speed_mps']! as num).toDouble(),
      avgSpeedMps: (row['avg_speed_mps']! as num).toDouble(),
    );
  }

  Future<void> deleteSession(String id) async {
    await _db.delete('session_runs', where: 'id = ?', whereArgs: [id]);
    _changes.add(null);
  }

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

  // ---------- Cloud sync ----------

  /// Triggers a full bidirectional sync with Supabase.
  /// Requires a [SyncService] to be configured and passed externally.
  /// This method is kept here for backward compatibility with the original API;
  /// in practice, use [SyncService.sync()] directly for more control.
  Future<void> syncWithCloud() async {
    // No-op: use SyncService directly for bidirectional sync.
    // Kept as non-throwing to allow callers that reference it to compile.
  }

  Future<void> dispose() async {
    await _changes.close();
  }
}
