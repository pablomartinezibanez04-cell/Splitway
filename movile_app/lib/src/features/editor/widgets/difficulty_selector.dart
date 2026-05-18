import 'package:flutter/material.dart';
import 'package:splitway_core/splitway_core.dart';
import 'package:splitway_mobile/l10n/app_localizations.dart';

class DifficultySelector extends StatelessWidget {
  const DifficultySelector({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final RouteDifficulty value;
  final ValueChanged<RouteDifficulty> onChanged;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Row(
      children: [
        _buildOption(
          context: context,
          difficulty: RouteDifficulty.easy,
          label: l.editorDifficultyEasy,
          icon: Icons.park_rounded,
          color: Colors.green,
        ),
        const SizedBox(width: 10),
        _buildOption(
          context: context,
          difficulty: RouteDifficulty.medium,
          label: l.editorDifficultyMedium,
          icon: Icons.terrain_rounded,
          color: Colors.orange,
        ),
        const SizedBox(width: 10),
        _buildOption(
          context: context,
          difficulty: RouteDifficulty.hard,
          label: l.editorDifficultyHard,
          icon: Icons.whatshot_rounded,
          color: Colors.red,
        ),
      ],
    );
  }

  Widget _buildOption({
    required BuildContext context,
    required RouteDifficulty difficulty,
    required String label,
    required IconData icon,
    required Color color,
  }) {
    final selected = value == difficulty;
    final cs = Theme.of(context).colorScheme;
    return Expanded(
      child: GestureDetector(
        onTap: () => onChanged(difficulty),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: selected
                ? color.withValues(alpha: 0.12)
                : cs.surfaceContainerHighest.withValues(alpha: 0.4),
            border: Border.all(
              color: selected ? color : cs.outline.withValues(alpha: 0.2),
              width: selected ? 2 : 1,
            ),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            children: [
              Icon(icon,
                  color: selected ? color : cs.onSurfaceVariant, size: 28),
              const SizedBox(height: 6),
              Text(
                label,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: selected ? color : cs.onSurfaceVariant,
                      fontWeight:
                          selected ? FontWeight.bold : FontWeight.w500,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
