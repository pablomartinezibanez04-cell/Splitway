import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:splitway_core/splitway_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/route_thumbnail_service.dart';

/// Remote repository backed by Supabase Postgres + RLS.
/// Each row has an `owner_id` populated from the current [User].
///
/// This class handles:
/// - Pushing local routes/sessions to the cloud.
/// - Pulling remote data that may have been created on another device.
/// - Last-write-wins conflict resolution via `updated_at`.
class SupabaseRepository {
  SupabaseRepository(this._client, {this.thumbnailService});

  final SupabaseClient _client;
  final RouteThumbnailService? thumbnailService;

  String get _uid => _client.auth.currentUser!.id;

  // ---------- Routes ----------

  /// Upserts a route template (with sectors) to Supabase.
  /// If [thumbnailUrl] is null and [thumbnailService] is configured,
  /// generates a thumbnail before upserting. Returns the (possibly updated)
  /// route.
  Future<RouteTemplate> upsertRoute(RouteTemplate route) async {
    // Generate thumbnail if missing and service is available
    if (route.thumbnailUrl == null && thumbnailService != null) {
      try {
        final url = await thumbnailService!.generate(route, _uid);
        route = route.copyWith(thumbnailUrl: url);
      } catch (e) {
        // Log but continue — route sync must not fail because of thumbnail
        debugPrint('Thumbnail generation failed: $e');
      }
    }

    await _client.from('route_templates').upsert({
      'id': route.id,
      'owner_id': _uid,
      'name': route.name,
      'description': route.description,
      'path_json': route.path.map((p) => p.toJson()).toList(),
      'start_finish_gate_json': route.startFinishGate.toJson(),
      'difficulty': route.difficulty.id,
      'location_label': route.locationLabel,
      'created_at': route.createdAt.toUtc().toIso8601String(),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
      'thumbnail_url': route.thumbnailUrl,
    });

    // Delete old sectors and re-insert
    await _client.from('sectors').delete().eq('route_id', route.id);
    if (route.sectors.isNotEmpty) {
      await _client.from('sectors').insert(
        route.sectors.map((s) => {
          'id': s.id,
          'route_id': route.id,
          'order_index': s.order,
          'label': s.label,
          'gate_json': s.gate.toJson(),
        }).toList(),
      );
    }

    return route;
  }

  /// Fetches all routes belonging to the current user.
  Future<List<RouteTemplate>> fetchAllRoutes() async {
    final rows = await _client
        .from('route_templates')
        .select()
        .order('created_at', ascending: false);

    final routes = <RouteTemplate>[];
    for (final row in rows) {
      final sectorRows = await _client
          .from('sectors')
          .select()
          .eq('route_id', row['id'] as String)
          .order('order_index');
      routes.add(_parseRoute(row, sectorRows));
    }
    return routes;
  }

  /// Deletes a route from the cloud.
  Future<void> deleteRoute(String id) async {
    await _client.from('route_templates').delete().eq('id', id);
  }

  // ---------- Sessions ----------

  /// Upserts a session run (metadata + telemetry) to Supabase atomically.
  Future<void> upsertSession(SessionRun session) async {
    await _client.rpc('upsert_session_with_telemetry', params: {
      'p_id': session.id,
      'p_route_id': session.routeTemplateId,
      'p_started_at': session.startedAt.toUtc().toIso8601String(),
      'p_ended_at': session.endedAt?.toUtc().toIso8601String(),
      'p_status': session.status.id,
      'p_lap_summaries': session.laps.map((l) => l.toJson()).toList(),
      'p_sector_summaries':
          session.sectorSummaries.map((s) => s.toJson()).toList(),
      'p_total_distance_m': session.totalDistanceMeters,
      'p_max_speed_mps': session.maxSpeedMps,
      'p_avg_speed_mps': session.avgSpeedMps,
      'p_updated_at': DateTime.now().toUtc().toIso8601String(),
      'p_points': session.points
          .map((p) => {
                'ts': p.timestamp.toUtc().toIso8601String(),
                'lat': p.location.latitude,
                'lng': p.location.longitude,
                'speed_mps': p.speedMps,
                'accuracy_m': p.accuracyMeters,
                'bearing_deg': p.bearingDeg,
                'altitude_m': p.altitudeMeters,
              })
          .toList(),
    });
  }

