import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:splitway_mobile/l10n/app_localizations.dart';

import '../../services/speed/speed_metric.dart';
import '../../services/speed/speed_metric_labels.dart';
import '../../services/speed/speed_session.dart';
import 'widgets/speed_category_header.dart';
import 'widgets/speed_metric_tile.dart';

class SpeedSessionDetailScreen extends StatelessWidget {
  const SpeedSessionDetailScreen({super.key, required this.session});

  final SpeedSession session;

  List<Widget> _categorySection(AppLocalizations l, SpeedMetricCategory cat) {
    final metrics =
        cat.metrics.where(session.selectedMetrics.contains).toList();
    if (metrics.isEmpty) return const [];
    return [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: SpeedCategoryHeader(label: cat.label(l), light: true),
      ),
      for (final m in metrics)
        SpeedMetricTile(metric: m, value: session.results[m]),
    ];
  }

  void _goToHistory(BuildContext context) {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/history?tab=speed');
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final top = session.results[SpeedMetric.topSpeed];
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _goToHistory(context);
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          title: Text(session.name),
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => _goToHistory(context),
          ),
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
                      style:
                          const TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                  ],
                ),
              ),
              for (final cat in SpeedMetricCategory.values)
                ..._categorySection(l, cat),
            ],
          ),
        ),
      ),
    );
  }
}
