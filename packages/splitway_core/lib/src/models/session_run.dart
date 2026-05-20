import 'lap_summary.dart';
import 'sector_summary.dart';
import 'telemetry_point.dart';

enum SessionStatus { draft, recording, completed, synced }

extension SessionStatusX on SessionStatus {
  String get id => name;

  static SessionStatus fromId(String value) {
    return SessionStatus.values.firstWhere(
      (s) => s.name == value,
      orElse: () => SessionStatus.draft,
    );
  }
}

class SessionRun {
  const SessionRun({
    required this.id,
    required this.routeTemplateId,
    required this.startedAt,
    required this.status,
    required this.points,
    required this.laps,
    required this.sectorSummaries,
    required this.totalDistanceMeters,
    required this.maxSpeedMps,
    required this.avgSpeedMps,
    this.endedAt,
    this.vehicleId,
  });

  final String id;
  final String routeTemplateId;
  final DateTime startedAt;
  final DateTime? endedAt;
  final SessionStatus status;
  final List<TelemetryPoint> points;
  final List<LapSummary> laps;
  final List<SectorSummary> sectorSummaries;
  final double totalDistanceMeters;
  final double maxSpeedMps;
  final double avgSpeedMps;
  final String? vehicleId;

  SessionRun copyWith({
    String? id,
    String? routeTemplateId,
    DateTime? startedAt,
    DateTime? endedAt,
    SessionStatus? status,
    List<TelemetryPoint>? points,
    List<LapSummary>? laps,
    List<SectorSummary>? sectorSummaries,
    double? totalDistanceMeters,
    double? maxSpeedMps,
    double? avgSpeedMps,
    String? vehicleId,
  }) {
    return SessionRun(
      id: id ?? this.id,
      routeTemplateId: routeTemplateId ?? this.routeTemplateId,
      startedAt: startedAt ?? this.startedAt,
      endedAt: endedAt ?? this.endedAt,
      status: status ?? this.status,
      points: points ?? this.points,
      laps: laps ?? this.laps,
      sectorSummaries: sectorSummaries ?? this.sectorSummaries,
      totalDistanceMeters: totalDistanceMeters ?? this.totalDistanceMeters,
      maxSpeedMps: maxSpeedMps ?? this.maxSpeedMps,
      avgSpeedMps: avgSpeedMps ?? this.avgSpeedMps,
      vehicleId: vehicleId ?? this.vehicleId,
    );
  }

  Duration? get totalDuration {
    final end = endedAt;
    if (end == null) return null;
    return end.difference(startedAt);
  }

  LapSummary? get bestLap {
    final completed = laps.where((l) => l.completed).toList();
    if (completed.isEmpty) return null;
    completed.sort((a, b) => a.duration.compareTo(b.duration));
    return completed.first;
  }
}
