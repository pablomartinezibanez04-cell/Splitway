import 'package:flutter/material.dart';
import 'package:splitway_mobile/l10n/app_localizations.dart';

import '../../services/garage/vehicle.dart';
import '../../services/settings/app_settings_controller.dart';
import 'history_filters.dart';

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/// Shows the filters modal bottom sheet. Returns the new [HistoryFilters] if
/// the user tapped "Apply", or `null` if they dismissed or tapped Close.
Future<HistoryFilters?> showHistoryFiltersSheet({
  required BuildContext context,
  required HistoryFilters initial,
  required List<Vehicle> vehicles,
  required bool isSpeedTab,
  required UnitSystem unitSystem,
}) {
  return showModalBottomSheet<HistoryFilters>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) => _FiltersSheetBody(
      initial: initial,
      vehicles: vehicles,
      isSpeedTab: isSpeedTab,
      unitSystem: unitSystem,
    ),
  );
}

// ---------------------------------------------------------------------------
// Private sheet body widget
// ---------------------------------------------------------------------------

class _FiltersSheetBody extends StatefulWidget {
  const _FiltersSheetBody({
    required this.initial,
    required this.vehicles,
    required this.isSpeedTab,
    required this.unitSystem,
  });

  final HistoryFilters initial;
  final List<Vehicle> vehicles;
  final bool isSpeedTab;
  final UnitSystem unitSystem;

  @override
  State<_FiltersSheetBody> createState() => _FiltersSheetBodyState();
}

class _FiltersSheetBodyState extends State<_FiltersSheetBody> {
  late HistoryFilters _draft;

  @override
  void initState() {
    super.initState();
    _draft = widget.initial;
  }

  void _applyPresetRange(DateTimeRange range) {
    setState(() => _draft = _draft.copyWith(dateRange: range));
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final now = DateTime.now();

    return SingleChildScrollView(
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: MediaQuery.viewInsetsOf(context).bottom + 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ------- Header -------
            Row(
              children: [
                Expanded(
                  child: Text(
                    l.historyFiltersTitle,
                    style: theme.textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: l.commonClose,
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),

            // ------- Group-by-route toggle (hidden on speed tab) -------
            if (!widget.isSpeedTab)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(l.historyFilterGroupByRoute),
                  value: _draft.groupByRoute,
                  onChanged: (on) {
                    setState(
                        () => _draft = _draft.copyWith(groupByRoute: on));
                  },
                ),
              ),

            // ------- Kind filter (hidden on speed tab) -------
            if (!widget.isSpeedTab) ...[
              const SizedBox(height: 16),
              Text(l.historyFilterKindLabel,
                  style: theme.textTheme.labelLarge),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  FilterChip(
                    label: Text(l.historyFilterKindSession),
                    selected:
                        _draft.kinds.contains(HistoryEntryKind.session),
                    onSelected: (on) {
                      setState(() {
                        final kinds = Set<HistoryEntryKind>.from(_draft.kinds);
                        if (on) {
                          kinds.add(HistoryEntryKind.session);
                        } else {
                          kinds.remove(HistoryEntryKind.session);
                        }
                        _draft = _draft.copyWith(kinds: kinds);
                      });
                    },
                  ),
                  FilterChip(
                    label: Text(l.historyFilterKindFreeRide),
                    selected:
                        _draft.kinds.contains(HistoryEntryKind.freeRide),
                    onSelected: (on) {
                      setState(() {
                        final kinds = Set<HistoryEntryKind>.from(_draft.kinds);
                        if (on) {
                          kinds.add(HistoryEntryKind.freeRide);
                        } else {
                          kinds.remove(HistoryEntryKind.freeRide);
                        }
                        _draft = _draft.copyWith(kinds: kinds);
                      });
                    },
                  ),
                ],
              ),
            ],

            // ------- Vehicle filter -------
            ...[
              const SizedBox(height: 16),
              Text(l.historyFilterVehicleLabel,
                  style: theme.textTheme.labelLarge),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final v in widget.vehicles)
                    FilterChip(
                      label: Text(v.name),
                      selected: _draft.vehicleIds.contains(v.id),
                      onSelected: (on) {
                        setState(() {
                          final ids =
                              Set<String?>.from(_draft.vehicleIds);
                          if (on) {
                            ids.add(v.id);
                          } else {
                            ids.remove(v.id);
                          }
                          _draft = _draft.copyWith(vehicleIds: ids);
                        });
                      },
                    ),
                  // "On foot" bucket
                  FilterChip(
                    label: Text(l.vehiclePickerOnFoot),
                    selected: _draft.vehicleIds.contains(null),
                    onSelected: (on) {
                      setState(() {
                        final ids = Set<String?>.from(_draft.vehicleIds);
                        if (on) {
                          ids.add(null);
                        } else {
                          ids.remove(null);
                        }
                        _draft = _draft.copyWith(vehicleIds: ids);
                      });
                    },
                  ),
                ],
              ),
            ],

            // ------- Date range -------
            const SizedBox(height: 16),
            Text(l.historyFilterDateRangeLabel,
                style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                OutlinedButton(
                  onPressed: () => _applyPresetRange(DateTimeRange(
                    start: now.subtract(const Duration(days: 7)),
                    end: now,
                  )),
                  child: Text(l.historyDateLast7Days),
                ),
                OutlinedButton(
                  onPressed: () => _applyPresetRange(DateTimeRange(
                    start: now.subtract(const Duration(days: 30)),
                    end: now,
                  )),
                  child: Text(l.historyDateLast30Days),
                ),
                OutlinedButton(
                  onPressed: () => _applyPresetRange(DateTimeRange(
                    start: DateTime(now.year, 1, 1),
                    end: now,
                  )),
                  child: Text(l.historyDateThisYear),
                ),
                OutlinedButton(
                  onPressed: () async {
                    final picked = await showDateRangePicker(
                      context: context,
                      firstDate: DateTime(2000),
                      lastDate: DateTime.now(),
                      initialDateRange: _draft.dateRange,
                    );
                    if (picked != null) {
                      setState(
                          () => _draft = _draft.copyWith(dateRange: picked));
                    }
                  },
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.calendar_today, size: 16),
                      const SizedBox(width: 8),
                      Text(l.historyDateCustom),
                    ],
                  ),
                ),
              ],
            ),

            // ------- Footer -------
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(
                    context,
                    HistoryFilters(query: widget.initial.query),
                  ),
                  child: Text(l.historyFiltersClear),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, _draft),
                  child: Text(l.historyFiltersApply),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
