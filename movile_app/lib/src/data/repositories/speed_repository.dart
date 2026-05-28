import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/logging/app_logger.dart';
import '../../services/speed/speed_session.dart';
import '../local/speed_session_dao.dart';

class SpeedRepository {
  SpeedRepository({required this.localDao, required this.supabase});

  final SpeedSessionDao localDao;
  final SupabaseClient? supabase;

  Future<void> save(SpeedSession session) async {
    await localDao.upsert(session);
    final client = supabase;
    if (client != null && client.auth.currentUser != null) {
      try {
        await client.from('speed_sessions').upsert(session.toJson());
      } catch (e, st) {
        // Network failure or RLS — keep local copy; SyncService will retry.
        AppLogger.maybeInstance?.warning(
          'supabase',
          'speed.save remote upsert failed',
          error: e,
          stackTrace: st,
        );
      }
    }
  }

  Future<List<SpeedSession>> listForUser(String userId) =>
      localDao.listForUser(userId);

  Future<SpeedSession?> getById(String id) => localDao.getById(id);

  Future<void> softDelete(String id) async {
    await localDao.softDelete(id);
    final client = supabase;
    if (client != null && client.auth.currentUser != null) {
      try {
        await client
            .from('speed_sessions')
            .update({'deleted_at': DateTime.now().toUtc().toIso8601String()})
            .eq('id', id);
      } catch (e, st) {
        // sync will reconcile
        AppLogger.maybeInstance?.warning(
          'supabase',
          'speed.softDelete remote update failed',
          error: e,
          stackTrace: st,
        );
      }
    }
  }

  /// Pushes every local session for [userId] to Supabase (upsert).
  Future<int> pushAllForUser(String userId) async {
    final client = supabase;
    if (client == null || client.auth.currentUser == null) return 0;
    final local = await localDao.listForUser(userId);
    var n = 0;
    for (final s in local) {
      try {
        await client.from('speed_sessions').upsert(s.toJson());
        n++;
      } catch (e, st) {
        // best-effort
        AppLogger.maybeInstance?.warning(
          'supabase',
          'speed.pushAllForUser upsert failed',
          error: e,
          stackTrace: st,
        );
      }
    }
    return n;
  }

  /// Pulls every remote session for [userId] into the local DAO.
  Future<int> pullAllForUser(String userId) async {
    final client = supabase;
    if (client == null || client.auth.currentUser == null) return 0;
    try {
      final rows = await client
          .from('speed_sessions')
          .select()
          .eq('user_id', userId)
          .filter('deleted_at', 'is', null)
          .order('updated_at', ascending: false);
      var n = 0;
      for (final row in (rows as List)) {
        final s = SpeedSession.fromJson(row as Map<String, dynamic>);
        await localDao.upsert(s);
        n++;
      }
      return n;
    } catch (e, st) {
      AppLogger.maybeInstance?.warning(
        'supabase',
        'speed.pullAllForUser failed',
        error: e,
        stackTrace: st,
      );
      return 0;
    }
  }
}
