import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:splitway_core/splitway_core.dart';
import 'package:splitway_mobile/l10n/app_localizations.dart';

import '../../data/repositories/local_draft_repository.dart';
import '../../data/repositories/speed_repository.dart';
import '../../services/auth/auth_service.dart';
import '../../services/garage/garage_service.dart';
import '../../services/garage/vehicle.dart';
import '../../services/settings/app_settings_controller.dart';
import '../../services/speed/speed_metric.dart';
import '../../services/speed/speed_session.dart';
import '../../shared/formatters.dart';
import '../../shared/widgets/empty_state.dart';

class StatsScreen extends StatefulWidget {
  const StatsScreen({
    super.key,
    required this.repository,
    required this.settingsController,
    this.speedRepository,
    this.garageService,
    this.authService,
  });

  final LocalDraftRepository repository;
  final AppSettingsController settingsController;
  final SpeedRepository? speedRepository;
  final GarageService? garageService;
  final AuthService? authService;

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  bool _loading = true;
  List<SessionRun> _sessions = const [];
  List<FreeRideRun> _freeRides = const [];
  List<SpeedSession> _speedSessions = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _loading = true);

    final sessions = await widget.repository.getAllSessions();
    final freeRides = await widget.repository.getAllFreeRides();

    List<SpeedSession> speed = const [];
    final userId = widget.authService?.currentUser?.id;
    final speedRepo = widget.speedRepository;
    if (userId != null && speedRepo != null) {
      speed = await speedRepo.listForUser(userId);
    }

    if (!mounted) return;
    setState(() {
      _sessions = sessions;
      _freeRides = freeRides;
      _speedSessions = speed;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(l.statsTitle),
        leading: IconButton(
          icon: const BackButtonIcon(),
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/routes');
            }
          },
        ),
        actions: [
          IconButton(
            tooltip: l.commonRefresh,
            onPressed: _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: widget.settingsController,
        builder: (context, _) {
          if (_loading) {
            return const Center(child: CircularProgressIndicator());
          }

          final hasAnyData = _sessions.isNotEmpty ||
              _freeRides.isNotEmpty ||
              _speedSessions.isNotEmpty;

          if (!hasAnyData) {
            return EmptyState(
              icon: Icons.bar_chart_outlined,
              title: l.statsEmptyTitle,
              message: l.statsEmptyMessage,
            );
          }

          return RefreshIndicator(
            onRefresh: _load,
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                _OverviewSection(
                  sessions: _sessions,
                  freeRides: _freeRides,
                  speedSessions: _speedSessions,
                  vehicleCount: widget.garageService?.vehicles.length ?? 0,
                  unit: widget.settingsController.unitSystem,
                ),
                _PersonalBestsSection(
                  speedSessions: _speedSessions,
                  vehicles: widget.garageService?.vehicles ?? const [],
                ),
                _RecordsSection(
                  sessions: _sessions,
                  freeRides: _freeRides,
                  speedSessions: _speedSessions,
                  unit: widget.settingsController.unitSystem,
                ),
                _ActivityChartSection(
                  sessions: _sessions,
                  freeRides: _freeRides,
                  speedSessions: _speedSessions,
                ),
                if (widget.garageService != null &&
                    widget.garageService!.vehicles.isNotEmpty)
                  _VehicleBreakdownSection(
                    vehicles: widget.garageService!.vehicles,
                    sessions: _sessions,
                    freeRides: _freeRides,
                    speedSessions: _speedSessions,
                    unit: widget.settingsController.unitSystem,
                  ),
                const SizedBox(height: 24),
              ],
            ),
          );
        },
      ),
    );
  }
}

// =============================================================================
// Overview: total activities, total distance, total time, vehicles
// =============================================================================

class _OverviewSection extends StatelessWidget {
  const _OverviewSection({
    required this.sessions,
    required this.freeRides,
    required this.speedSessions,
    required this.vehicleCount,
    required this.unit,
  });

