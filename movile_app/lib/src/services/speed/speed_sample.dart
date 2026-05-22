class SpeedSample {
  const SpeedSample({
    required this.tSinceStart,
    required this.speedKmh,
    required this.distanceM,
    required this.accelMs2,
  });

  final Duration tSinceStart;
  final double speedKmh;
  final double distanceM;
  final double accelMs2;
}
