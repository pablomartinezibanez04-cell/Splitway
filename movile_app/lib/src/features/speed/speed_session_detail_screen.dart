import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:splitway_mobile/l10n/app_localizations.dart';

import '../../services/speed/speed_metric.dart';
import '../../services/speed/speed_session.dart';
import 'widgets/speed_metric_tile.dart';

class SpeedSessionDetailScreen extends StatelessWidget {
  const SpeedSessionDetailScreen({super.key, required this.session});

  final SpeedSession session;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final top = session.results[SpeedMetric.topSpeed];
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(session.name),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: ListView(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Column(
                children: [
                  Text(
                    top == null ? '-' : '${top.round()}',
                    style: const TextStyle(
                      fontSize: 96,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      height: 1,
                    ),
                  ),
                  const Text(
                    'km/h',
                    style: TextStyle(color: Colors.white70, fontSize: 16),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    DateFormat.yMd(l.localeName)
                        .add_Hm()
                        .format(session.startedAt),
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                ],
              ),
            ),
            for (final m in SpeedMetric.values
                .where(session.selectedMetrics.contains))
              SpeedMetricTile(metric: m, value: session.results[m]),
          ],
        ),
      ),
    );
  }
}