  /// Fetches all sessions belonging to the current user.
  Future<List<SessionRun>> fetchAllSessions(
      {bool includePoints = false}) async {
    final rows = await _client
        .from('session_runs')
        .select()
        .order('started_at', ascending: false);

    final sessions = <SessionRun>[];
    for (final row in rows) {
      List<TelemetryPoint> points = const [];
      if (includePoints) {
        final tRows = await _client
            .from('telemetry_points')
            .select()
            .eq('session_id', row['id'] as String)
            .order('ts');
        points = tRows.map(_parseTelemetryPoint).toList();
      }
      sessions.add(_parseSession(row, points));
    }
    return sessions;
  }

  /// Fetches a single session by [id], optionally with telemetry points.
  Future<SessionRun?> fetchSession(
    String id, {
    bool includePoints = false,
  }) async {
    final rows = await _client
        .from('session_runs')
        .select()
        .eq('id', id)
        .limit(1);
    if (rows.isEmpty) return null;
    List<TelemetryPoint> points = const [];
    if (includePoints) {
      final tRows = await _client
          .from('telemetry_points')
          .select()
          .eq('session_id', id)
          .order('ts');
      points = tRows.map(_parseTelemetryPoint).toList();
    }
    return _parseSession(rows.first, points);
  }

  /// Deletes a session from the cloud.
  Future<void> deleteSession(String id) async {
    await _client.from('session_runs').delete().eq('id', id);
  }

  // ---------- Free rides ----------

  /// Upserts a free ride run (metadata + telemetry) to Supabase atomically.
  Future<void> upsertFreeRide(FreeRideRun ride) async {
    await _client.rpc('upsert_free_ride_with_telemetry', params: {
      'p_id': ride.id,
      'p_started_at': ride.startedAt.toUtc().toIso8601String(),
      'p_ended_at': ride.endedAt?.toUtc().toIso8601String(),
      'p_status': ride.status.id,
      'p_total_distance_m': ride.totalDistanceMeters,
      'p_max_speed_mps': ride.maxSpeedMps,
      'p_avg_speed_mps': ride.avgSpeedMps,
      'p_name': ride.name,
      'p_description': ride.description,
      'p_location_label': ride.locationLabel,
      'p_updated_at': DateTime.now().toUtc().toIso8601String(),
      'p_points': ride.points
          .map((p) => {
                'ts': p.timestamp.toUtc().toIso8601String(),
                'lat': p.location.latitude,
                'lng': p.location.longitude,
                'speed_mps': p.speedMps,
                'accuracy_m': p.accuracyMeters,
                'bearing_deg': p.bearingDeg,
                'altitude_m': p.altitudeMeters,
              })
          .toList(),
    });
  }

  /// Fetches all free rides belonging to the current user (without telemetry).
  Future<List<FreeRideRun>> fetchAllFreeRides() async {
    final rows = await _client
        .from('free_rides')
        .select()
        .order('started_at', ascending: false);
    return rows.map((r) => _parseFreeRide(r, const [])).toList();
  }

  /// Fetches a single free ride by [id], optionally with telemetry points.
  Future<FreeRideRun?> fetchFreeRide(
    String id, {
    bool includePoints = false,
  }) async {
    final rows = await _client
        .from('free_rides')
        .select()
        .eq('id', id)
        .limit(1);
    if (rows.isEmpty) return null;
    List<TelemetryPoint> points = const [];
    if (includePoints) {
      final tRows = await _client
          .from('free_ride_telemetry')
          .select()
          .eq('free_ride_id', id)
          .order('ts');
      points = tRows.map(_parseTelemetryPoint).toList();
    }
    return _parseFreeRide(rows.first, points);
  }

  /// Returns remote free ride IDs with their `updated_at` timestamps.
  Future<Map<String, DateTime>> fetchFreeRideTimestamps() async {
    final rows = await _client
        .from('free_rides')
        .select('id, updated_at');
    return {
      for (final r in rows)
        r['id'] as String: DateTime.parse(r['updated_at'] as String),
    };
  }

  // ---------- Sync helpers ----------

  /// Returns remote route IDs with their `updated_at` timestamps for
  /// diffing against local state.
  Future<Map<String, DateTime>> fetchRouteTimestamps() async {
    final rows = await _client
        .from('route_templates')
        .select('id, updated_at');
    return {
      for (final r in rows)
        r['id'] as String: DateTime.parse(r['updated_at'] as String),
    };
  }

  /// Returns remote session IDs with their `updated_at` timestamps.
  Future<Map<String, DateTime>> fetchSessionTimestamps() async {
    final rows = await _client
        .from('session_runs')
        .select('id, updated_at');
    return {
      for (final r in rows)
        r['id'] as String: DateTime.parse(r['updated_at'] as String),
    };
  }

