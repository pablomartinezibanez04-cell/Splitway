import 'package:flutter/material.dart';
import 'package:splitway_mobile/l10n/app_localizations.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'speed_session_controller.dart';
import 'speed_setup_screen.dart';
import 'widgets/countdown_overlay.dart';
import 'widgets/false_start_overlay.dart';
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
    return ValueListenableBuilder<double>(
      valueListenable: c.service.instantaneousKmh,
      builder: (_, v, __) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          children: [
            Text(
              '${v.round()}',
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
          ],
        ),
      ),
    );
  }

  Widget _body(SpeedSessionController c) {
    return ValueListenableBuilder(
      valueListenable: c.service.results,
      builder: (_, results, __) {
        final metrics = c.metrics.toList();
        if (widget.view == SpeedView.grid) {
          return GridView.builder(
            padding: const EdgeInsets.all(12),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisExtent: 96,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
            ),
            itemCount: metrics.length,
            itemBuilder: (_, i) {
              final m = metrics[i];
              return SpeedMetricCard(metric: m, value: results[m]);
            },
          );
        }
        return ListView.builder(
          itemCount: metrics.length,
          itemBuilder: (_, i) {
            final m = metrics[i];
            return SpeedMetricTile(metric: m, value: results[m]);
          },
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
