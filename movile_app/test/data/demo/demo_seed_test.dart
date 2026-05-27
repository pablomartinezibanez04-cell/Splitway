import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:splitway_mobile/src/data/demo/demo_seed.dart';
import 'package:splitway_mobile/src/data/local/splitway_local_database.dart';
import 'package:splitway_mobile/src/data/repositories/local_draft_repository.dart';
import 'package:splitway_mobile/src/services/settings/app_settings_controller.dart';

int _counter = 0;

Future<LocalDraftRepository> _makeRepo() async {
  _counter++;
  final db = await SplitwayLocalDatabase.open(
    overridePath: 'file:demo_seed_test_$_counter?mode=memory&cache=shared',
  );
  return LocalDraftRepository(db);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('seeds España route into empty DB', () async {
    final repo = await _makeRepo();
    final settings = await AppSettingsController.load();

    await DemoSeed.ensureSeeded(repo, settings);

    final route = await repo.getRouteTemplate('demo-espana');
    expect(route, isNotNull);
    expect(route!.name, 'Demo España');
    expect(route.sectors, hasLength(2));
  });

  test('does not re-seed when route already exists', () async {
    final repo = await _makeRepo();
    final settings = await AppSettingsController.load();

    await DemoSeed.ensureSeeded(repo, settings);
    await DemoSeed.ensureSeeded(repo, settings);

    final routes = await repo.getAllRoutes();
    expect(routes.where((r) => r.id == 'demo-espana'), hasLength(1));
  });

  test('does not seed when route is dismissed', () async {
    final repo = await _makeRepo();
    final settings = await AppSettingsController.load();
    await settings.dismissDemoRoute('demo-espana');

    await DemoSeed.ensureSeeded(repo, settings);

    final route = await repo.getRouteTemplate('demo-espana');
    expect(route, isNull);
  });

  test('does not re-seed after deletion when dismissed', () async {
    final repo = await _makeRepo();
    final settings = await AppSettingsController.load();

    await DemoSeed.ensureSeeded(repo, settings);
    await settings.dismissDemoRoute('demo-espana');
    await repo.deleteRoute('demo-espana');

    await DemoSeed.ensureSeeded(repo, settings);

    final route = await repo.getRouteTemplate('demo-espana');
    expect(route, isNull);
  });
}
