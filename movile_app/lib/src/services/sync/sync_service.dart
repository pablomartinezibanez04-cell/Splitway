import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

import '../../data/repositories/local_draft_repository.dart';
import '../../data/repositories/supabase_repository.dart';

/// Bidirectional sync between [LocalDraftRepository] (SQLite) and
/// [SupabaseRepository] (Postgres + RLS).
///
/// Strategy: **last-write-wins** based on `updated_at`.
/// - Push: all local routes/sessions that don't exist remotely or are newer.
/// - Pull: all remote routes/sessions that don't exist locally or are newer.
///
/// Supports:
/// - Periodic auto-sync every [syncInterval] (default 5 min).
/// - Connectivity awareness — pauses when offline, resumes when back online.
/// - Manual trigger via [sync()].
class SyncService extends ChangeNotifier {
  SyncService({
    required this.local,
    required this.remote,
    this.syncInterval = const Duration(minutes: 5),
  }) {
    _connectivitySubscription =
        Connectivity().onConnectivityChanged.listen(_onConnectivityChanged);
  }

  final LocalDraftRepository local;
  final SupabaseRepository remote;
  final Duration syncInterval;

  Timer? _periodicTimer;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  bool _isConnected = true;
  bool _disposed = false;

  SyncStatus _status = SyncStatus.idle;
  SyncStatus get status => _status;

  String? _lastError;
  String? get lastError => _lastError;

  DateTime? _lastSyncedAt;
  DateTime? get lastSyncedAt => _lastSyncedAt;

  /// Start the periodic sync timer. Call this after authentication succeeds.
  void startPeriodicSync() {
    _periodicTimer?.cancel();
    _periodicTimer = Timer.periodic(syncInterval, (_) {
      if (_isConnected) sync();
    });
    // Do an initial sync immediately.
    if (_isConnected) sync();
  }

  /// Stop the periodic sync timer (e.g. on sign-out).
  void stopPeriodicSync() {
    _periodicTimer?.cancel();
    _periodicTimer = null;
  }

  void _onConnectivityChanged(List<ConnectivityResult> results) {
    final wasConnected = _isConnected;
    _isConnected =
        results.any((r) => r != ConnectivityResult.none);

    if (_isConnected && !wasConnected) {
      // Back online — sync immediately.
      debugPrint('SyncService: back online, syncing…');
      _status = SyncStatus.idle;
      notifyListeners();
      sync();
    } else if (!_isConnected && wasConnected) {
      debugPrint('SyncService: went offline');
      _status = SyncStatus.offline;
      notifyListeners();
    }
  }

  /// Runs a full bidirectional sync.
  /// Returns the number of items transferred (pushed + pulled).
  Future<int> sync() async {
    if (_status == SyncStatus.syncing) return 0;
    if (!_isConnected) {
      _status = SyncStatus.offline;
      notifyListeners();
      return 0;
    }

    _status = SyncStatus.syncing;
    _lastError = null;
    notifyListeners();

    try {
      final transferred = await _doSync();
      _status = SyncStatus.success;
      _lastSyncedAt = DateTime.now();
      notifyListeners();
      return transferred;
    } catch (e, st) {
      debugPrint('SyncService error: $e\n$st');
      _status = SyncStatus.error;
      _lastError = e.toString();
      notifyListeners();
      return 0;
    }
  }

  Future<int> _doSync() async {
    var transferred = 0;

    // --- Routes ---
    // Comparison uses only IDs + timestamps — no heavy path_json loading.
    final localRoutes = await local.getAllRoutes();
    final remoteRouteTs = await remote.fetchRouteTimestamps();

    // Push local → remote (new or newer locally, or missing thumbnail).
    // Collect routes with new thumbnails to batch-save locally afterwards,
    // so the controller's 300ms reload debouncer collapses all saves into
    // a single UI rebuild (avoids one flicker per thumbnail loaded).
    final routesWithNewThumbnails = <RouteTemplate>[];
    for (final route in localRoutes) {
      if (route.id == 'demo-oval') continue; // never push demo route
      final remoteUpdated = remoteRouteTs[route.id];
      final needsPush = remoteUpdated == null ||
          route.createdAt.isAfter(remoteUpdated);
      final needsThumbnail = route.thumbnailUrl == null;
      if (needsPush || needsThumbnail) {
        final updated = await remote.upsertRoute(route);
        if (updated.thumbnailUrl != null &&
            updated.thumbnailUrl != route.thumbnailUrl) {
          routesWithNewThumbnails.add(updated);
        }
        transferred++;
      }
    }
    // Batch-save: all local writes happen back-to-back (no network delay),
    // so the 300ms debouncer collapses them into one reload.
    for (final route in routesWithNewThumbnails) {
      await local.saveRouteTemplate(route);
    }

    // Pull remote → local (only routes that don't exist locally)
    final localRouteIds = {for (final r in localRoutes) r.id};
    final remoteRoutes = await remote.fetchAllRoutes();
    for (final route in remoteRoutes) {
      if (!localRouteIds.contains(route.id)) {
        await local.saveRouteTemplate(route);
        transferred++;
      }
    }

    // --- Sessions ---
    // Load local sessions WITHOUT telemetry — only need IDs + timestamps
    // to decide what to push/pull.
    final localSessions = await local.getAllSessions(includePoints: false);
    final remoteSessionTs = await remote.fetchSessionTimestamps();

    // Push local → remote (new or newer locally).
    // Re-load each session WITH points only when we actually need to push.
    for (final session in localSessions) {
      final remoteUpdated = remoteSessionTs[session.id];
      if (remoteUpdated == null ||
          (session.endedAt?.isAfter(remoteUpdated) ?? false)) {
        final full = await local.getSessionRun(session.id);
        if (full != null) {
          await remote.upsertSession(full);
          transferred++;
        }
      }
    }

    // Pull remote → local (only sessions that don't exist locally).
    // Fetch each missing session individually instead of all at once.
    final localSessionIds = {for (final s in localSessions) s.id};
    for (final remoteId in remoteSessionTs.keys) {
      if (!localSessionIds.contains(remoteId)) {
        final session =
            await remote.fetchSession(remoteId, includePoints: true);
        if (session != null) {
          await local.saveSessionRun(session);
          transferred++;
        }
      }
    }

    // --- Free rides ---
    final localFreeRides = await local.getAllFreeRides();
    final remoteFreeRideTs = await remote.fetchFreeRideTimestamps();

    // Push local → remote
    for (final ride in localFreeRides) {
      final remoteUpdated = remoteFreeRideTs[ride.id];
      if (remoteUpdated == null ||
          (ride.endedAt?.isAfter(remoteUpdated) ?? false)) {
        // Re-load with telemetry for push
        final full = await local.getFreeRideRun(ride.id);
        if (full != null) {
          await remote.upsertFreeRide(full);
          transferred++;
        }
      }
    }

    // Pull remote → local (only rides that don't exist locally)
    final localFreeRideIds = {for (final r in localFreeRides) r.id};
    for (final remoteId in remoteFreeRideTs.keys) {
      if (!localFreeRideIds.contains(remoteId)) {
        final ride =
            await remote.fetchFreeRide(remoteId, includePoints: true);
        if (ride != null) {
          await local.saveFreeRideRun(ride);
          transferred++;
        }
      }
    }

    return transferred;
  }

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _periodicTimer?.cancel();
    _connectivitySubscription?.cancel();
    super.dispose();
  }
}

enum SyncStatus { idle, syncing, error, success, offline }
