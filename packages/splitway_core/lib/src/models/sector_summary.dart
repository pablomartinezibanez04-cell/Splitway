/// Stable identifier for the implicit final sector — the segment that runs from
/// the last sector gate to the start/finish line (closed routes) or the last
/// path point (open routes). N sector gates yield N+1 sectors; this id keys the
/// extra one. It never collides with editor-generated ids (`'<routeId>-sec-N'`).
const String kFinalSectorId = '__final__';

class SectorSummary {
  const SectorSummary({
    required this.sectorId,
    required this.lapNumber,
    required this.duration,
    required this.startedAt,
    required this.endedAt,
    required this.distanceMeters,
    required this.avgSpeedMps,
  });

  final String sectorId;
  final int lapNumber;
  final Duration duration;
  final DateTime startedAt;
  final DateTime endedAt;
  final double distanceMeters;
  final double avgSpeedMps;

  Map<String, dynamic> toJson() => {
        'sectorId': sectorId,
        'lapNumber': lapNumber,
        'durationMs': duration.inMilliseconds,
        'startedAt': startedAt.toUtc().toIso8601String(),
        'endedAt': endedAt.toUtc().toIso8601String(),
        'distanceMeters': distanceMeters,
        'avgSpeedMps': avgSpeedMps,
      };

  factory SectorSummary.fromJson(Map<String, dynamic> json) => SectorSummary(
        sectorId: json['sectorId'] as String,
        lapNumber: json['lapNumber'] as int,
        duration: Duration(milliseconds: json['durationMs'] as int),
        startedAt: DateTime.parse(json['startedAt'] as String),
        endedAt: DateTime.parse(json['endedAt'] as String),
        distanceMeters: (json['distanceMeters'] as num).toDouble(),
        avgSpeedMps: (json['avgSpeedMps'] as num).toDouble(),
      );
}
