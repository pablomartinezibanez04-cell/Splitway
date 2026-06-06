import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:splitway_core/splitway_core.dart';

import '../../data/repositories/local_draft_repository.dart';
import '../logging/app_logger.dart';
import '../settings/app_settings_controller.dart';

/// Thin interface over the remote source so the service can be tested
/// without a live Supabase client. Implemented by `SupabaseRepository`.
abstract class OfficialRoutesRemote {
  Future<List<RouteTemplate>> fetchOfficialRoutes();
}

/// Owns the lifecycle of the official-routes catalog on the device.
///
/// Pulls the catalog from Supabase (anon-readable), reconciles it with the
/// local SQLite store, and applies per-device dismissal state stored in
/// [AppSettingsController.dismissedOfficialRoutes].
class OfficialRoutesService extends ChangeNotifier {
  OfficialRoutesService({
    required OfficialRoutesRemote remote,
    required LocalDraftRepository local,
    required AppSettingsController settings,
  })  : _remote = remote,
        _local = local,
        _settings = settings;

  final OfficialRoutesRemote _remote;
  final LocalDraftRepository _local;
  final AppSettingsController _settings;

  Future<void>? _inFlight;

  /// Fetches the official catalog from Supabase and reconciles the local
  /// store. Concurrent calls share the same in-flight future. Network /
  /// Supabase errors are logged and swallowed.
  Future<void> refresh() {
    final existing = _inFlight;
    if (existing != null) return existing;
    final fut = _doRefresh();
    _inFlight = fut;
    return fut.whenComplete(() => _inFlight = null);
  }

  Future<void> _doRefresh() async {
    final List<RouteTemplate> remote;
    try {
      remote = await _remote.fetchOfficialRoutes();
    } catch (e, st) {
      AppLogger.maybeInstance?.warning(
        'official_routes',
        'fetch failed; keeping local state',
        error: e,
        stackTrace: st,
      );
      return;
    }

    // Snapshot dismissals once so the per-route decisions below are
    // consistent even if clearDismissal mutates prefs mid-loop.
    final dismissals = _settings.dismissedOfficialRoutes;

    // Reconcile each remote route against dismissals BEFORE writing to
    // local. This avoids the previous "save then delete" flicker and the
    // race where a dismissed-unchanged route briefly reappeared.
    for (final r in remote) {
      final dismissedAt = dismissals[r.id];
      if (dismissedAt == null) {
        // Not dismissed → save normally.
        await _local.saveRouteTemplate(r);
        continue;
      }
      final remoteMillis = r.updatedAt?.millisecondsSinceEpoch ?? 0;
      if (remoteMillis > dismissedAt) {
        // The route was modified after the dismissal — bring it back and
        // forget the dismissal so future refreshes don't second-guess it.
        await _settings.clearDismissal(r.id);
        await _local.saveRouteTemplate(r);
      } else {
        // Still dismissed-unchanged — don't save, and make sure no stale
        // copy lingers locally (e.g. from a pre-fix install).
        await _local.deleteRoute(r.id);
      }
    }

    // Prune local officials that no longer exist remotely (the curator
    // deleted them or flipped is_official off).
    final remoteIds = {for (final r in remote) r.id};
    final localRoutes = await _local.getAllRoutes();
    for (final r in localRoutes) {
      if (!r.isOfficial) continue;
      if (remoteIds.contains(r.id)) continue;
      await _local.deleteRoute(r.id);
    }

    notifyListeners();
  }

  /// Dismisses an official route on this device. Records its current
  /// `updated_at` in settings and deletes the row locally. A future refresh
  /// with a newer `updated_at` will bring it back.
  Future<void> dismiss(String routeId) async {
    final route = await _local.getRouteTemplate(routeId);
    final stamp = route?.updatedAt?.millisecondsSinceEpoch ?? 0;
    await _settings.recordDismissal(routeId, stamp);
    await _local.deleteRoute(routeId);
    notifyListeners();
  }
}
