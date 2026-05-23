import 'package:flutter/material.dart';
import 'package:splitway_mobile/l10n/app_localizations.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../services/speed/speed_metric.dart';
import '../../services/speed/speed_metric_labels.dart';
import 'speed_session_controller.dart';
import 'speed_setup_screen.dart';
import 'widgets/countdown_overlay.dart';
import 'widgets/false_start_overlay.dart';
import 'widgets/speed_category_header.dart';
import 'widgets/speed_metric_card.dart';
import 'widgets/speed_metric_tile.dart';

class SpeedSessionScreen extends StatefulWidget {
  const SpeedSessionScreen({
    super.key,
    required this.controller,
    required this.view,
    required this.onSaved,
    required this.onDiscarded,
    required this.onCancelled,
  });

  final SpeedSessionController controller;
  final SpeedView view;
  final void Function(String sessionId) onSaved;
  final VoidCallback onDiscarded;
  final VoidCallback onCancelled;

  @override
  State<SpeedSessionScreen> createState() => _SpeedSessionScreenState();
}

class _SpeedSessionScreenState extends State<SpeedSessionScreen> {
  @override
  void initState() {
    super.initState();
    WakelockPlus.enable();
    widget.controller.addListener(_onChange);
    widget.controller.begin();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChange);
    WakelockPlus.disable();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                _speedHeader(c),
                Expanded(child: _body(c)),
                if (c.phase == SpeedScreenPhase.running) _manualStopBar(c),
                if (c.phase == SpeedScreenPhase.finished) _finishBar(c),
              ],
            ),
            if (c.phase == SpeedScreenPhase.arming ||
                c.phase == SpeedScreenPhase.countdown)
              CountdownOverlay(
                value: c.countdownValue == 0 ? null : c.countdownValue,
              ),
            if (c.phase == SpeedScreenPhase.falseStart)
              FalseStartOverlay(
                onRetry: () => c.retry(),
                onCancel: widget.onCancelled,
              ),
          ],
        ),
      ),
    );
  }

  Widget _speedHeader(SpeedSessionController c) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          ValueListenableBuilder<double>(
            valueListenable: c.service.instantaneousKmh,
            builder: (_, v, __) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${v.round()}',
                  style: const TextStyle(
                    fontSize: 80,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                    height: 1,
                  ),
                ),
                const Text(
                  'km/h',
                  style: TextStyle(color: Colors.white70, fontSize: 14),
                ),
              ],
            ),
          ),
          ValueListenableBuilder<Duration>(
            valueListenable: c.service.elapsed,
            builder: (_, d, __) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _formatChrono(d),
                  style: const TextStyle(
                    fontSize: 40,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    height: 1,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'mm:ss.SSS',
                  style: TextStyle(color: Colors.white54, fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _formatChrono(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    final ms = d.inMilliseconds % 1000;
    return '${m.toString().padLeft(2, '0')}:'
        '${s.toString().padLeft(2, '0')}.'
        '${ms.toString().padLeft(3, '0')}';
  }

  Widget _body(SpeedSessionController c) {
    final l = AppLocalizations.of(context);
    return ValueListenableBuilder(
      valueListenable: c.service.results,
      builder: (_, results, __) {
        final groups = <SpeedMetricCategory, List<SpeedMetric>>{};
        for (final cat in SpeedMetricCategory.values) {
          final items = cat.metrics.where(c.metrics.contains).toList();
          if (items.isNotEmpty) groups[cat] = items;
        }
        if (widget.view == SpeedView.grid) {
          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              for (final entry in groups.entries) ...[
                SpeedCategoryHeader(label: entry.key.label(l), light: true),
                GridView.count(
                  crossAxisCount: 2,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: (MediaQuery.of(context).size.width - 36) /
                      2 /
                      96,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
                    for (final m in entry.value)
                      SpeedMetricCard(metric: m, value: results[m]),
                  ],
                ),
              ],
            ],
          );
        }
        return ListView(
          children: [
            for (final entry in groups.entries) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: SpeedCategoryHeader(
                    label: entry.key.label(l), light: true),
              ),
              for (final m in entry.value)
                SpeedMetricTile(metric: m, value: results[m]),
            ],
          ],
        );
      },
    );
  }

  Widget _manualStopBar(SpeedSessionController c) {
    final l = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.all(12),
      child: SizedBox(
        width: double.infinity,
        child: OutlinedButton(
          onPressed: () => c.manualStop(),
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.white,
            side: const BorderSide(color: Colors.white24),
          ),
          child: Text(l.speedFinishedManualStop),
        ),
      ),
    );
  }

  Widget _finishBar(SpeedSessionController c) {
    final l = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: widget.onDiscarded,
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: Colors.white24),
              ),
              child: Text(l.speedFinishedDiscard),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: FilledButton(
              onPressed: () async {
                final s = await c.saveResult();
                widget.onSaved(s.id);
              },
              child: Text(l.speedFinishedSave),
            ),
          ),
        ],
      ),
    );
  }
}
