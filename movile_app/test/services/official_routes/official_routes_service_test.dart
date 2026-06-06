import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:splitway_core/splitway_core.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:splitway_mobile/src/data/local/splitway_local_database.dart';
import 'package:splitway_mobile/src/data/repositories/local_draft_repository.dart';
import 'package:splitway_mobile/src/services/official_routes/official_routes_service.dart';
import 'package:splitway_mobile/src/services/settings/app_settings_controller.dart';

class _FakeRemote implements OfficialRoutesRemote {
  _FakeRemote(this.routes);
  List<RouteTemplate> routes;
  int callCount = 0;
  @override
  Future<List<RouteTemplate>> fetchOfficialRoutes() async {
    callCount++;
    return routes;
  }
}

class _ThrowingRemote implements OfficialRoutesRemote {
  @override
  Future<List<RouteTemplate>> fetchOfficialRoutes() async {
    throw StateError('boom');
  }
}

RouteTemplate official(String id, DateTime updatedAt) => RouteTemplate(
      id: id,
      name: 'Official $id',
      path: const [],
      startFinishGate: GateDefinition(
        left: GeoPoint(latitude: 0, longitude: 0),
        right: GeoPoint(latitude: 0, longitude: 0),
      ),
      sectors: const [],
      difficulty: RouteDifficulty.medium,
      createdAt: DateTime.utc(2026, 1, 1),
      isOfficial: true,
      updatedAt: updatedAt,
    );

void main() {
  late SplitwayLocalDatabase database;
  late LocalDraftRepository repo;
  late AppSettingsController settings;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    database = await SplitwayLocalDatabase.open(overridePath: inMemoryDatabasePath);
    repo = LocalDraftRepository(database);
    settings = await AppSettingsController.load();
  });

  tearDown(() async {
    await repo.dispose();
    await database.close();
  });

  test('refresh inserts new remote official routes locally', () async {
    final remote = _FakeRemote([official('r1', DateTime.utc(2026, 5, 1))]);
    final svc = OfficialRoutesService(
        remote: remote, local: repo, settings: settings);
    await svc.refresh();
    final loaded = await repo.getRouteTemplate('r1');
    expect(loaded, isNotNull);
    expect(loaded!.isOfficial, isTrue);
    expect(loaded.updatedAt?.millisecondsSinceEpoch,
        DateTime.utc(2026, 5, 1).millisecondsSinceEpoch);
  });

  test('refresh prunes local official routes absent in remote', () async {
    await repo.saveRouteTemplate(
        official('stale', DateTime.utc(2026, 4, 1)));
    final remote = _FakeRemote([]);
    final svc = OfficialRoutesService(
        remote: remote, local: repo, settings: settings);
    await svc.refresh();
    expect(await repo.getRouteTemplate('stale'), isNull);
  });

  test('refresh applies dismissal: remote updated > dismissedAt -> reappears',
      () async {
    final dismissedAt =
        DateTime.utc(2026, 4, 1).millisecondsSinceEpoch;
    await settings.recordDismissal('r1', dismissedAt);

    final remote = _FakeRemote([official('r1', DateTime.utc(2026, 5, 1))]);
    final svc = OfficialRoutesService(
        remote: remote, local: repo, settings: settings);
    await svc.refresh();

    expect(await repo.getRouteTemplate('r1'), isNotNull);
    expect(settings.dismissedOfficialRoutes.containsKey('r1'), isFalse);
  });

  test('refresh applies dismissal: remote updated <= dismissedAt -> removed',
      () async {
    final updatedAt = DateTime.utc(2026, 4, 1);
    await settings.recordDismissal('r1', updatedAt.millisecondsSinceEpoch);

    final remote = _FakeRemote([official('r1', updatedAt)]);
    final svc = OfficialRoutesService(
        remote: remote, local: repo, settings: settings);
    await svc.refresh();

    expect(await repo.getRouteTemplate('r1'), isNull);
    expect(settings.dismissedOfficialRoutes['r1'],
        updatedAt.millisecondsSinceEpoch);
  });

  test('dismiss records updated_at and deletes from local', () async {
    final updatedAt = DateTime.utc(2026, 5, 1);
    await repo.saveRouteTemplate(official('r1', updatedAt));

    final svc = OfficialRoutesService(
        remote: _FakeRemote([]), local: repo, settings: settings);
    await svc.dismiss('r1');

    expect(await repo.getRouteTemplate('r1'), isNull);
    expect(settings.dismissedOfficialRoutes['r1'],
        updatedAt.millisecondsSinceEpoch);
  });

  test('refresh swallows fetch errors and leaves local unchanged', () async {
    await repo.saveRouteTemplate(
        official('r1', DateTime.utc(2026, 4, 1)));

    final svc = OfficialRoutesService(
      remote: _ThrowingRemote(),
      local: repo,
      settings: settings,
    );
    await svc.refresh(); // must not throw

    expect(await repo.getRouteTemplate('r1'), isNotNull);
  });

  test('concurrent refresh calls coalesce — only one fetch in flight',
      () async {
    final remote = _FakeRemote([]);
    final svc = OfficialRoutesService(
        remote: remote, local: repo, settings: settings);
    await Future.wait([svc.refresh(), svc.refresh(), svc.refresh()]);
    expect(remote.callCount, 1);
  });
}
