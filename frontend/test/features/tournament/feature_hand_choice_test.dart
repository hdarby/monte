import 'package:flutter_test/flutter_test.dart';
import 'package:monte/core/domain/ai/trigger_observer.dart';
import 'package:monte/core/domain/engine/game.dart' show BettingRound;
import 'package:monte/core/domain/engine/hand_evaluator.dart';
import 'package:monte/features/tournament/domain/tournament_chronicle.dart';
import 'package:monte/features/tournament/domain/tournament_snapshot.dart'
    show StandingKind;

/// Only one hand per level is ever narrated, so which one gets the slot decides
/// what the player actually sees. Picking it on pot size alone threw away most
/// of what is worth watching: over a level of 27 runners, signature moves fired
/// three times and not one landed in the biggest pot.
HandReplay _replay({
  int pot = 1000,
  bool allIn = false,
  bool suckout = false,
  HandRank winner = HandRank.pair,
  HandRank loser = HandRank.highCard,
  List<FiredTrigger> triggers = const [],
  List<String> seatIds = const [],
}) =>
    HandReplay(
      pot: pot,
      bigBlind: 100,
      board: const ['Kd', '7s', '2c', '9h', '3d'],
      seats: [
        for (final id in seatIds)
          ReplaySeat(
            playerId: id,
            name: id,
            cards: const ['Ac', 'Ad'],
            position: TablePosition.button,
            startingStack: 10000,
            won: false,
            net: 0,
            foldedOn: null,
            finalRank: HandRank.pair,
            styleLabel: null,
          ),
      ],
      streets: [
        ReplayStreet(
          name: 'Flop',
          round: BettingRound.flop,
          boardAfter: const ['Kd', '7s', '2c'],
          actions: const [],
          potAfter: pot,
          triggers: triggers,
        ),
      ],
      winnerName: 'Ana',
      winnerHand: 'a pair',
      loserName: 'Ben',
      loserHand: 'high card',
      winnerRank: winner,
      loserRank: loser,
      allIn: allIn,
      suckout: suckout,
      reachedRiver: true,
    );

ShowdownEntry _entry(String id) => ShowdownEntry(
      id: id,
      name: id,
      kind: StandingKind.pro,
      wentAllIn: false,
      net: 100,
      rank: HandRank.pair,
    );

HandDigest _digest({
  required int pot,
  HandReplay? replay,
  int showdownPlayers = 2,
  List<String> busted = const [],
  bool humanTable = false,
}) =>
    HandDigest(
      levelIndex: 0,
      tableId: 0,
      pot: pot,
      showdown: [for (var i = 0; i < showdownPlayers; i++) _entry('p$i')],
      winners: const ['p0'],
      busted: busted,
      humanTable: humanTable,
      replay: replay ?? _replay(pot: pot),
    );

/// Feeds hands to a chronicle and reports which one won the replay slot.
String? _featureWinner(List<(String, HandDigest)> hands) {
  final c = TournamentChronicle();
  c.beginLevel(
    {'p0': 10000, 'p1': 10000},
    {'p0': 'p0', 'p1': 'p1'},
    // p0 is the human, so the 'a hand you played' weighting can apply.
    {'p0': StandingKind.human, 'p1': StandingKind.pro},
    {'p0'},
  );
  final byPot = <int, String>{};
  for (final (label, d) in hands) {
    byPot[d.pot] = label;
    c.record(d, avgStack: 10000);
  }
  final recap = c.buildRecap(
    levelJustFinished: 1,
    playersLeft: 2,
    averageStack: 10000,
    bigBlind: 100,
    paidPlaces: 1,
    inMoney: false,
    humanId: 'p0',
    currentChips: {'p0': 10000, 'p1': 10000},
    finishPlaces: const {},
    prizes: const {},
  );
  final chosen = recap.featureHand;
  return chosen == null ? null : byPot[chosen.pot];
}

