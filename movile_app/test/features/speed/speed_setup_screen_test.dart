import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:splitway_mobile/l10n/app_localizations.dart';
import 'package:splitway_mobile/src/features/speed/speed_setup_screen.dart';

void main() {
  testWidgets('Continue disabled without vehicle and metrics', (tester) async {
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: SpeedSetupScreen(
        garageService: null,
        onContinue: (_) {},
      ),
    ));
    await tester.pumpAndSettle();
    final btn = find.byKey(const Key('speed-continue'));
    expect(btn, findsOneWidget);
    expect(tester.widget<FilledButton>(btn).onPressed, isNull);
  });
}
