import 'package:flutter_test/flutter_test.dart';
import 'package:splitway_mobile/src/shared/widgets/sector_chip.dart';

Duration s(int seconds, [int ms = 0]) =>
    Duration(seconds: seconds, milliseconds: ms);

void main() {
  group('sectorChipTier', () {
    test('null lapTime -> unset', () {
      expect(
        sectorChipTier(
          lapTime: null,
          sessionCrossings: const [],
          historicalRecord: null,
        ),
        SectorChipTier.unset,
      );
    });

    test('first time ever (no history, single crossing) -> overall', () {
      final t = s(25);
      expect(
        sectorChipTier(
          lapTime: t,
          sessionCrossings: [t],
          historicalRecord: null,
        ),
        SectorChipTier.overall,
      );
    });

    test('beats historical record -> overall', () {
      final t = s(24, 500);
      expect(
        sectorChipTier(
          lapTime: t,
          sessionCrossings: [t, s(26)],
          historicalRecord: s(25),
        ),
        SectorChipTier.overall,
      );
    });

    test('best of session but slower than historical record -> sessionBest', () {
      final t = s(25, 200);
      expect(
        sectorChipTier(
          lapTime: t,
          sessionCrossings: [t, s(27)],
          historicalRecord: s(24),
        ),
        SectorChipTier.sessionBest,
      );
    });

    test('slower than session best -> slower', () {
      final t = s(28);
      expect(
        sectorChipTier(
          lapTime: t,
          sessionCrossings: [s(25), t],
          historicalRecord: s(24),
        ),
        SectorChipTier.slower,
      );
    });

    test('ties historical record -> overall (<= favours better tier)', () {
      final t = s(24);
      expect(
        sectorChipTier(
          lapTime: t,
          sessionCrossings: [t, s(26)],
          historicalRecord: s(24),
        ),
        SectorChipTier.overall,
      );
    });

    test('ties session best (no history) -> overall when it is the min', () {
      final t = s(25);
      // Two equal session times, no history: t equals the session/overall best.
      expect(
        sectorChipTier(
          lapTime: t,
          sessionCrossings: [s(25), t],
          historicalRecord: null,
        ),
        SectorChipTier.overall,
      );
    });

    test('sessionCrossings empty but lapTime set -> falls back to lapTime',
        () {
      final t = s(25);
      expect(
        sectorChipTier(
          lapTime: t,
          sessionCrossings: const [],
          historicalRecord: s(30),
        ),
        SectorChipTier.overall,
      );
    });
  });
}
