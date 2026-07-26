import 'package:flutter_test/flutter_test.dart';
import 'package:monte/features/tournament/domain/payout_structure.dart';
import 'package:monte/features/tournament/domain/tournament_state.dart';
import 'package:monte/features/tournament/domain/tournament_structure.dart';

TournamentState _state({
  int n = 4,
  int buyIn = 100,
  int stack = 1000,
  TournamentStructure? structure,
}) {
  final players = <String, TournamentPlayer>{
    for (var i = 0; i < n; i++)
      'p$i': TournamentPlayer(id: 'p$i', name: 'p$i', isHuman: i == 0, chips: stack),
  };
  return TournamentState(
    structure: structure ?? TournamentStructure.standard(),
    payouts: PayoutStructure.forFieldSize(n),
    buyIn: buyIn,
    players: players,
    tables: [TournamentTable(id: 0, playerIds: players.keys.toList())],
  );
}

void main() {
  group('TournamentState bustouts & champion', () {
    test('assigns descending finish places and pays only in the money', () {
      final s = _state(n: 4); // forFieldSize(4) => 2 paid places
      expect(s.paidPlaces, 2);
      expect(s.prizePool, 400);

      s.recordBustouts(['p3']); // 4 left -> finishes 4th, unpaid
      expect(s.players['p3']!.finishPlace, 4);
      expect(s.players['p3']!.prizeWon, 0);
      expect(s.playersRemaining, 3);

      s.recordBustouts(['p2']); // 3rd, still unpaid (bubble was 3rd)
      expect(s.players['p2']!.finishPlace, 3);
      expect(s.players['p2']!.prizeWon, 0);

      s.recordBustouts(['p1']); // 2nd, paid
      expect(s.players['p1']!.finishPlace, 2);
      expect(s.players['p1']!.prizeWon, s.payoutTable[1]);

      s.declareChampion();
      expect(s.players['p0']!.finishPlace, 1);
      expect(s.players['p0']!.prizeWon, s.payoutTable[0]);
      expect(s.status, TournamentStatus.finished);

      // Every chip is paid out.
      final paid = s.players.values.fold(0, (a, p) => a + p.prizeWon);
      expect(paid, s.prizePool);
    });

    test('simultaneous bustouts take the worst places worst-first', () {
      final s = _state(n: 6);
      s.recordBustouts(['p5', 'p4']); // worst-first: p5 = 6th, p4 = 5th
      expect(s.players['p5']!.finishPlace, 6);
      expect(s.players['p4']!.finishPlace, 5);
      expect(s.playersRemaining, 4);
    });

    test('onBubble and inMoney track the paid-places boundary', () {
      final s = _state(n: 4); // 2 paid
      expect(s.onBubble, isFalse);
      s.recordBustouts(['p3']); // 3 left -> bubble (paid+1)
      expect(s.onBubble, isTrue);
      expect(s.inMoney, isFalse);
      s.recordBustouts(['p2']); // 2 left -> in the money
      expect(s.inMoney, isTrue);
    });
  });

  group('TournamentState level clock', () {
    test('advances by hands and resets the counter', () {
      final s = _state(structure: TournamentStructure.turbo(clockMode: LevelClockMode.hands));
      final needed = s.structure.durationOf(0);
      s.handsThisLevel = needed - 1;
      expect(s.maybeAdvanceLevel(), isFalse);
      s.handsThisLevel = needed;
      expect(s.maybeAdvanceLevel(), isTrue);
      expect(s.levelIndex, 1);
      expect(s.handsThisLevel, 0);
    });

    test('advances by minutes when in wall-clock mode', () {
      final s = _state(structure: TournamentStructure.turbo(clockMode: LevelClockMode.minutes));
      s.clockElapsed = Duration(minutes: s.structure.durationOf(0));
      expect(s.maybeAdvanceLevel(), isTrue);
      expect(s.clockElapsed, Duration.zero);
    });
  });

  group('TournamentState rebuys', () {
    test('re-entry reactivates a busted player and grows the pool', () {
      final structure = TournamentStructure.standard();
      final rebuyStructure = TournamentStructure(
        name: 'Rebuy',
        levels: structure.levels,
        clockMode: structure.clockMode,
        startingStack: structure.startingStack,
        maxRebuys: 1,
        reentryLevelCutoff: 3,
      );
      final s = _state(n: 4, structure: rebuyStructure);
      s.recordBustouts(['p3']);
      final poolBefore = s.prizePool;

      final ok = s.rebuy('p3', chips: 1000);
      expect(ok, isTrue);
      expect(s.players['p3']!.isActive, isTrue);
      expect(s.players['p3']!.finishPlace, isNull);
      expect(s.prizePool, poolBefore + s.buyIn);
      expect(s.playersRemaining, 4);

      // A second rebuy exceeds the cap.
      s.recordBustouts(['p3']);
      expect(s.rebuy('p3', chips: 1000), isFalse);
    });

    test('freezeouts refuse rebuys', () {
      final s = _state(n: 4); // standard preset: no rebuys
      s.recordBustouts(['p3']);
      expect(s.rebuy('p3', chips: 1000), isFalse);
    });
  });
}
