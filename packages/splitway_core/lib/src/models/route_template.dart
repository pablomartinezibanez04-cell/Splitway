import 'gate_definition.dart';
import 'geo_point.dart';
import 'sector_definition.dart';

const _sentinel = Object();

enum RouteDifficulty { easy, medium, hard }

extension RouteDifficultyX on RouteDifficulty {
  String get id => name;

  static RouteDifficulty fromId(String value) {
    return RouteDifficulty.values.firstWhere(
      (d) => d.name == value,
      orElse: () => RouteDifficulty.medium,
    );
  }
}

class RouteTemplate {
  const RouteTemplate({
    required this.id,
    required this.name,
    required this.path,
    required this.startFinishGate,
    required this.sectors,
    required this.difficulty,
    required this.createdAt,
    this.description,
    this.locationLabel,
    this.thumbnailUrl,
    this.elevationRangeMeters,
    this.isOfficial = false,
    this.updatedAt,
    this.expectedDuration,
  });

  final String id;
  final String name;
  final String? description;
  final String? locationLabel;
  final String? thumbnailUrl;
  final List<GeoPoint> path;
  final GateDefinition startFinishGate;
  final List<SectorDefinition> sectors;
  final RouteDifficulty difficulty;
  final DateTime createdAt;
  final double? elevationRangeMeters;
  final bool isOfficial;
  final DateTime? updatedAt;

  /// Estimated time to complete the route once at normal driving speed,
  /// computed from Mapbox. Null when it could not be computed (offline, no
  /// token, no road match).
  final Duration? expectedDuration;

  /// True when the route is a closed circuit (first and last path points
  /// are the same, as set when the gap between them is ≤ 20 m at save time).
  bool get isClosed =>
      path.length >= 2 && path.first == path.last;

  /// Total route distance in meters, computed from the path vertices.
  double get totalDistanceMeters {
    if (path.length < 2) return 0;
    double total = 0;
    for (var i = 0; i < path.length - 1; i++) {
      total += path[i].distanceTo(path[i + 1]);
    }
    return total;
  }

  RouteTemplate copyWith({
    String? id,
    String? name,
    String? description,
    String? locationLabel,
    Object? thumbnailUrl = _sentinel,
    List<GeoPoint>? path,
    GateDefinition? startFinishGate,
    List<SectorDefinition>? sectors,
    RouteDifficulty? difficulty,
    DateTime? createdAt,
    Object? elevationRangeMeters = _sentinel,
    bool? isOfficial,
    Object? updatedAt = _sentinel,
    Object? expectedDuration = _sentinel,
  }) {
    return RouteTemplate(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      locationLabel: locationLabel ?? this.locationLabel,
      thumbnailUrl: thumbnailUrl == _sentinel
          ? this.thumbnailUrl
          : thumbnailUrl as String?,
      path: path ?? this.path,
      startFinishGate: startFinishGate ?? this.startFinishGate,
      sectors: sectors ?? this.sectors,
      difficulty: difficulty ?? this.difficulty,
      createdAt: createdAt ?? this.createdAt,
      elevationRangeMeters: elevationRangeMeters == _sentinel
          ? this.elevationRangeMeters
          : elevationRangeMeters as double?,
      isOfficial: isOfficial ?? this.isOfficial,
      updatedAt: updatedAt == _sentinel
          ? this.updatedAt
          : updatedAt as DateTime?,
      expectedDuration: expectedDuration == _sentinel
          ? this.expectedDuration
          : expectedDuration as Duration?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'locationLabel': locationLabel,
        'thumbnailUrl': thumbnailUrl,
        'path': path.map((p) => p.toJson()).toList(),
        'startFinishGate': startFinishGate.toJson(),
        'sectors': sectors.map((s) => s.toJson()).toList(),
        'difficulty': difficulty.id,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'elevationRangeMeters': elevationRangeMeters,
        'isOfficial': isOfficial,
        'updatedAt': updatedAt?.toUtc().toIso8601String(),
        'expectedDurationMs': expectedDuration?.inMilliseconds,
      };

  factory RouteTemplate.fromJson(Map<String, dynamic> json) => RouteTemplate(
        id: json['id'] as String,
        name: json['name'] as String,
        description: json['description'] as String?,
        locationLabel: json['locationLabel'] as String?,
        thumbnailUrl: json['thumbnailUrl'] as String?,
        path: (json['path'] as List<dynamic>)
            .map((e) => GeoPoint.fromJson(e as Map<String, dynamic>))
            .toList(),
        startFinishGate: GateDefinition.fromJson(
            json['startFinishGate'] as Map<String, dynamic>),
        sectors: (json['sectors'] as List<dynamic>)
            .map((e) => SectorDefinition.fromJson(e as Map<String, dynamic>))
            .toList(),
        difficulty:
            RouteDifficultyX.fromId(json['difficulty'] as String? ?? 'medium'),
        createdAt: DateTime.parse(json['createdAt'] as String),
        elevationRangeMeters:
            (json['elevationRangeMeters'] as num?)?.toDouble(),
        isOfficial: json['isOfficial'] as bool? ?? false,
        updatedAt: json['updatedAt'] == null
            ? null
            : DateTime.parse(json['updatedAt'] as String),
        expectedDuration: json['expectedDurationMs'] == null
            ? null
            : Duration(milliseconds: (json['expectedDurationMs'] as num).toInt()),
      );
}
