import 'package:flutter/material.dart';
import 'package:splitway_core/splitway_core.dart';
import 'package:splitway_mobile/l10n/app_localizations.dart';

enum GpsSignalLevel { none, low, medium, high }

/// Small floating chip that surfaces the live GPS signal quality during a
/// recording. Caller is responsible for triggering rebuilds at the desired
/// cadence so the staleness check stays current.
class GpsSignalBadge extends StatelessWidget {
  const GpsSignalBadge({
    super.key,
    required this.lastPoint,
    this.staleAfter = const Duration(seconds: 6),
  });

  final TelemetryPoint? lastPoint;
  final Duration staleAfter;

  GpsSignalLevel _level() {
    final p = lastPoint;
    if (p == null) return GpsSignalLevel.none;
    final age = DateTime.now().difference(p.timestamp);
    if (age > staleAfter) return GpsSignalLevel.none;
    final acc = p.accuracyMeters;
    if (acc == null) return GpsSignalLevel.low;
    if (acc <= 8) return GpsSignalLevel.high;
    if (acc <= 20) return GpsSignalLevel.medium;
    return GpsSignalLevel.low;
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final level = _level();
    final (color, icon, text) = switch (level) {
      GpsSignalLevel.none => (
          Colors.grey.shade400,
          Icons.signal_cellular_nodata_outlined,
          l.gpsSignalNone,
        ),
      GpsSignalLevel.low => (
          Colors.red.shade400,
          Icons.signal_cellular_alt_1_bar,
          l.gpsSignalLow,
        ),
      GpsSignalLevel.medium => (
          Colors.amber.shade600,
          Icons.signal_cellular_alt_2_bar,
          l.gpsSignalMedium,
        ),
      GpsSignalLevel.high => (
          Colors.green.shade500,
          Icons.signal_cellular_alt,
          l.gpsSignalHigh,
        ),
    };
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.85), width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 16),
            const SizedBox(width: 6),
            Text(
              '${l.gpsSignalLabel} · $text',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
