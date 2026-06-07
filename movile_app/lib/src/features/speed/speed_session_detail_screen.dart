import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:splitway_mobile/l10n/app_localizations.dart';

import '../../data/repositories/speed_repository.dart';
import '../../services/speed/speed_metric.dart';
import '../../services/speed/speed_metric_labels.dart';
import '../../services/speed/speed_session.dart';
import 'widgets/speed_category_header.dart';
import 'widgets/speed_metric_tile.dart';

class SpeedSessionDetailScreen extends StatefulWidget {
  const SpeedSessionDetailScreen({
    super.key,
    required this.session,
    required this.repository,
  });

  final SpeedSession session;
  final SpeedRepository repository;

  @override
  State<SpeedSessionDetailScreen> createState() =>
      _SpeedSessionDetailScreenState();
}

class _SpeedSessionDetailScreenState extends State<SpeedSessionDetailScreen> {
  late SpeedSession _session = widget.session;

  List<Widget> _categorySection(AppLocalizations l, SpeedMetricCategory cat) {
    final metrics =
        cat.metrics.where(_session.selectedMetrics.contains).toList();
    if (metrics.isEmpty) return const [];
    return [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: SpeedCategoryHeader(label: cat.label(l), light: true),
      ),
      for (final m in metrics)
        SpeedMetricTile(metric: m, value: _session.results[m]),
    ];
  }

  void _goToHistory(BuildContext context) {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/history?tab=speed');
    }
  }

  Future<void> _editName() async {
    final l = AppLocalizations.of(context);
    final controller = TextEditingController(text: _session.name);
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.speedDetailEditNameTitle),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            border: const OutlineInputBorder(),
            hintText: l.speedDetailEditNameHint,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(l.speedDetailEditNameCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: Text(l.speedDetailEditNameSave),
          ),
        ],
      ),
    );
    // Defer disposal so the dialog exit animation can finish detaching
    // the TextField from the controller before it is marked as disposed.
    WidgetsBinding.instance.addPostFrameCallback((_) => controller.dispose());
    if (!mounted) return;
    if (newName == null || newName.isEmpty || newName == _session.name) return;
    final updated = _session.copyWith(
      name: newName,
      updatedAt: DateTime.now(),
    );
    try {
      await widget.repository.save(updated);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.speedDetailEditNameError)),
      );
      return;
    }
    if (!mounted) return;
    setState(() => _session = updated);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _goToHistory(context);
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          title: Text(_session.name),
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => _goToHistory(context),
          ),
          actions: [
            IconButton(
              tooltip: l.speedDetailEditNameTooltip,
              icon: const Icon(Icons.edit),
              onPressed: _editName,
            ),
          ],
        ),
        body: SafeArea(
          child: ListView(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Center(
                  child: Text(
                    DateFormat.yMd(l.localeName)
                        .add_Hm()
                        .format(_session.startedAt),
                    style:
                        const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
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
