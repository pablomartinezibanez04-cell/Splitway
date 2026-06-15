import 'package:flutter_test/flutter_test.dart';
import 'package:splitway_mobile/src/services/sync/sync_planner.dart';

void main() {
  final t1 = DateTime.utc(2026, 1, 1, 10);
  final t2 = DateTime.utc(2026, 1, 1, 11); // one hour later

  group('SyncPlanner.shouldPush', () {
    test('pushes when remote is missing', () {
      expect(
        SyncPlanner.shouldPush(localUpdatedAt: t1, remoteUpdatedAt: null),
        isTrue,
      );
    });

    test('pushes when local is strictly newer than remote', () {
      expect(
        SyncPlanner.shouldPush(localUpdatedAt: t2, remoteUpdatedAt: t1),
        isTrue,
      );
    });

    test('does not push when local equals remote', () {
      expect(
        SyncPlanner.shouldPush(localUpdatedAt: t1, remoteUpdatedAt: t1),
        isFalse,
      );
    });

    test('does not push when remote is newer', () {
      expect(
        SyncPlanner.shouldPush(localUpdatedAt: t1, remoteUpdatedAt: t2),
        isFalse,
      );
    });

    test('does not push when local timestamp is unknown but remote exists', () {
      expect(
        SyncPlanner.shouldPush(localUpdatedAt: null, remoteUpdatedAt: t1),
        isFalse,
      );
    });
  });

  group('SyncPlanner.shouldPull', () {
    test('pulls when missing locally', () {
      expect(
        SyncPlanner.shouldPull(localUpdatedAt: null, remoteUpdatedAt: t1),
        isTrue,
      );
    });

    test('pulls when remote is strictly newer', () {
      expect(
        SyncPlanner.shouldPull(localUpdatedAt: t1, remoteUpdatedAt: t2),
        isTrue,
      );
    });

    test('does not pull when local is newer or equal', () {
      expect(
        SyncPlanner.shouldPull(localUpdatedAt: t2, remoteUpdatedAt: t1),
        isFalse,
      );
      expect(
        SyncPlanner.shouldPull(localUpdatedAt: t1, remoteUpdatedAt: t1),
        isFalse,
      );
    });
  });

  group('SyncPlanner.canPushSession', () {
    test('pushes when the route is present remotely', () {
      expect(
        SyncPlanner.canPushSession(
          routeId: 'r1',
          remoteRouteIds: {'r1', 'r2'},
        ),
        isTrue,
      );
    });

    test('pushes when the route was pushed earlier this cycle', () {
      // pushedRouteIds are folded into remoteRouteIds by the caller.
      expect(
        SyncPlanner.canPushSession(
          routeId: 'just-pushed',
          remoteRouteIds: {'just-pushed'},
        ),
        isTrue,
      );
    });

    test('skips when the route is absent remotely (avoids 23503)', () {
      // e.g. an official route the curator never published.
      expect(
        SyncPlanner.canPushSession(
          routeId: 'official-not-on-server',
          remoteRouteIds: {'r1'},
        ),
        isFalse,
      );
    });

    test('skips when there are no remote routes at all', () {
      expect(
        SyncPlanner.canPushSession(routeId: 'r1', remoteRouteIds: {}),
        isFalse,
      );
    });
  });

  group('SyncPlanner.shouldApplyReconciliationDeletions', () {
    test('skips deletions when remote is empty but local has items', () {
      expect(
        SyncPlanner.shouldApplyReconciliationDeletions(
          remoteCount: 0,
          localCount: 3,
        ),
        isFalse,
      );
    });

    test('applies deletions when remote has items', () {
      expect(
        SyncPlanner.shouldApplyReconciliationDeletions(
          remoteCount: 2,
          localCount: 3,
        ),
        isTrue,
      );
    });

    test('applies (no-op) when both empty', () {
      expect(
        SyncPlanner.shouldApplyReconciliationDeletions(
          remoteCount: 0,
          localCount: 0,
        ),
        isTrue,
      );
    });
  });
}
