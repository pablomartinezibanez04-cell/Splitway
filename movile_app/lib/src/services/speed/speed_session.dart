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

  SpeedSession copyWith({
    String? name,
    DateTime? updatedAt,
  }) {
    return SpeedSession(
      id: id,
      userId: userId,
      vehicleId: vehicleId,
      name: name ?? this.name,
      selectedMetrics: selectedMetrics,
      results: results,
      countdownSeconds: countdownSeconds,
      isPartial: isPartial,
      startedAt: startedAt,
      finishedAt: finishedAt,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt,
    );
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
