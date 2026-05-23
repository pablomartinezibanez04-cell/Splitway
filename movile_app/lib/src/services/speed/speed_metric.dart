enum SpeedMetricCategory {
  drag,
  stopwatch,
  other;

  List<SpeedMetric> get metrics => SpeedMetric.values
      .where((m) => m.category == this)
      .toList();
}

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

  SpeedMetricCategory get category => switch (this) {
        SpeedMetric.sixtyFoot => SpeedMetricCategory.drag,
        SpeedMetric.eighthMile => SpeedMetricCategory.drag,
        SpeedMetric.quarterMile => SpeedMetricCategory.drag,
        SpeedMetric.zeroTo50 => SpeedMetricCategory.stopwatch,
        SpeedMetric.zeroTo100 => SpeedMetricCategory.stopwatch,
        SpeedMetric.zeroTo200 => SpeedMetricCategory.stopwatch,
        SpeedMetric.reactionTime => SpeedMetricCategory.other,
        SpeedMetric.topSpeed => SpeedMetricCategory.other,
      };

  String formatValue(double? value) {
    if (value == null) return '-';
    if (this == SpeedMetric.topSpeed) {
      return '${value.round()} km/h';
    }
    return '${value.toStringAsFixed(2)} s';
  }
}
