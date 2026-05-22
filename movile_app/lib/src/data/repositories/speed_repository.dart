import 'package:supabase_flutter/supabase_flutter.dart';

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
      } catch (_) {
        // Network failure or RLS — keep local copy; SyncService will retry.
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
      } catch (_) {
        // sync will reconcile
      }
    }
  }
}
