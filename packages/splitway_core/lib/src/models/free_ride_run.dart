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
    this.vehicleId,
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
  final String? vehicleId;

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
    String? vehicleId,
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
      vehicleId: vehicleId ?? this.vehicleId,
    );
  }
}
