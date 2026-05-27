import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:splitway_mobile/l10n/app_localizations.dart';
import 'package:splitway_mobile/src/services/locale/locale_controller.dart';
import 'package:splitway_mobile/src/services/settings/app_settings_controller.dart';
import 'package:splitway_mobile/src/shared/widgets/speed_heatmap_legend.dart';

Widget _harness({required Locale locale, required Widget child}) => MaterialApp(
      locale: locale,
      supportedLocales: LocaleController.supported,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: Scaffold(body: SizedBox(height: 200, child: child)),
    );

void main() {
  testWidgets('renders 0, mid and max labels in km/h for metric', (tester) async {
    // 50 km/h ≈ 13.8889 m/s.
    const maxMps = 50 / 3.6;
    await tester.pumpWidget(_harness(
      locale: const Locale('en'),
      child: const SpeedHeatmapLegend(maxMps: maxMps, unit: UnitSystem.metric),
    ));

    expect(find.text('50.0 km/h'), findsOneWidget);
    expect(find.text('25.0 km/h'), findsOneWidget);
    expect(find.text('0.0 km/h'), findsOneWidget);
  });

  testWidgets('renders labels in mph for imperial', (tester) async {
    // 60 mph ≈ 26.8224 m/s.
    const maxMps = 60 / 2.23694;
    await tester.pumpWidget(_harness(
      locale: const Locale('en'),
      child: const SpeedHeatmapLegend(maxMps: maxMps, unit: UnitSystem.imperial),
    ));

    expect(find.text('60.0 mph'), findsOneWidget);
    expect(find.text('30.0 mph'), findsOneWidget);
    expect(find.text('0.0 mph'), findsOneWidget);
  });
}
