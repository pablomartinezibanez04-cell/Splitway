import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:splitway_mobile/src/data/local/splitway_local_database.dart';
import 'package:splitway_mobile/src/features/logs/logs_screen.dart';
import 'package:splitway_mobile/src/services/logging/log_entry.dart';
import 'package:splitway_mobile/src/services/logging/log_level.dart';
import 'package:splitway_mobile/src/services/logging/log_uploader.dart';
import 'package:splitway_mobile/src/services/logging/sinks/local_sink.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late SplitwayLocalDatabase db;
  late LocalSink sink;
  late LogUploader uploader;

  setUp(() async {
    db = await SplitwayLocalDatabase.open(overridePath: inMemoryDatabasePath);
    sink = LocalSink(db);
    uploader = LogUploader(sink: sink, upload: (_) async {});
    await sink.write(LogEntry(
      id: '1',
      timestamp: DateTime.now().toUtc(),
      level: LogLevel.error,
      tag: 'supabase',
      message: 'upsert failed',
      appVersion: '0.4.0+1',
      platform: 'test',
      deviceModel: 'test',
    ));
  });

  tearDown(() async => db.close());

  testWidgets('renders the only log entry', (tester) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(MaterialApp(
        home: LogsScreen(sink: sink, uploader: uploader),
      ));
      // initState triggers an async _reload that hits SQLite. runAsync lets
      // real async work (including SQLite via FFI) complete.
      await Future<void>.delayed(const Duration(milliseconds: 200));
      await tester.pump();
    });
    expect(find.text('upsert failed'), findsOneWidget);
    // 'supabase' appears both in the filter chip and the log tile.
    expect(find.text('supabase'), findsNWidgets(2));
  });
}
