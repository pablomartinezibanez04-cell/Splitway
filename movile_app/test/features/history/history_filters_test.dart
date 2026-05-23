import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:splitway_mobile/src/features/history/history_filters.dart';

void main() {
  group('HistoryFilters', () {
    test('default constructor is empty', () {
      const f = HistoryFilters();
      expect(f.isEmpty, isTrue);
      expect(f.activeCount, 0);
    });

    test('activeCount counts non-empty filter groups (excludes query)', () {
      const f = HistoryFilters(
        query: 'foo',
        kinds: {HistoryEntryKind.session},
        vehicleIds: {'v1'},
      );
      // query is excluded; kinds + vehicleIds = 2
      expect(f.activeCount, 2);
      expect(f.isEmpty, isFalse);
    });

    test('clear() resets every field', () {
      final f = HistoryFilters(
        query: 'foo',
        kinds: const {HistoryEntryKind.freeRide},
        vehicleIds: const {'v1'},
        dateRange: DateTimeRange(
          start: DateTime(2026, 1, 1),
          end: DateTime(2026, 2, 1),
        ),
        minDistanceMeters: 1000,
      );
      expect(f.clear().isEmpty, isTrue);
    });

    test('copyWith preserves other fields and can explicitly clear nullables',
        () {
      final f = HistoryFilters(
        query: 'monza',
        dateRange: DateTimeRange(
          start: DateTime(2026, 1, 1),
          end: DateTime(2026, 2, 1),
        ),
        minDistanceMeters: 5000,
      );
      final next = f.copyWith(dateRange: null, query: 'mugello');
      expect(next.query, 'mugello');             // overridden
      expect(next.minDistanceMeters, 5000);      // preserved
      expect(next.dateRange, isNull);            // explicitly cleared
    });
  });

  group('foldForSearch', () {
    test('lowercases and strips common Latin diacritics', () {
      expect(foldForSearch('JARAMA'), 'jarama');
      expect(foldForSearch('Móntmelo'), 'montmelo');
      expect(foldForSearch('Niño'), 'nino');
      expect(foldForSearch('Català'), 'catala');
    });
  });

  group('matchesHistoryFilters', () {
    HistoryEntryFields make({
      HistoryEntryKind kind = HistoryEntryKind.session,
      String name = 'Test ride',
      String? vehicleId,
      DateTime? date,
      double totalDistanceMeters = 5000,
    }) {
      return HistoryEntryFields(
        kind: kind,
        displayName: name,
        vehicleId: vehicleId,
        date: date ?? DateTime(2026, 5, 15, 12),
        totalDistanceMeters: totalDistanceMeters,
      );
    }

    test('empty filters pass everything', () {
      expect(matchesHistoryFilters(const HistoryFilters(), make()), isTrue);
    });

    test('query is case- and accent-insensitive substring', () {
      final e = make(name: 'Montmeló circuit');
      expect(
          matchesHistoryFilters(const HistoryFilters(query: 'montmelo'), e),
          isTrue);
      expect(matchesHistoryFilters(const HistoryFilters(query: 'XYZ'), e),
          isFalse);
    });

    test('kind filter restricts to selected kinds', () {
      final session = make(kind: HistoryEntryKind.session);
      final ride = make(kind: HistoryEntryKind.freeRide);
      const f = HistoryFilters(kinds: {HistoryEntryKind.freeRide});
      expect(matchesHistoryFilters(f, session), isFalse);
      expect(matchesHistoryFilters(f, ride), isTrue);
    });

    test('vehicle filter matches selected ids and the null bucket', () {
      const f = HistoryFilters(vehicleIds: {'v1', null});
      expect(matchesHistoryFilters(f, make(vehicleId: 'v1')), isTrue);
      expect(matchesHistoryFilters(f, make(vehicleId: null)), isTrue);
      expect(matchesHistoryFilters(f, make(vehicleId: 'v2')), isFalse);
    });

    test('date range is inclusive with end normalised to end-of-day', () {
      final f = HistoryFilters(
        dateRange: DateTimeRange(
          start: DateTime(2026, 5, 1),
          end: DateTime(2026, 5, 31),
        ),
      );
      expect(matchesHistoryFilters(f, make(date: DateTime(2026, 5, 1))),
          isTrue);
      // Entry late on the end day should still pass
      expect(
          matchesHistoryFilters(
              f, make(date: DateTime(2026, 5, 31, 23, 30))),
          isTrue);
      expect(matchesHistoryFilters(f, make(date: DateTime(2026, 6, 1))),
          isFalse);
    });

    test('minDistanceMeters is a lower bound (inclusive)', () {
      const f = HistoryFilters(minDistanceMeters: 5000);
      expect(matchesHistoryFilters(f, make(totalDistanceMeters: 4999)),
          isFalse);
      expect(matchesHistoryFilters(f, make(totalDistanceMeters: 5000)),
          isTrue);
    });

    test('all groups AND together', () {
      const f = HistoryFilters(
        query: 'monza',
        kinds: {HistoryEntryKind.session},
        vehicleIds: {'v1'},
        minDistanceMeters: 4000,
      );
      expect(
        matchesHistoryFilters(
            f,
            make(
              name: 'Monza GP',
              vehicleId: 'v1',
              totalDistanceMeters: 5000,
            )),
        isTrue,
      );
      // Wrong vehicle:
      expect(
        matchesHistoryFilters(
            f,
            make(
              name: 'Monza GP',
              vehicleId: 'v2',
              totalDistanceMeters: 5000,
            )),
        isFalse,
      );
      // Distance below threshold:
      expect(
        matchesHistoryFilters(
            f,
            make(
              name: 'Monza GP',
              vehicleId: 'v1',
              totalDistanceMeters: 1000,
            )),
        isFalse,
      );
    });
  });

  group('matchesSpeedFilters', () {
    SpeedSessionFields make({
      String name = 'Speed run',
      String? vehicleId,
      DateTime? date,
    }) {
      return SpeedSessionFields(
        displayName: name,
        vehicleId: vehicleId,
        date: date ?? DateTime(2026, 5, 15, 10),
      );
    }

    test('empty filters pass everything', () {
      expect(matchesSpeedFilters(const HistoryFilters(), make()), isTrue);
    });

    test('query matches the speed session name', () {
      expect(
          matchesSpeedFilters(
              const HistoryFilters(query: 'speed'), make(name: 'Speed run')),
          isTrue);
      expect(
          matchesSpeedFilters(
              const HistoryFilters(query: 'xyz'), make()),
          isFalse);
    });

    test('vehicle filter applies (including null bucket)', () {
      const f = HistoryFilters(vehicleIds: {null});
      expect(matchesSpeedFilters(f, make(vehicleId: null)), isTrue);
      expect(matchesSpeedFilters(f, make(vehicleId: 'v1')), isFalse);
    });

    test('kind filter is IGNORED for speed sessions', () {
      // Speed sessions appear only in the Velocidad tab; the kind filter
      // (session/freeRide) is irrelevant and must not exclude them.
      const f = HistoryFilters(kinds: {HistoryEntryKind.session});
      expect(matchesSpeedFilters(f, make()), isTrue);
    });

    test('minDistanceMeters is IGNORED for speed sessions', () {
      const f = HistoryFilters(minDistanceMeters: 10000);
      expect(matchesSpeedFilters(f, make()), isTrue);
    });
  });
}
