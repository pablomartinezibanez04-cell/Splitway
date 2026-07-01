import 'package:splitway_core/splitway_core.dart';

/// Narrow remote surface that [SyncService] depends on, mirroring the
/// [OfficialRoutesRemote] pattern so the service can be unit-tested against a
/// fake backend without a live Supabase client. [SupabaseRepository]
/// implements this in addition to [OfficialRoutesRemote].
abstract class SyncRemote {
  // Routes
  Future<Map<String, DateTime>> fetchRouteTimestamps();
  Future<List<RouteTemplate>> fetchAllRoutes();
  Future<RouteTemplate> upsertRoute(RouteTemplate route);
  Future<void> deleteRoute(String id);

  // Sessions
  Future<Map<String, DateTime>> fetchSessionTimestamps();
  Future<SessionRun?> fetchSession(String id, {bool includePoints = false});
  Future<void> upsertSession(SessionRun session);
  Future<void> deleteSession(String id);

  // Free rides
  Future<Map<String, DateTime>> fetchFreeRideTimestamps();
  Future<FreeRideRun?> fetchFreeRide(String id, {bool includePoints = false});
  Future<void> upsertFreeRide(FreeRideRun ride);
  Future<void> deleteFreeRide(String id);
}
