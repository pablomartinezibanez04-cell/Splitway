import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:splitway_mobile/l10n/app_localizations.dart';

import '../../services/garage/vehicle.dart';
import '../../services/settings/app_settings_controller.dart';
import 'history_filters.dart';

// ---------------------------------------------------------------------------
// Unit-conversion helpers (internal — not exported).
// ---------------------------------------------------------------------------

double _metersToDisplay(double meters, UnitSystem unit) =>
    unit == UnitSystem.imperial ? meters / 1609.344 : meters / 1000.0;

double _displayToMeters(double display, UnitSystem unit) =>
    unit == UnitSystem.imperial ? display * 1609.344 : display * 1000.0;

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

  // Text controller for the minimum-distance field.
  late final TextEditingController _distanceCtrl;

  @override
  void initState() {
    super.initState();
    _draft = widget.initial;

    final distDisplay = _draft.minDistanceMeters == null
        ? ''
        : _metersToDisplay(_draft.minDistanceMeters!, widget.unitSystem)
            .toStringAsFixed(2);

    _distanceCtrl = TextEditingController(text: distDisplay);
  }

  @override
  void dispose() {
    _distanceCtrl.dispose();
    super.dispose();
  }

  // Parses the current text fields into the draft.
  HistoryFilters _draftWithTextFields() {
    final distText = _distanceCtrl.text.trim();
    final distVal = double.tryParse(distText);

    return _draft.copyWith(
      minDistanceMeters: distVal == null
          ? null
          : _displayToMeters(distVal, widget.unitSystem),
    );
  }

  void _resetDraft() {
    setState(() {
      // Preserve the live query so it isn't wiped by Clear.
      _draft = HistoryFilters(query: widget.initial.query);
      _distanceCtrl.clear();
    });
  }

  void _applyPresetRange(DateTimeRange range) {
    setState(() => _draft = _draft.copyWith(dateRange: range));
  }

  // Builds the date-range summary text.
  String _dateRangeText(AppLocalizations l) {
    final range = _draft.dateRange;
    if (range == null) return '—';
    final fmt = DateFormat.yMd(l.localeName);
    return '${fmt.format(range.start)} – ${fmt.format(range.end)}';
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final now = DateTime.now();

    final distSuffix = widget.unitSystem == UnitSystem.imperial ? 'mi' : 'km';

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

            // ------- Vehicle filter (hidden when no vehicles) -------
            if (widget.vehicles.isNotEmpty) ...[
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
                  // "No vehicle" bucket
                  FilterChip(
                    label: Text(l.historyNoVehicle),
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
                OutlinedButton.icon(
                  icon: const Icon(Icons.calendar_today, size: 16),
                  label: Text(l.historyDateCustom),
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
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              _dateRangeText(l),
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),

            // ------- Min distance (hidden on speed tab) -------
            if (!widget.isSpeedTab) ...[
              const SizedBox(height: 16),
              Text(l.historyFilterMinDistanceLabel,
                  style: theme.textTheme.labelLarge),
              const SizedBox(height: 8),
              TextField(
                controller: _distanceCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  isDense: true,
                  border: const OutlineInputBorder(),
                  suffixText: distSuffix,
                ),
              ),
            ],

            // ------- Footer -------
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton(
                  onPressed: _resetDraft,
                  child: Text(l.historyFiltersClear),
                ),
                FilledButton(
                  onPressed: () =>
                      Navigator.pop(context, _draftWithTextFields()),
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
