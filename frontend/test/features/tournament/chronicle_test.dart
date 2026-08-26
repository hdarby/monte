import 'package:flutter_test/flutter_test.dart';
import 'package:monte/core/domain/engine/game.dart' show BettingRound;
import 'package:monte/core/domain/engine/hand_evaluator.dart';
import 'package:monte/features/tournament/domain/tournament_chronicle.dart';
import 'package:monte/features/tournament/domain/tournament_snapshot.dart'
    show StandingKind;

ShowdownEntry _e(
  String id,
  String name,
  int net, {
  bool allIn = false,
  bool aheadOnFlop = false,
  HandRank rank = HandRank.pair,
  StandingKind kind = StandingKind.pro,
}) =>
    ShowdownEntry(
      id: id,
      name: name,
      kind: kind,
      wentAllIn: allIn,
      net: net,
      rank: rank,
      aheadOnFlop: aheadOnFlop,
    );

HandDigest _hand({
  required int pot,
  required List<ShowdownEntry> showdown,
  required List<String> winners,
  List<String> busted = const [],
}) =>
    HandDigest(
      levelIndex: 0,
      tableId: 1,
      pot: pot,
      showdown: showdown,
      winners: winners,
      busted: busted,
    );

void main() {
  // Al & Bo are real personalities; Gen is an anonymous filler; You is human.
  const kinds = <String, StandingKind>{
    'a': StandingKind.pro,
    'b': StandingKind.pro,
    'gen': StandingKind.pro,
    'you': StandingKind.human,
  };
  const names = <String, String>{
    'a': 'Al Pro',
    'b': 'Bo Reg',
    'gen': 'Random Reg',
    'you': 'You',
  };
  const personalities = {'a', 'b'}; // 'gen' is a generated filler

  TournamentChronicle fresh() {
    final c = TournamentChronicle();
    c.beginLevel(
        {'a': 100, 'b': 100, 'gen': 100, 'you': 100}, names, kinds, personalities);
    return c;
  }

  LevelRecap recapOf(
    TournamentChronicle c, {
    required int level,
    required int playersLeft,
    int paidPlaces = 0,
    bool inMoney = false,
    required Map<String, int> currentChips,
    Map<String, int> finishPlaces = const {},
    Map<String, int> prizes = const {},
  }) =>
      c.buildRecap(
        levelJustFinished: level,
        playersLeft: playersLeft,
        averageStack: 100,
        bigBlind: 2,
        paidPlaces: paidPlaces,
        inMoney: inMoney,
        humanId: 'you',
        currentChips: currentChips,
        finishPlaces: finishPlaces,
        prizes: prizes,
      );

  test('intro reports players left and eliminations this level', () {
    final c = fresh();
    // Al busts (removed from active); everyone else survives.
    final recap = recapOf(c,
        level: 1, playersLeft: 3, currentChips: {'b': 150, 'gen': 100, 'you': 150},
        finishPlaces: {'a': 4});
    expect(recap.eliminatedThisLevel, 1);
    expect(recap.intro, contains('3'));
    expect(recap.intro.toLowerCase(), contains('rail'));
  });

  test('busted personalities are named; generated fillers are not', () {
    final c = fresh();
    final recap = recapOf(c,
        level: 1,
        playersLeft: 2,
        currentChips: {'b': 200, 'you': 200},
        finishPlaces: {'a': 3, 'gen': 4});
    final joined = recap.eliminations.join(' ');
    expect(joined, contains('Al Pro')); // full first + last name
    expect(joined, isNot(contains('Random Reg'))); // filler not storied
  });

  test('a personality who cashes has their payout reported', () {
    final c = fresh();
    final recap = recapOf(c,
        level: 5,
        playersLeft: 2,
        paidPlaces: 3,
        inMoney: true,
        currentChips: {'b': 300, 'you': 100},
        finishPlaces: {'a': 3},
        prizes: {'a': 2500});
    expect(recap.eliminations.any((l) => l.contains('Al Pro') && l.contains('2,500')),
        isTrue);
  });

  test('deep-running personalities are hyped with full names', () {
    final c = fresh();
    final recap = recapOf(c,
        level: 2,
        playersLeft: 3,
        currentChips: {'a': 400, 'b': 200, 'gen': 100, 'you': 50});
    expect(recap.risers, isNotEmpty);
    expect(recap.risers.first, contains('Al Pro'));
  });

  test('the previous level leader gets a follow-up next level', () {
    final c = fresh();
    // End of level 1: Al leads.
    recapOf(c, level: 1, playersLeft: 4, currentChips: {
      'a': 300,
      'b': 100,
      'gen': 100,
      'you': 100,
    });
    // Level 2 starts; then ends with Al having busted.
    c.beginLevel({'a': 300, 'b': 100, 'gen': 100, 'you': 100}, names, kinds,
        personalities);
    final recap = recapOf(c,
        level: 2,
        playersLeft: 3,
        currentChips: {'b': 300, 'gen': 100, 'you': 200},
        finishPlaces: {'a': 4});
    expect(recap.leaderFollowUp, isNotNull);
    expect(recap.leaderFollowUp, contains('Al Pro'));
  });

  test('bubble tension appears when the money is near, not when far', () {
    final far = recapOf(fresh(),
        level: 1, playersLeft: 200, paidPlaces: 15,
        currentChips: {'a': 100, 'b': 100, 'gen': 100, 'you': 100});
    expect(far.bubbleLine, isNull);
    final near = recapOf(fresh(),
        level: 6, playersLeft: 17, paidPlaces: 15,
        currentChips: {'a': 100, 'b': 100, 'gen': 100, 'you': 100});
    expect(near.bubbleLine, isNotNull);
  });

  test('biggest pot reports the hands shown down, with full names', () {
    final c = fresh();
    c.record(
      _hand(
        pot: 200,
        winners: ['a'],
        showdown: [
          _e('a', 'Al Pro', 200, allIn: true, rank: HandRank.flush),
          _e('b', 'Bo Reg', -200,
              allIn: true, aheadOnFlop: true, rank: HandRank.threeOfAKind),
        ],
      ),
      avgStack: 100,
    );
    final recap = recapOf(c,
        level: 1, playersLeft: 3, currentChips: {'a': 300, 'gen': 100, 'you': 100});
    final pot = recap.biggestPots.first;
    expect(pot.winnerName, 'Al Pro');
    expect(pot.loserName, 'Bo Reg');
    expect(pot.suckout, isTrue);
  });

  test('the biggest showdown of the level is the one kept for the recap', () {
    final c = fresh();
    HandReplay replay(int pot) => HandReplay(
          pot: pot,
          bigBlind: 100,
          board: const ['Ah', 'Kh', '7h', '2d', '3c'],
          seats: const [
            ReplaySeat(
              playerId: 'a',
              name: 'Al Pro',
              cards: ['Qh', 'Jh'],
              position: TablePosition.button,
              startingStack: 5000,
              won: true,
              net: 5000,
              styleLabel: 'lag',
              foldedOn: null,
              finalRank: HandRank.flush,
            ),
            ReplaySeat(
              playerId: 'b',
              name: 'Bo Reg',
              cards: ['Ad', 'Ac'],
              position: TablePosition.bigBlind,
              startingStack: 5000,
              won: false,
              net: -5000,
              styleLabel: 'nit',
              foldedOn: null,
              finalRank: HandRank.threeOfAKind,
            ),
          ],
          streets: const [
            ReplayStreet(
              name: 'Preflop',
              round: BettingRound.preflop,
              boardAfter: [],
              actions: [],
              potAfter: 600,
            ),
          ],
          winnerName: 'Al Pro',
          winnerHand: 'Flush',
          loserName: 'Bo Reg',
          loserHand: 'Three of a Kind',
          winnerRank: HandRank.flush,
          loserRank: HandRank.threeOfAKind,
          allIn: true,
          suckout: false,
          reachedRiver: true,
        );
    // A small showdown, then a bigger one — the bigger is kept.
    c.record(
      HandDigest(
        levelIndex: 0,
        tableId: 1,
        pot: 400,
        showdown: [_e('a', 'Al Pro', 400), _e('b', 'Bo Reg', -400)],
        winners: const ['a'],
        busted: const [],
        replay: replay(400),
      ),
      avgStack: 100,
    );
    c.record(
      HandDigest(
        levelIndex: 0,
        tableId: 2,
        pot: 5000,
        showdown: [_e('a', 'Al Pro', 5000), _e('b', 'Bo Reg', -5000)],
        winners: const ['a'],
        busted: const [],
        replay: replay(5000),
      ),
      avgStack: 100,
    );
    final recap = recapOf(c,
        level: 1, playersLeft: 3, currentChips: {'a': 500, 'gen': 100, 'you': 100});
    expect(recap.featureHand, isNotNull);
    expect(recap.featureHand!.pot, 5000); // the bigger pot won
    // The chronicle carries the replay through untouched — commentary is added
    // upstream by ReplayBuilder/HandNarrator, which can see the hole cards.
    expect(recap.featureHand!.seats, hasLength(2));
  });

  test('your story reports your swing and best pot of the level', () {
    final c = fresh();
    c.record(
      _hand(
        pot: 120,
        winners: ['you'],
        showdown: [
          _e('you', 'You', 120,
              rank: HandRank.threeOfAKind, kind: StandingKind.human),
          _e('a', 'Al Pro', -120, rank: HandRank.twoPair),
        ],
      ),
      avgStack: 100,
    );
    final recap = recapOf(c,
        level: 1, playersLeft: 3, currentChips: {'b': 100, 'gen': 100, 'you': 220});
    expect(recap.yourStory, contains('up 120'));
    expect(recap.yourStory, contains('set'));
  });

  group('cross-level leaderboard swings', () {
    test('a former chip leader who busts gets a "fallen star" storyline', () {
      final c = fresh();
      // Level 1: Al is the runaway chip leader (rank 1) — sets bestRankEver.
      recapOf(c,
          level: 1,
          playersLeft: 4,
          currentChips: {'a': 500, 'b': 100, 'gen': 100, 'you': 100});
      c.beginLevel({'a': 500, 'b': 100, 'gen': 100, 'you': 100}, names, kinds,
          personalities);
      // Level 2: nothing eventful, Al is still around.
      recapOf(c,
          level: 2,
          playersLeft: 4,
          currentChips: {'a': 500, 'b': 150, 'gen': 100, 'you': 150});
      c.beginLevel({'a': 500, 'b': 150, 'gen': 100, 'you': 150}, names, kinds,
          personalities);
      // Level 3: Al busts, several levels after having led the field.
      final recap = recapOf(c,
          level: 3,
          playersLeft: 3,
          currentChips: {'b': 150, 'gen': 100, 'you': 150},
          finishPlaces: {'a': 50});
      final text = recap.notables.join(' ');
      expect(text, contains('Al Pro'));
      expect(text, contains('as high as 1st'));
      expect(text, contains('50th'));
      // A generated filler never gets this treatment, even if it once led.
      expect(text, isNot(contains('Random Reg')));
    });

    test('a former leader who fades but stays in gets a "faded leader" line, '
        'once', () {
      final c = fresh();
      recapOf(c,
          level: 1,
          playersLeft: 4,
          currentChips: {'a': 500, 'b': 100, 'gen': 100, 'you': 100});
      c.beginLevel({'a': 500, 'b': 100, 'gen': 100, 'you': 100}, names, kinds,
          personalities);
      // Level 2: Al craters to crumbs but survives.
      final level2 = recapOf(c,
          level: 2,
          playersLeft: 4,
          currentChips: {'a': 10, 'b': 300, 'gen': 150, 'you': 150});
      expect(level2.notables.join(' '), contains('Al Pro'));
      expect(level2.notables.join(' '), contains('once cracked the top 100'));

      c.beginLevel({'a': 10, 'b': 300, 'gen': 150, 'you': 150}, names, kinds,
          personalities);
      // Level 3: still crippled — the line does not repeat.
      final level3 = recapOf(c,
          level: 3,
          playersLeft: 4,
          currentChips: {'a': 12, 'b': 300, 'gen': 150, 'you': 150});
      expect(level3.notables.join(' '), isNot(contains('once cracked')));
    });

    test('a genuine multi-level comeback gets "back from the dead", not the '
        'same-level comeback line', () {
      final c = fresh();
      // Level 1 ends with Al crippled.
      recapOf(c,
          level: 1,
          playersLeft: 4,
          currentChips: {'a': 10, 'b': 100, 'gen': 100, 'you': 100});
      c.beginLevel(
          {'a': 10, 'b': 100, 'gen': 100, 'you': 100}, names, kinds, personalities);
      // Level 2 starts crippled (marks wasCrippledEarlier at level 2) and ends
      // still short — too soon for "back from the dead".
      final level2 = recapOf(c,
          level: 2,
          playersLeft: 4,
          currentChips: {'a': 15, 'b': 100, 'gen': 100, 'you': 100});
      expect(level2.notables.join(' '), isNot(contains('down to fumes')));
      c.beginLevel(
          {'a': 15, 'b': 100, 'gen': 100, 'you': 100}, names, kinds, personalities);
      // Level 3: still short, still too soon.
      final level3 = recapOf(c,
          level: 3,
          playersLeft: 4,
          currentChips: {'a': 20, 'b': 100, 'gen': 100, 'you': 100});
      expect(level3.notables.join(' '), isNot(contains('down to fumes')));
      c.beginLevel(
          {'a': 20, 'b': 100, 'gen': 100, 'you': 100}, names, kinds, personalities);
      // Level 4: healthy again, well after the crippling level — the real arc.
      final level4 = recapOf(c,
          level: 4,
          playersLeft: 4,
          currentChips: {'a': 150, 'b': 100, 'gen': 100, 'you': 100});
      final text = level4.notables.join(' ');
      expect(text, contains('Al Pro'));
      expect(text, contains('down to fumes back on level 2'));
      expect(text, contains('clawed all the way back into contention'));
    });
  });

  group('the human is a character in their own tournament', () {
    test('a human wrecking-ball level gets a storyline, in second person', () {
      final c = fresh();
      // Three knockouts for the human across three hands.
      for (var i = 0; i < 3; i++) {
        c.record(
          _hand(
            pot: 300,
            winners: const ['you'],
            showdown: [
              _e('you', 'You', 300, kind: StandingKind.human),
              _e('a', 'Al Pro', -300),
            ],
            busted: const ['a'],
          ),
          avgStack: 100,
        );
      }
      final recap = recapOf(c,
          level: 1, playersLeft: 3, currentChips: {'you': 900, 'b': 100, 'gen': 100});
      final text = recap.notables.join(' ');
      expect(text, contains('You are a wrecking ball'));
      expect(text, isNot(contains('You is')));
    });

    test('the human running deep is listed among the risers', () {
      final c = fresh();
      final recap = recapOf(c,
          level: 1, playersLeft: 3, currentChips: {'you': 900, 'a': 100, 'gen': 100});
      final text = recap.risers.join(' ');
      expect(text, isNotEmpty);
      // Human is chip leader, so they lead the section in second person.
      expect(text, contains('You are'));
      expect(text, isNot(contains('You is')));
    });

    test('a short-stacked human appears among the fallers as "you"', () {
      final c = fresh();
      final recap = recapOf(c,
          level: 1,
          playersLeft: 3,
          currentChips: {'you': 10, 'a': 400, 'gen': 400});
      expect(recap.fallers.join(' '), contains('you'));
    });

    test('the human can be the bounty leader', () {
      final c = fresh();
      for (final victim in ['a', 'b']) {
        c.record(
          _hand(
            pot: 300,
            winners: const ['you'],
            showdown: [
              _e('you', 'You', 300, kind: StandingKind.human),
              _e(victim, 'Victim', -300),
            ],
            busted: [victim],
          ),
          avgStack: 100,
        );
      }
      final recap = recapOf(c,
          level: 1, playersLeft: 2, currentChips: {'you': 700, 'gen': 100});
      expect(recap.bountyLine, isNotNull);
      expect(recap.bountyLine, contains('You have sent'));
    });

    test('a human comeback is reported in second person', () {
      final c = TournamentChronicle();
      // The human starts the level on fumes.
      c.beginLevel(
          {'a': 100, 'b': 100, 'gen': 100, 'you': 2}, names, kinds, personalities);
      final recap = recapOf(c,
          level: 1,
          playersLeft: 4,
          currentChips: {'you': 400, 'a': 100, 'b': 100, 'gen': 100});
      final text = recap.notables.join(' ');
      expect(text, contains('You were left for dead'));
      expect(text, contains('you have clawed'.replaceFirst('you ', '')));
      expect(text, isNot(contains('You was')));
    });

    test('the human cashing is reported alongside the other eliminations', () {
      final c = fresh();
      final recap = recapOf(c,
          level: 1,
          playersLeft: 2,
          currentChips: {'a': 200, 'b': 200},
          finishPlaces: {'you': 3},
          prizes: {'you': 500});
      expect(recap.eliminations.join(' '), contains('You banked'));
    });

    test('no third-person verb ever leaks into a second-person line', () {
      final c = fresh();
      final recap = recapOf(c,
          level: 1, playersLeft: 3, currentChips: {'you': 900, 'a': 50, 'gen': 50});
      final all = [
        recap.intro,
        ...recap.notables,
        ...recap.risers,
        ...recap.fallers,
        ...recap.eliminations,
        recap.bountyLine ?? '',
        recap.yourStory ?? '',
      ].join(' ');
      for (final bad in ['You is', 'You has', 'You was', 'You keeps']) {
        expect(all, isNot(contains(bad)), reason: 'ungrammatical: "$bad"');
      }
    });
  });
}
