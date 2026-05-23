import 'package:flutter/material.dart';
import 'package:splitway_mobile/l10n/app_localizations.dart';

import '../../../services/speed/speed_metric.dart';
import '../../../services/speed/speed_metric_labels.dart';

class SpeedMetricCard extends StatelessWidget {
  const SpeedMetricCard({
    super.key,
    required this.metric,
    required this.value,
  });

  final SpeedMetric metric;
  final double? value;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            metric.label(l),
            style: const TextStyle(
              fontSize: 12,
              color: Colors.white70,
            ),
          ),
          const Spacer(),
          Text(
            metric.formatValue(value),
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}