  final List<SessionRun> sessions;
  final List<FreeRideRun> freeRides;
  final List<SpeedSession> speedSessions;
  final int vehicleCount;
  final UnitSystem unit;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);

    final totalActivities =
        sessions.length + freeRides.length + speedSessions.length;

    var totalMeters = 0.0;
    for (final s in sessions) {
      totalMeters += s.totalDistanceMeters;
    }
    for (final r in freeRides) {
      totalMeters += r.totalDistanceMeters;
    }

    Duration totalTime = Duration.zero;
    for (final s in sessions) {
      final d = s.totalDuration;
      if (d != null) totalTime += d;
    }
    for (final r in freeRides) {
      final d = r.totalDuration;
      if (d != null) totalTime += d;
    }

    return _Section(
      title: l.statsOverviewSection,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: _StatCard(
                    icon: Icons.directions_run_outlined,
                    label: l.statsTotalSessions,
                    value: totalActivities.toString(),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _StatCard(
                    icon: Icons.straighten,
                    label: l.statsTotalDistance,
                    value: _formatDistance(totalMeters, unit),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _StatCard(
                    icon: Icons.timer_outlined,
                    label: l.statsTotalTime,
                    value: _formatDurationLong(totalTime),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _StatCard(
                    icon: Icons.directions_car_outlined,
                    label: l.statsVehiclesOwned,
                    value: vehicleCount.toString(),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// Personal bests: best result per SpeedMetric across all speed sessions
// =============================================================================

class _PersonalBestsSection extends StatelessWidget {
  const _PersonalBestsSection({
    required this.speedSessions,
    required this.vehicles,
  });

  final List<SpeedSession> speedSessions;
  final List<Vehicle> vehicles;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);

    // Track best value + vehicleId of the speed session that achieved it.
    final bests = <SpeedMetric, ({double value, String? vehicleId})>{};
    for (final s in speedSessions) {
      for (final entry in s.results.entries) {
        final v = entry.value;
        if (v == null) continue;
        final current = bests[entry.key];
        final isBetter = entry.key.isTimeBased
            ? (current == null || v < current.value) // lower is better
            : (current == null || v > current.value); // higher is better
        if (isBetter) {
          bests[entry.key] = (value: v, vehicleId: s.vehicleId);
        }
      }
    }

    final vehiclesById = {for (final v in vehicles) v.id: v};

    return _Section(
      title: l.statsPersonalBestsSection,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Column(
          children: [
            for (final metric in SpeedMetric.values)
              _MetricRow(
                label: _metricLabel(l, metric),
                value: bests.containsKey(metric)
                    ? metric.formatValue(bests[metric]!.value)
                    : l.statsNoBestYet,
                subtitle: _vehicleSubtitle(
                  l: l,
                  vehicleId: bests[metric]?.vehicleId,
                  vehicle: bests[metric]?.vehicleId == null
                      ? null
                      : vehiclesById[bests[metric]!.vehicleId],
                  hasBest: bests.containsKey(metric),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// Records: top speed (across everything) + longest ride/session
// =============================================================================

class _RecordsSection extends StatelessWidget {
  const _RecordsSection({
    required this.sessions,
    required this.freeRides,
    required this.speedSessions,
    required this.unit,
  });

  final List<SessionRun> sessions;
  final List<FreeRideRun> freeRides;
  final List<SpeedSession> speedSessions;
  final UnitSystem unit;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);

    // Top speed: from m/s telemetry of sessions/free rides, plus topSpeed metric
    // from speed sessions (km/h → convert to m/s for comparison).
    double topMps = 0;
    for (final s in sessions) {
      if (s.maxSpeedMps > topMps) topMps = s.maxSpeedMps;
    }
    for (final r in freeRides) {
      if (r.maxSpeedMps > topMps) topMps = r.maxSpeedMps;
    }
    for (final s in speedSessions) {
      final v = s.results[SpeedMetric.topSpeed];
      if (v == null) continue;
      final mps = v / 3.6;
      if (mps > topMps) topMps = mps;
    }

    // Longest ride (free ride) and longest session (route) — by distance
    double longestRideM = 0;
    for (final r in freeRides) {
      if (r.totalDistanceMeters > longestRideM) {
        longestRideM = r.totalDistanceMeters;
      }
    }
    double longestSessionM = 0;
    for (final s in sessions) {
      if (s.totalDistanceMeters > longestSessionM) {
        longestSessionM = s.totalDistanceMeters;
      }
    }

    final unitLabel = unit == UnitSystem.imperial ? 'mph' : 'km/h';

    return _Section(
      title: l.statsRecordsSection,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Column(
          children: [
            _MetricRow(
              label: l.statsTopSpeedRecord,
              value: topMps > 0
                  ? '${Formatters.speedMps(topMps, unit: unit)} $unitLabel'
                  : l.statsNoBestYet,
            ),
            _MetricRow(
              label: l.statsLongestRide,
              value: longestRideM > 0
                  ? _formatDistance(longestRideM, unit)
                  : l.statsNoBestYet,
            ),
            _MetricRow(
              label: l.statsLongestSession,
              value: longestSessionM > 0
                  ? _formatDistance(longestSessionM, unit)
                  : l.statsNoBestYet,
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// Activity chart: weekly bar chart over the last 8 weeks
// =============================================================================

class _ActivityChartSection extends StatelessWidget {
  const _ActivityChartSection({
    required this.sessions,
    required this.freeRides,
    required this.speedSessions,
  });

  final List<SessionRun> sessions;
  final List<FreeRideRun> freeRides;
  final List<SpeedSession> speedSessions;

  static const _weeksCount = 8;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);

    // Build a bucket per week, ending today. Buckets are oriented oldest → newest.
    final now = DateTime.now();
    final endOfToday = DateTime(now.year, now.month, now.day, 23, 59, 59);
    final counts = List<int>.filled(_weeksCount, 0);

    void bucketize(DateTime when) {
      final daysAgo = endOfToday.difference(when).inDays;
      if (daysAgo < 0) return;
      final weekIndexFromEnd = daysAgo ~/ 7;
      if (weekIndexFromEnd >= _weeksCount) return;
      // counts[_weeksCount - 1] is the most recent week
      counts[_weeksCount - 1 - weekIndexFromEnd]++;
    }

    for (final s in sessions) {
      bucketize(s.startedAt);
    }
    for (final r in freeRides) {
      bucketize(r.startedAt);
    }
    for (final s in speedSessions) {
      bucketize(s.startedAt);
    }

    final maxCount = counts.fold<int>(0, (m, v) => v > m ? v : m);

    // Compute the start date of each week bucket. Today is the last day of the
    // most recent bucket, so the start of that bucket is today - 6 days; each
    // older bucket starts 7 more days back.
    final today = DateTime(now.year, now.month, now.day);
    final weekStarts = <DateTime>[
      for (var i = 0; i < _weeksCount; i++)
        today.subtract(Duration(days: 6 + (_weeksCount - 1 - i) * 7)),
    ];
    final labelFmt = DateFormat.Md(l.localeName);

    return _Section(
      title: l.statsActivitySection,
      subtitle: l.statsActivityWeekly,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
        child: SizedBox(
          height: 140,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var i = 0; i < counts.length; i++) ...[
                Expanded(
                  child: _BarColumn(
                    count: counts[i],
                    maxCount: maxCount == 0 ? 1 : maxCount,
                    weekLabel: labelFmt.format(weekStarts[i]),
                  ),
                ),
                if (i < counts.length - 1) const SizedBox(width: 6),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _BarColumn extends StatelessWidget {
  const _BarColumn({
    required this.count,
    required this.maxCount,
    required this.weekLabel,
  });

  final int count;
  final int maxCount;

  /// Short label shown under the bar (start date of the week, e.g. "5/27").
  final String weekLabel;

  @override
  Widget build(BuildContext context) {
    final ratio = maxCount == 0 ? 0.0 : count / maxCount;
    final theme = Theme.of(context);
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Text(
          count > 0 ? count.toString() : '',
          style: theme.textTheme.labelSmall
              ?.copyWith(color: theme.colorScheme.outline),
        ),
        const SizedBox(height: 2),
        Container(
          height: 80 * ratio + (count > 0 ? 4 : 1),
          decoration: BoxDecoration(
            color: count > 0
                ? theme.colorScheme.primary
                : theme.colorScheme.outlineVariant,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            weekLabel,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.outline,
              fontSize: 10,
            ),
          ),
        ),
      ],
    );
  }
}

// =============================================================================
// Per-vehicle breakdown
// =============================================================================

class _VehicleBreakdownSection extends StatefulWidget {
  const _VehicleBreakdownSection({
    required this.vehicles,
    required this.sessions,
    required this.freeRides,
    required this.speedSessions,
    required this.unit,
  });

  final List<Vehicle> vehicles;
  final List<SessionRun> sessions;
  final List<FreeRideRun> freeRides;
  final List<SpeedSession> speedSessions;
  final UnitSystem unit;

  @override
  State<_VehicleBreakdownSection> createState() =>
      _VehicleBreakdownSectionState();
}

class _VehicleBreakdownSectionState extends State<_VehicleBreakdownSection> {
  SpeedMetric _selectedMetric = SpeedMetric.quarterMile;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);

    // Count activities per vehicle (independent of selected metric).
    final activityCount = <String, int>{};
    void inc(String? id) {
      if (id == null) return;
      activityCount[id] = (activityCount[id] ?? 0) + 1;
    }

    for (final s in widget.sessions) {
      inc(s.vehicleId);
    }
    for (final r in widget.freeRides) {
      inc(r.vehicleId);
    }
    for (final s in widget.speedSessions) {
      inc(s.vehicleId);
    }

    // Best value of the selected metric per vehicle.
    // Time-based metrics: best = lowest. Top speed: best = highest.
    final bestPerVehicle = <String, double>{};
    for (final s in widget.speedSessions) {
      final id = s.vehicleId;
      if (id == null) continue;
      final v = s.results[_selectedMetric];
      if (v == null) continue;
      final current = bestPerVehicle[id];
      final isBetter = _selectedMetric.isTimeBased
          ? (current == null || v < current)
          : (current == null || v > current);
      if (isBetter) bestPerVehicle[id] = v;
    }

    // Sort vehicles by activity count desc.
    final sorted = [...widget.vehicles]..sort((a, b) {
        final ca = activityCount[a.id] ?? 0;
        final cb = activityCount[b.id] ?? 0;
        return cb.compareTo(ca);
      });

    final theme = Theme.of(context);

    return _Section(
      title: l.statsByVehicleSection,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Metric selector row.
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Row(
              children: [
                Text(
                  l.statsMetricSelectorLabel,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.outline),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest
                          .withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<SpeedMetric>(
                        value: _selectedMetric,
                        isExpanded: true,
                        isDense: true,
                        style: theme.textTheme.bodyMedium,
                        items: [
                          for (final m in SpeedMetric.values)
                            DropdownMenuItem<SpeedMetric>(
                              value: m,
                              child: Text(_metricLabel(l, m)),
                            ),
                        ],
                        onChanged: (m) {
                          if (m != null) setState(() => _selectedMetric = m);
                        },
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Column(
              children: [
                for (final v in sorted)
                  _VehicleRow(
                    vehicle: v,
                    activities: activityCount[v.id] ?? 0,
                    metric: _selectedMetric,
                    bestValue: bestPerVehicle[v.id],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _VehicleRow extends StatelessWidget {
  const _VehicleRow({
    required this.vehicle,
    required this.activities,
    required this.metric,
    required this.bestValue,
  });

  final Vehicle vehicle;
  final int activities;
  final SpeedMetric metric;
  final double? bestValue;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final best = bestValue;

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(_iconForVehicle(vehicle.type),
              size: 20, color: theme.colorScheme.outline),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  vehicle.name,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  l.statsActivitiesCount(activities),
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.outline),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                _metricLabel(l, metric),
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: theme.colorScheme.outline),
              ),
              Text(
                best != null
                    ? metric.formatValue(best)
                    : l.statsNoSpeedSessionsForVehicle,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: best != null
                      ? theme.colorScheme.primary
                      : theme.colorScheme.outline,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

IconData _iconForVehicle(VehicleType type) {
  switch (type) {
    case VehicleType.car:
      return Icons.directions_car_outlined;
    case VehicleType.motorcycle:
      return Icons.two_wheeler_outlined;
    case VehicleType.bicycle:
      return Icons.pedal_bike_outlined;
    case VehicleType.goKart:
      return Icons.sports_motorsports_outlined;
    case VehicleType.other:
      return Icons.commute_outlined;
  }
}

// =============================================================================
// Shared widgets / helpers
// =============================================================================

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.child,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title.toUpperCase(),
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.primary,
                  letterSpacing: 0.8,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (subtitle != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    subtitle!,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.outline),
                  ),
                ),
            ],
          ),
        ),
        child,
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: theme.colorScheme.primary),
          const SizedBox(height: 8),
          Text(
            value,
            style: theme.textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.outline),
          ),
        ],
      ),
    );
  }
}

class _MetricRow extends StatelessWidget {
  const _MetricRow({
    required this.label,
    required this.value,
    this.subtitle,
  });

  final String label;
  final String value;

  /// Optional small caption shown below the label (e.g., vehicle name).
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.bodyMedium,
                ),
                if (subtitle != null && subtitle!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Row(
                      children: [
                        Icon(Icons.directions_car_outlined,
                            size: 12,
                            color: theme.colorScheme.outline),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            subtitle!,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.outline,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          Text(
            value,
            style: theme.textTheme.bodyMedium
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

/// Returns the subtitle to display under a personal-best row:
/// - The vehicle name when the session had a vehicle and we still know it.
/// - A localized "unknown vehicle" string when the session had a vehicleId but
///   the vehicle is no longer in the garage.
/// - `null` (no subtitle) when there's no best yet or the session had no
///   associated vehicle.
String? _vehicleSubtitle({
  required AppLocalizations l,
  required String? vehicleId,
  required Vehicle? vehicle,
  required bool hasBest,
}) {
  if (!hasBest) return null;
  if (vehicleId == null) return null;
  return vehicle?.name ?? l.statsUnknownVehicle;
}

String _metricLabel(AppLocalizations l, SpeedMetric m) {
  switch (m) {
    case SpeedMetric.reactionTime:
      return l.speedMetricReactionTime;
    case SpeedMetric.sixtyFoot:
      return l.speedMetricSixtyFoot;
    case SpeedMetric.eighthMile:
      return l.speedMetricEighthMile;
    case SpeedMetric.quarterMile:
      return l.speedMetricQuarterMile;
    case SpeedMetric.zeroTo50:
      return l.speedMetricZeroTo50;
    case SpeedMetric.zeroTo100:
      return l.speedMetricZeroTo100;
    case SpeedMetric.zeroTo200:
      return l.speedMetricZeroTo200;
    case SpeedMetric.topSpeed:
      return l.speedMetricTopSpeed;
  }
}

String _formatDistance(double meters, UnitSystem unit) {
  final (value, isLarge) = Formatters.distanceMeters(meters, unit: unit);
  if (unit == UnitSystem.imperial) {
    return isLarge
        ? '${value.toStringAsFixed(1)} mi'
        : '${value.round()} ft';
  }
  return isLarge ? '${value.toStringAsFixed(1)} km' : '${value.round()} m';
}

String _formatDurationLong(Duration d) {
  if (d.inSeconds == 0) return '0m';
  final hours = d.inHours;
  final minutes = d.inMinutes.remainder(60);
  if (hours == 0) return '${minutes}m';
  return '${hours}h ${minutes}m';
}