  // ---------- Parsers ----------

  RouteTemplate _parseRoute(
      Map<String, dynamic> row, List<Map<String, dynamic>> sectorRows) {
    final pathJson = row['path_json'];
    final List<dynamic> pathList =
        pathJson is String ? jsonDecode(pathJson) as List<dynamic> : pathJson as List<dynamic>;
    final gateJson = row['start_finish_gate_json'];
    final Map<String, dynamic> gateMap =
        gateJson is String ? jsonDecode(gateJson) as Map<String, dynamic> : Map<String, dynamic>.from(gateJson as Map);

    final sectors = sectorRows.map((s) {
      final sGate = s['gate_json'];
      final Map<String, dynamic> sGateMap =
          sGate is String ? jsonDecode(sGate) as Map<String, dynamic> : Map<String, dynamic>.from(sGate as Map);
      return SectorDefinition(
        id: s['id'] as String,
        order: s['order_index'] as int,
        label: s['label'] as String,
        gate: GateDefinition.fromJson(sGateMap),
      );
    }).toList();

    return RouteTemplate(
      id: row['id'] as String,
      name: row['name'] as String,
      description: row['description'] as String?,
      path: pathList
          .map((e) => GeoPoint.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
      startFinishGate: GateDefinition.fromJson(gateMap),
      sectors: sectors,
      difficulty: RouteDifficultyX.fromId(row['difficulty'] as String),
      locationLabel: row['location_label'] as String?,
      createdAt: DateTime.parse(row['created_at'] as String).toLocal(),
      thumbnailUrl: row['thumbnail_url'] as String?,
    );
  }

  SessionRun _parseSession(
      Map<String, dynamic> row, List<TelemetryPoint> points) {
    final lapsJson = row['lap_summaries_json'];
    final List<dynamic> lapsList =
        lapsJson is String ? jsonDecode(lapsJson) as List<dynamic> : lapsJson as List<dynamic>;
    final sectorsJson = row['sector_summaries_json'];
    final List<dynamic> sectorsList =
        sectorsJson is String ? jsonDecode(sectorsJson) as List<dynamic> : sectorsJson as List<dynamic>;

    return SessionRun(
      id: row['id'] as String,
      routeTemplateId: row['route_id'] as String,
      startedAt: DateTime.parse(row['started_at'] as String).toLocal(),
      endedAt: row['ended_at'] == null
          ? null
          : DateTime.parse(row['ended_at'] as String).toLocal(),
      status: SessionStatusX.fromId(row['status'] as String),
      points: points,
      laps: lapsList
          .map((e) => LapSummary.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
      sectorSummaries: sectorsList
          .map((e) =>
              SectorSummary.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
      totalDistanceMeters: (row['total_distance_m'] as num).toDouble(),
      maxSpeedMps: (row['max_speed_mps'] as num).toDouble(),
      avgSpeedMps: (row['avg_speed_mps'] as num).toDouble(),
    );
  }

  FreeRideRun _parseFreeRide(
      Map<String, dynamic> row, List<TelemetryPoint> points) {
    return FreeRideRun(
      id: row['id'] as String,
      startedAt: DateTime.parse(row['started_at'] as String).toLocal(),
      endedAt: row['ended_at'] == null
          ? null
          : DateTime.parse(row['ended_at'] as String).toLocal(),
      status: FreeRideStatusX.fromId(row['status'] as String),
      points: points,
      totalDistanceMeters: (row['total_distance_m'] as num).toDouble(),
      maxSpeedMps: (row['max_speed_mps'] as num).toDouble(),
      avgSpeedMps: (row['avg_speed_mps'] as num).toDouble(),
      name: row['name'] as String?,
      description: row['description'] as String?,
      locationLabel: row['location_label'] as String?,
    );
  }

  TelemetryPoint _parseTelemetryPoint(Map<String, dynamic> t) {
    return TelemetryPoint(
      timestamp: DateTime.parse(t['ts'] as String).toLocal(),
      location: GeoPoint(
        latitude: (t['lat'] as num).toDouble(),
        longitude: (t['lng'] as num).toDouble(),
      ),
      speedMps: (t['speed_mps'] as num?)?.toDouble(),
      accuracyMeters: (t['accuracy_m'] as num?)?.toDouble(),
      bearingDeg: (t['bearing_deg'] as num?)?.toDouble(),
      altitudeMeters: (t['altitude_m'] as num?)?.toDouble(),
    );
  }
}
