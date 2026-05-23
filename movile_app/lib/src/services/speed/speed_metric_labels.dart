import 'package:splitway_mobile/l10n/app_localizations.dart';

import 'speed_metric.dart';

extension SpeedMetricCategoryLabel on SpeedMetricCategory {
  String label(AppLocalizations l) => switch (this) {
        SpeedMetricCategory.drag => l.speedCategoryDrag,
        SpeedMetricCategory.stopwatch => l.speedCategoryStopwatch,
        SpeedMetricCategory.other => l.speedCategoryOther,
      };
}

extension SpeedMetricLabel on SpeedMetric {
  String label(AppLocalizations l) {
    switch (this) {
      case SpeedMetric.reactionTime:
        return l.speedMetricReactionTime;
      case SpeedMetric.sixtyFoot:
        return l.speedMetricSixtyFoot;
      case SpeedMetric.eighthMile:
        return l.speedMetricEighthMile;
      case SpeedMetric.quarterMile:
        return l.speedMetricQuarterMile;
      case SpeedMetric.zeroTo50:
        return l.speedMetricZeroTo50;
      case SpeedMetric.zeroTo100:
        return l.speedMetricZeroTo100;
      case SpeedMetric.zeroTo200:
        return l.speedMetricZeroTo200;
      case SpeedMetric.topSpeed:
        return l.speedMetricTopSpeed;
    }
  }
}
