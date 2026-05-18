enum FreeRideTrackingStatus { idle, recording, finished }

class FreeRideSnapshot {
  const FreeRideSnapshot({
    required this.status,
    required this.elapsed,
    required this.totalDistanceMeters,
    required this.currentSpeedMps,
    required this.maxSpeedMps,
    required this.avgSpeedMps,
    required this.pointCount,
  });

  final FreeRideTrackingStatus status;
  final Duration elapsed;
  final double totalDistanceMeters;
  final double currentSpeedMps;
  final double maxSpeedMps;
  final double avgSpeedMps;
  final int pointCount;

  static const FreeRideSnapshot initial = FreeRideSnapshot(
    status: FreeRideTrackingStatus.idle,
    elapsed: Duration.zero,
    totalDistanceMeters: 0,
    currentSpeedMps: 0,
    maxSpeedMps: 0,
    avgSpeedMps: 0,
    pointCount: 0,
  );
}
