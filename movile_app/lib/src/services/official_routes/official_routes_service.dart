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

    final remoteById = {for (final r in remote) r.id: r};

    // Upsert remote rows locally.
    for (final r in remote) {
      await _local.saveRouteTemplate(r);
    }

    // Prune local officials that no longer exist remotely.
    final localRoutes = await _local.getAllRoutes();
    for (final r in localRoutes) {
      if (!r.isOfficial) continue;
      if (remoteById.containsKey(r.id)) continue;
      await _local.deleteRoute(r.id);
    }

    // Apply dismissals: if remote.updated_at > dismissedAt, the user
    // should see the route again; otherwise keep it dismissed.
    final dismissals = _settings.dismissedOfficialRoutes;
    for (final entry in dismissals.entries) {
      final id = entry.key;
      final dismissedAt = entry.value;
      final remoteRoute = remoteById[id];
      if (remoteRoute == null) continue; // not in catalog anymore — leave entry
      final remoteMillis = remoteRoute.updatedAt?.millisecondsSinceEpoch ?? 0;
      if (remoteMillis > dismissedAt) {
        await _settings.clearDismissal(id);
      } else {
        await _local.deleteRoute(id);
      }
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
