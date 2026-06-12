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
