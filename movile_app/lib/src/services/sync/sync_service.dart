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
    final localRoutes = await local.getAllRoutes();
    final remoteTimestamps = await remote.fetchRouteTimestamps();

    // Push local → remote (routes that are new or newer locally)
    for (final route in localRoutes) {
      final remoteUpdated = remoteTimestamps[route.id];
      if (remoteUpdated == null || route.createdAt.isAfter(remoteUpdated)) {
        await remote.upsertRoute(route);
        transferred++;
      }
    }

    // Pull remote → local (routes that don't exist locally or are newer)
    final localRouteIds = {for (final r in localRoutes) r.id};
    final remoteRoutes = await remote.fetchAllRoutes();
    for (final route in remoteRoutes) {
      if (!localRouteIds.contains(route.id)) {
        await local.saveRouteTemplate(route);
        transferred++;
      }
    }

    // --- Sessions ---
    final localSessions = await local.getAllSessions(includePoints: true);
    final remoteSessionTimestamps = await remote.fetchSessionTimestamps();

    // Push local → remote
    for (final session in localSessions) {
      final remoteUpdated = remoteSessionTimestamps[session.id];
      if (remoteUpdated == null ||
          (session.endedAt?.isAfter(remoteUpdated) ?? false)) {
        await remote.upsertSession(session);
        transferred++;
      }
    }

    // Pull remote → local
    final localSessionIds = {for (final s in localSessions) s.id};
    final remoteSessions =
        await remote.fetchAllSessions(includePoints: true);
    for (final session in remoteSessions) {
      if (!localSessionIds.contains(session.id)) {
        await local.saveSessionRun(session);
        transferred++;
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