void main() {
  group('which hand gets narrated', () {
    test('a signature move beats a slightly bigger routine pot', () {
      final winner = _featureWinner([
        ('routine', _digest(pot: 1200)),
        (
          'move',
          _digest(
            pot: 1000,
            replay: _replay(
              pot: 1000,
              triggers: const [
                FiredTrigger('Slow_Play_Trap', 'p0', BettingRound.flop),
              ],
            ),
          ),
        ),
      ]);
      expect(winner, 'move');
    });

    test('a bad beat beats a bigger routine pot', () {
      final winner = _featureWinner([
        ('routine', _digest(pot: 1400)),
        ('suckout', _digest(pot: 1000, replay: _replay(pot: 1000, suckout: true))),
      ]);
      expect(winner, 'suckout');
    });

    test('a knockout beats a bigger routine pot', () {
      final winner = _featureWinner([
        ('routine', _digest(pot: 1300)),
        ('knockout', _digest(pot: 1000, busted: const ['p1'])),
      ]);
      expect(winner, 'knockout');
    });

    test('a cooler beats a bigger one-pair pot', () {
      final winner = _featureWinner([
        ('routine', _digest(pot: 1200)),
        (
          'cooler',
          _digest(
            pot: 1000,
            replay: _replay(
              pot: 1000,
              winner: HandRank.flush,
              loser: HandRank.threeOfAKind,
            ),
          ),
        ),
      ]);
      expect(winner, 'cooler');
    });

    test('pot still dominates — a trivial hand cannot win on flags alone', () {
      // Every bonus at once on a tiny pot still loses to a genuinely huge one.
      final winner = _featureWinner([
        ('huge', _digest(pot: 20000)),
        (
          'small-but-flashy',
          _digest(
            pot: 1000,
            busted: const ['p1'],
            showdownPlayers: 3,
            humanTable: true,
            replay: _replay(
              pot: 1000,
              allIn: true,
              suckout: true,
              winner: HandRank.flush,
              loser: HandRank.straight,
              triggers: const [
                FiredTrigger('Slow_Play_Trap', 'p0', BettingRound.flop),
                FiredTrigger('Sticky_Showdown', 'p1', BettingRound.river),
              ],
            ),
          ),
        ),
      ]);
      expect(winner, 'huge',
          reason: 'interestingness weights the pot, it does not replace it');
    });

    test('with nothing to separate them, the bigger pot wins', () {
      final winner = _featureWinner([
        ('small', _digest(pot: 900)),
        ('big', _digest(pot: 1500)),
      ]);
      expect(winner, 'big');
    });

    test('an interesting hand the player contested outranks a bigger one', () {
      final winner = _featureWinner([
        ('watched', _digest(pot: 1700, humanTable: true)),
        (
          'played',
          _digest(
            pot: 1000,
            humanTable: true,
            busted: const ['p1'],
            replay: _replay(
                pot: 1000, allIn: true, seatIds: const ['p0', 'p1']),
          ),
        ),
      ]);
      expect(winner, 'played',
          reason: 'getting your own big hand analysed is the most useful recap');
    });

    test('but a dull hand does not win the slot just because you were in it',
        () {
      // The human contested it and nothing happened: no bad beat, no knockout,
      // no move, no cooler. Amplifying zero interest leaves it at zero, so the
      // genuinely interesting hand elsewhere still gets the slot.
      final winner = _featureWinner([
        (
          'elsewhere',
          _digest(pot: 1100, replay: _replay(pot: 1100, suckout: true)),
        ),
        (
          'mine-but-dull',
          _digest(pot: 1000, replay: _replay(pot: 1000, seatIds: const ['p0'])),
        ),
      ]);
      expect(winner, 'elsewhere',
          reason: 'your hands should not automatically win — only good ones');
    });

    test('between two equally dull hands, yours does not jump the queue', () {
      final winner = _featureWinner([
        ('bigger', _digest(pot: 1400)),
        (
          'mine',
          _digest(pot: 1000, replay: _replay(pot: 1000, seatIds: const ['p0'])),
        ),
      ]);
      expect(winner, 'bigger');
    });
  });
}
