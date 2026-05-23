import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/material.dart' show DateTimeRange;

/// Which kind of timeline entry this is.
///
/// `speed` is intentionally excluded: speed sessions live in their own tab
/// and the kind filter only narrows the combined timeline.
enum HistoryEntryKind { session, freeRide }

/// Immutable bag of every active filter on the history screen.
///
/// Empty fields mean "no constraint" for that group. `query` is the free-text
/// search and is tracked separately from `activeCount` because the search
/// field has its own UI affordance (the badge on the filters button is meant
/// to count structured filters only).
class HistoryFilters {
  const HistoryFilters({
    this.query = '',
    this.kinds = const <HistoryEntryKind>{},
    this.vehicleIds = const <String?>{},
    this.dateRange,
    this.minDistanceMeters,
  });

  final String query;
  final Set<HistoryEntryKind> kinds;

  /// Selected vehicle ids. `null` is a valid member meaning "entries with no
  /// vehicle assigned" (the "Sin vehículo" bucket in the UI).
  final Set<String?> vehicleIds;

  final DateTimeRange? dateRange;
  final double? minDistanceMeters;

  bool get isEmpty =>
      query.isEmpty &&
      kinds.isEmpty &&
      vehicleIds.isEmpty &&
      dateRange == null &&
      minDistanceMeters == null;

  /// Number of structured filter groups currently active. The query is
  /// excluded — it has its own UI indicator.
  int get activeCount {
    var n = 0;
    if (kinds.isNotEmpty) n++;
    if (vehicleIds.isNotEmpty) n++;
    if (dateRange != null) n++;
    if (minDistanceMeters != null) n++;
    return n;
  }

  HistoryFilters copyWith({
    String? query,
    Set<HistoryEntryKind>? kinds,
    Set<String?>? vehicleIds,
    Object? dateRange = _sentinel,
    Object? minDistanceMeters = _sentinel,
  }) {
    return HistoryFilters(
      query: query ?? this.query,
      kinds: kinds ?? this.kinds,
      vehicleIds: vehicleIds ?? this.vehicleIds,
      dateRange: identical(dateRange, _sentinel)
          ? this.dateRange
          : dateRange as DateTimeRange?,
      minDistanceMeters: identical(minDistanceMeters, _sentinel)
          ? this.minDistanceMeters
          : minDistanceMeters as double?,
    );
  }

  HistoryFilters clear() => const HistoryFilters();
}

const _sentinel = Object();

/// Snapshot of the fields needed to evaluate a session/free-ride entry against
/// [HistoryFilters]. Letting callers pass primitives keeps this module pure
/// and trivially testable.
class HistoryEntryFields {
  const HistoryEntryFields({
    required this.kind,
    required this.displayName,
    required this.vehicleId,
    required this.date,
    required this.totalDistanceMeters,
  });

  final HistoryEntryKind kind;
  final String displayName;
  final String? vehicleId;
  final DateTime date;
  final double totalDistanceMeters;
}

/// Same idea for speed sessions, which expose a different set of fields.
class SpeedSessionFields {
  const SpeedSessionFields({
    required this.displayName,
    required this.vehicleId,
    required this.date,
  });

  final String displayName;
  final String? vehicleId;
  final DateTime date;
}

/// Case- and diacritics-insensitive fold used by the free-text search.
///
/// We don't pull in a full Unicode normaliser — a small lookup over the
/// common Latin characters used in route and vehicle names is sufficient and
/// keeps the build dependency-free.
///
/// Public only so unit tests can pin its behaviour directly; production code
/// reaches it through [matchesHistoryFilters] / [matchesSpeedFilters].
@visibleForTesting
String foldForSearch(String input) {
  const folds = {
    'á': 'a', 'à': 'a', 'ä': 'a', 'â': 'a', 'ã': 'a', 'å': 'a',
    'é': 'e', 'è': 'e', 'ë': 'e', 'ê': 'e',
    'í': 'i', 'ì': 'i', 'ï': 'i', 'î': 'i',
    'ó': 'o', 'ò': 'o', 'ö': 'o', 'ô': 'o', 'õ': 'o', 'ø': 'o',
    'ú': 'u', 'ù': 'u', 'ü': 'u', 'û': 'u',
    'ñ': 'n', 'ç': 'c',
  };
  final lower = input.toLowerCase();
  final buf = StringBuffer();
  for (final r in lower.runes) {
    final ch = String.fromCharCode(r);
    buf.write(folds[ch] ?? ch);
  }
  return buf.toString();
}

bool _matchesQuery(String query, String displayName) {
  if (query.isEmpty) return true;
  return foldForSearch(displayName).contains(foldForSearch(query));
}

bool _matchesDate(DateTimeRange? range, DateTime date) {
  if (range == null) return true;
  if (date.isBefore(range.start)) return false;
  // Normalise the end-of-day so an entry recorded at 23:30 on the last day
  // of the range is included.
  final endOfDay = DateTime(
    range.end.year,
    range.end.month,
    range.end.day,
    23,
    59,
    59,
    999,
  );
  return !date.isAfter(endOfDay);
}

bool _matchesVehicle(Set<String?> selected, String? vehicleId) {
  if (selected.isEmpty) return true;
  return selected.contains(vehicleId);
}

/// True when this session/free-ride entry passes every active filter group.
bool matchesHistoryFilters(HistoryFilters f, HistoryEntryFields e) {
  if (!_matchesQuery(f.query, e.displayName)) return false;
  if (f.kinds.isNotEmpty && !f.kinds.contains(e.kind)) return false;
  if (!_matchesVehicle(f.vehicleIds, e.vehicleId)) return false;
  if (!_matchesDate(f.dateRange, e.date)) return false;
  if (f.minDistanceMeters != null &&
      e.totalDistanceMeters < f.minDistanceMeters!) {
    return false;
  }
  return true;
}

/// True when this speed session passes every applicable filter group.
///
/// The `kinds` filter and `minDistanceMeters` are intentionally ignored:
/// they don't apply to speed sessions.
bool matchesSpeedFilters(HistoryFilters f, SpeedSessionFields s) {
  if (!_matchesQuery(f.query, s.displayName)) return false;
  if (!_matchesVehicle(f.vehicleIds, s.vehicleId)) return false;
  if (!_matchesDate(f.dateRange, s.date)) return false;
  return true;
}
