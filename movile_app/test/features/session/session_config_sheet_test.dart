import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:splitway_mobile/l10n/app_localizations.dart';
import 'package:splitway_mobile/src/features/session/live_session_controller.dart';
import 'package:splitway_mobile/src/features/session/session_config_sheet.dart';

Widget _host(Widget child) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: Scaffold(body: child),
    );

void main() {
  testWidgets('checkbox starts on and Start returns the config', (tester) async {
    SessionConfig? captured;
    await tester.pumpWidget(_host(SessionConfigSheet(
      vehicles: const [],
      initialVehicleId: null,
      isAdmin: false,
      initialSource: TrackingSource.realGps,
      onStart: (c) => captured = c,
    )));
    await tester.pumpAndSettle();

    // Telemetry segmented control is hidden for non-admins.
    expect(find.text('Telemetry source'), findsNothing);

    // Type a name.
    await tester.enterText(find.byType(TextField).first, 'Hot lap');

    // Tap Start.
    await tester.tap(find.text('Start'));
    await tester.pump();

    expect(captured, isNotNull);
    expect(captured!.name, 'Hot lap');
    expect(captured!.includeHistorical, isTrue);
    expect(captured!.source, TrackingSource.realGps);
  });
}
