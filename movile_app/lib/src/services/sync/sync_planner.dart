/// Pure decision helpers for [SyncService]'s last-write-wins strategy.
///
/// Extracted as side-effect-free functions so the push/pull/reconcile
/// decisions can be unit-tested without a live Supabase or local database.
class SyncPlanner {
  const SyncPlanner._();

  /// Whether a local item should be pushed to the remote.
  ///
  /// Push when the remote copy is missing, or the local copy is strictly
  /// newer than the remote. When the local timestamp is unknown we cannot
  /// prove the local copy is newer, so we do not push (avoids clobbering a
  /// remote edit with a stale local row).
  static bool shouldPush({
    required DateTime? localUpdatedAt,
    required DateTime? remoteUpdatedAt,
  }) {
    if (remoteUpdatedAt == null) return true;
    if (localUpdatedAt == null) return false;
    return localUpdatedAt.isAfter(remoteUpdatedAt);
  }

  /// Whether a remote item should be pulled into local storage.
  ///
  /// Pull when it's missing locally ([localUpdatedAt] null) or the remote
  /// copy is strictly newer than the local one.
  static bool shouldPull({
    required DateTime? localUpdatedAt,
    required DateTime remoteUpdatedAt,
  }) {
    if (localUpdatedAt == null) return true;
    return remoteUpdatedAt.isAfter(localUpdatedAt);
  }

  /// Whether a session may be pushed to the remote.
  ///
  /// `session_runs.route_id` has a non-deferrable foreign key to
  /// `route_templates(id)`. Pushing a session whose route is not present
  /// remotely — most often an official route the curator hasn't published, or
  /// a route deleted remotely — raises a 23503 FK violation. Because the push
  /// is not isolated, that single error aborts the entire sync, so no routes,
  /// sessions or free rides get through. Gate the push on the route being
  /// known-present remotely. [remoteRouteIds] must include both the ids fetched
  /// from the remote and any pushed earlier in the same cycle.
  ///
  /// Non-official local routes are always either already remote or pushed
  /// earlier in the cycle, so only official routes missing server-side are
  /// skipped here; such sessions sync automatically once the route appears.
  static bool canPushSession({
    required String routeId,
    required Set<String> remoteRouteIds,
  }) {
    return remoteRouteIds.contains(routeId);
  }

  /// Whether reconciliation deletions (removing local rows absent from the
  /// remote set) are safe to apply.
  ///
  /// When the remote set is empty but local still has items, treat it as a
  /// likely incomplete/failed fetch and skip deletions, so a transient empty
  /// response never wipes the user's local data.
  static bool shouldApplyReconciliationDeletions({
    required int remoteCount,
    required int localCount,
  }) {
    if (remoteCount == 0 && localCount > 0) return false;
    return true;
  }
}
