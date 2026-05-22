enum SpeedMetric {
  reactionTime,
  sixtyFoot,
  eighthMile,
  quarterMile,
  zeroTo50,
  zeroTo100,
  zeroTo200,
  topSpeed;

  String get id => name;

  static SpeedMetric? fromId(String value) {
    for (final m in SpeedMetric.values) {
      if (m.id == value) return m;
    }
    return null;
  }

  bool get isTimeBased => this != SpeedMetric.topSpeed;

  String formatValue(double? value) {
    if (value == null) return '-';
    if (this == SpeedMetric.topSpeed) {
      return '${value.round()} km/h';
    }
    return '${value.toStringAsFixed(2)} s';
  }
}
