import 'package:flutter/material.dart';
import 'package:splitway_mobile/l10n/app_localizations.dart';

import '../../../services/logging/log_level.dart';

class LogFilterBar extends StatelessWidget {
  const LogFilterBar({
    super.key,
    required this.level,
    required this.tag,
    required this.onLevelChanged,
    required this.onTagChanged,
    required this.onSearchChanged,
  });

  final LogLevel level;
  final String? tag;
  final ValueChanged<LogLevel> onLevelChanged;
  final ValueChanged<String?> onTagChanged;
  final ValueChanged<String> onSearchChanged;

  static const _tags = <String>[
    'supabase',
    'mapbox',
    'auth',
    'sync',
    'flutter',
    'dart',
    'http',
    'location',
    'elevation',
    'app',
    'zone',
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Column(
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final l in LogLevel.values)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text(l.label),
                      selected: l == level,
                      onSelected: (_) => onLevelChanged(l),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                ChoiceChip(
                  label: const Text('all'),
                  selected: tag == null,
                  onSelected: (_) => onTagChanged(null),
                ),
                const SizedBox(width: 6),
                for (final t in _tags) ...[
                  ChoiceChip(
                    label: Text(t),
                    selected: tag == t,
                    onSelected: (_) => onTagChanged(t),
                  ),
                  const SizedBox(width: 6),
                ],
              ],
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: AppLocalizations.of(context).logsSearchHint,
              border: const OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: onSearchChanged,
          ),
        ],
      ),
    );
  }
}
