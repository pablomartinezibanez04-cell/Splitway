import 'package:flutter/material.dart';

import '../formatters.dart';

/// F1-style classification of a sector time relative to session and circuit
/// records. Drives the chip colour shown in the live session and history.
enum SectorChipTier {
  /// Sector not crossed yet in the lap being shown (no time).
  unset,

  /// Fastest time for this sector across all sessions on the route (purple).
  overall,

  /// Best time for this sector in the current session, but not the all-time
  /// record (green).
  sessionBest,

  /// Slower than the best session time for this sector (orange).
  slower,
}

/// F1 colour palette for sector chips.
const Color kSectorPurple = Color(0xFF7B1FA2);
const Color kSectorGreen = Color(0xFF43A047);
const Color kSectorOrange = Color(0xFFFB8C00);

/// Classifies [lapTime] for a sector using F1 conventions.
///
/// - [lapTime]: the sector time being evaluated, or null if the sector has not
///   been crossed yet in the lap shown.
/// - [sessionCrossings]: every recorded time for this sector in the current
///   session (should include [lapTime] when it has been crossed).
/// - [historicalRecord]: the best time for this sector across the user's
///   previous sessions on the route, or null when there is no history.
///
/// Ties (`<=`) resolve in favour of the better tier.
SectorChipTier sectorChipTier({
  required Duration? lapTime,
  required Iterable<Duration> sessionCrossings,
  required Duration? historicalRecord,
}) {
  if (lapTime == null) return SectorChipTier.unset;

  Duration? sessionBest;
  for (final d in sessionCrossings) {
    if (sessionBest == null || d < sessionBest) sessionBest = d;
  }
  sessionBest ??= lapTime;

  final overallBest = historicalRecord == null
      ? sessionBest
      : (historicalRecord < sessionBest ? historicalRecord : sessionBest);

  if (lapTime <= overallBest) return SectorChipTier.overall;
  if (lapTime <= sessionBest) return SectorChipTier.sessionBest;
  return SectorChipTier.slower;
}

/// A single sector indicator pill. Shows the sector number, coloured by
/// [tier]; when [time] is provided (history view) the time is shown above the
/// number. In the live view [time] is omitted and only the colour + number
/// are shown.
class SectorChip extends StatelessWidget {
  const SectorChip({
    super.key,
    required this.sectorNumber,
    required this.tier,
    this.time,
    this.dotSeparator = true,
  });

  final int sectorNumber;
  final SectorChipTier tier;
  final Duration? time;
  final bool dotSeparator;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isUnset = tier == SectorChipTier.unset;
    final bg = switch (tier) {
      SectorChipTier.unset => theme.colorScheme.surfaceContainerHighest,
      SectorChipTier.overall => kSectorPurple,
      SectorChipTier.sessionBest => kSectorGreen,
      SectorChipTier.slower => kSectorOrange,
    };
    final fg = isUnset ? theme.colorScheme.onSurfaceVariant : Colors.white;
    final label = 'S$sectorNumber';

    return Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: theme.textTheme.labelLarge
                ?.copyWith(color: fg, fontWeight: FontWeight.w600),
          ),
          if (time != null) ...[
            const SizedBox(height: 2),
            Text(
              Formatters.duration(time!, dotSeparator: dotSeparator),
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: fg, fontWeight: FontWeight.bold),
            ),
          ],
        ],
      ),
    );
  }
}
