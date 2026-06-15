import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:splitway_mobile/src/shared/widgets/sector_chip.dart';
import 'package:splitway_mobile/src/shared/widgets/sector_chips_bar.dart';

Widget _wrap(Widget child) => MaterialApp(
      home: Scaffold(
        body: Center(child: child),
      ),
    );

List<SectorChipTier> _tiers(int n) =>
    List.filled(n, SectorChipTier.unset);

void main() {
  group('SectorChipsBar layout', () {
    testWidgets('3 sectors use an Expanded row (no horizontal scroll)',
        (tester) async {
      await tester.pumpWidget(_wrap(SectorChipsBar(tiers: _tiers(3))));

      expect(find.byType(SingleChildScrollView), findsNothing);
      expect(find.byType(SectorChip), findsNWidgets(3));
      expect(find.text('S1'), findsOneWidget);
      expect(find.text('S3'), findsOneWidget);
    });

    testWidgets('1 sector uses an Expanded row', (tester) async {
      await tester.pumpWidget(_wrap(SectorChipsBar(tiers: _tiers(1))));

      expect(find.byType(SingleChildScrollView), findsNothing);
      expect(find.byType(SectorChip), findsOneWidget);
    });

    testWidgets('4+ sectors use a horizontal scroll list', (tester) async {
      await tester.pumpWidget(_wrap(SectorChipsBar(tiers: _tiers(5))));

      expect(find.byType(SingleChildScrollView), findsOneWidget);
      expect(find.byType(SectorChip), findsNWidgets(5));
      expect(find.text('S1'), findsOneWidget);
      expect(find.text('S5'), findsOneWidget);
    });

    testWidgets('scrolling list reserves room for 3 chips per viewport',
        (tester) async {
      // Force a known viewport width.
      tester.view.physicalSize = const Size(600, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_wrap(
        SizedBox(width: 600, child: SectorChipsBar(tiers: _tiers(6))),
      ));
      await tester.pumpAndSettle();

      // Each chip ≈ (600 - 2*8) / 3 ≈ 194.6 wide.
      final w = tester.getSize(find.byType(SectorChip).first).width;
      expect(w, closeTo((600 - 2 * 8) / 3, 1.0));
    });
  });

  group('SectorChipsBar auto-scroll', () {
    testWidgets('activeIndex 0 keeps the first sector at the left edge',
        (tester) async {
      tester.view.physicalSize = const Size(600, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_wrap(
        SizedBox(
          width: 600,
          child: SectorChipsBar(tiers: _tiers(6), activeIndex: 0),
        ),
      ));
      await tester.pumpAndSettle();

      expect(tester.getTopLeft(find.text('S1')).dx, greaterThanOrEqualTo(0));
    });

    testWidgets('a high activeIndex scrolls earlier sectors off-screen',
        (tester) async {
      tester.view.physicalSize = const Size(600, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_wrap(
        SizedBox(
          width: 600,
          child: SectorChipsBar(tiers: _tiers(6), activeIndex: 5),
        ),
      ));
      await tester.pumpAndSettle();

      // S1 should have scrolled out of view to the left.
      expect(tester.getTopLeft(find.text('S1')).dx, lessThan(0));
      // The active sector (S6) should be visible within the viewport.
      final s6x = tester.getTopLeft(find.text('S6')).dx;
      expect(s6x, greaterThanOrEqualTo(0));
      expect(s6x, lessThan(600));
    });
  });
}
