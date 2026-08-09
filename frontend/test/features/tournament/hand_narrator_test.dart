import 'package:flutter_test/flutter_test.dart';
import 'package:monte/core/domain/engine/actions.dart';
import 'package:monte/core/domain/engine/game.dart' show BettingRound;
import 'package:monte/core/domain/engine/hand_evaluator.dart';
import 'package:monte/features/tournament/domain/chronicle/hand_narrator.dart';
import 'package:monte/features/tournament/domain/chronicle/hand_replay.dart';

/// Builds a replay by hand so each commentary path can be exercised in
/// isolation. Amounts are in chips with a big blind of 100, so 250 = 2.5bb.
HandReplay _replay({
  required List<ReplaySeat> seats,
  required List<ReplayStreet> streets,
  List<String> board = const ['Kd', '7s', '2c', '9h', '3d'],
  int pot = 4000,
  bool allIn = false,
  bool suckout = false,
  bool reachedRiver = true,
  String? winnerName,
  String? loserName,
}) {
  final winner = seats.firstWhere((s) => s.won, orElse: () => seats.first);
  final loser = seats.firstWhere((s) => !s.won, orElse: () => seats.last);
  return HandReplay(
    pot: pot,
    bigBlind: 100,
    board: board,
    seats: seats,
    streets: streets,
    winnerName: winnerName ?? winner.name,
    winnerHand: winner.finalRank?.label ?? 'the winner',
    loserName: loserName ?? loser.name,
    loserHand: loser.finalRank?.label ?? 'a losing hand',
    winnerRank: winner.finalRank ?? HandRank.highCard,
    loserRank: loser.finalRank ?? HandRank.highCard,
    allIn: allIn,
    suckout: suckout,
    reachedRiver: reachedRiver,
  );
}

ReplaySeat _seat(
  String id,
  String name,
  List<String> cards,
  TablePosition pos, {
  bool won = false,
  int stack = 5000,
  int net = 0,
  String? style,
  BettingRound? foldedOn,
  HandRank? finalRank,
}) => ReplaySeat(
  playerId: id,
  name: name,
  cards: cards,
  position: pos,
  startingStack: stack,
  won: won,
  net: net,
  styleLabel: style,
  foldedOn: foldedOn,
  finalRank: finalRank,
);

ReplayAction _act(
  String id,
  String name,
  TablePosition pos,
  ActionType type,
  BettingRound street, {
  int amount = 0,
  int potBefore = 300,
  int toCall = 0,
}) => ReplayAction(
  playerId: id,
  name: name,
  position: pos,
  type: type,
  street: street,
  amount: amount,
  potBefore: potBefore,
  toCall: toCall,
  isAllIn: false,
);

String _allText(HandReplay r) => [
  for (final s in r.streets) ...s.commentary,
  ...r.commentary,
  for (final v in r.verdicts) v.line,
].join('\n');

void main() {
  group('preflop', () {
    test('calls out a hand that is too loose for the seat', () {
      final r = HandNarrator.narrate(
        _replay(
          seats: [
            // 72o under the gun is indefensible.
            _seat('a', 'Loose Larry', ['7d', '2s'], TablePosition.underTheGun),
            _seat('b', 'Solid Sam', ['Ah', 'Kh'], TablePosition.button,
                won: true),
          ],
          streets: [
            ReplayStreet(
              name: 'Preflop',
              round: BettingRound.preflop,
              boardAfter: const [],
              actions: [
                _act('a', 'Loose Larry', TablePosition.underTheGun,
                    ActionType.raise, BettingRound.preflop,
                    amount: 250),
              ],
              potAfter: 600,
            ),
          ],
        ),
      );
      final text = _allText(r);
      expect(text, contains('Loose Larry'));
      expect(text.toLowerCase(), contains('no business'));
    });

    test('approves a legitimate opening hand', () {
      final r = HandNarrator.narrate(
        _replay(
          seats: [
            _seat('b', 'Solid Sam', ['Ah', 'Kh'], TablePosition.underTheGun,
                won: true),
            _seat('c', 'Bob', ['Qd', 'Qs'], TablePosition.button),
          ],
          streets: [
            ReplayStreet(
              name: 'Preflop',
              round: BettingRound.preflop,
              boardAfter: const [],
              actions: [
                _act('b', 'Solid Sam', TablePosition.underTheGun,
                    ActionType.raise, BettingRound.preflop,
                    amount: 250),
              ],
              potAfter: 600,
            ),
          ],
        ),
      );
      expect(_allText(r).toLowerCase(), contains('no complaints'));
    });

    test('the big blind is never criticised for defending', () {
      final r = HandNarrator.narrate(
        _replay(
          seats: [
            _seat('a', 'Blind Bob', ['7d', '2s'], TablePosition.bigBlind),
            _seat('b', 'Sam', ['Ah', 'Kh'], TablePosition.button, won: true),
          ],
          streets: [
            ReplayStreet(
              name: 'Preflop',
              round: BettingRound.preflop,
              boardAfter: const [],
              actions: const [],
              potAfter: 600,
            ),
          ],
        ),
      );
      expect(_allText(r), contains('defends the big blind'));
    });

    test('reports the stack-to-pot ratio going to the flop', () {
      final r = HandNarrator.narrate(
        _replay(
          seats: [
            _seat('a', 'Ann', ['Ah', 'Kh'], TablePosition.button, won: true),
            _seat('b', 'Bob', ['Qd', 'Qs'], TablePosition.bigBlind),
          ],
          streets: [
            ReplayStreet(
              name: 'Preflop',
              round: BettingRound.preflop,
              boardAfter: const [],
              actions: const [],
              potAfter: 600,
            ),
          ],
        ),
      );
      expect(_allText(r), contains('SPR'));
    });
  });

  group('flop', () {
    ReplayStreet flopStreet(List<ReplayAction> actions) => ReplayStreet(
      name: 'Flop',
      round: BettingRound.flop,
      boardAfter: const ['Kd', '7s', '2c'],
      actions: actions,
      potAfter: 1200,
    );

    test('describes the texture in the six-texture vocabulary', () {
      final r = HandNarrator.narrate(
        _replay(
          seats: [
            _seat('a', 'Ann', ['Ah', 'Kh'], TablePosition.button, won: true),
            _seat('b', 'Bob', ['Qd', 'Qs'], TablePosition.bigBlind),
          ],
          streets: [flopStreet(const [])],
        ),
      );
      final text = _allText(r).toLowerCase();
      // Kd 7s 2c is dry and static.
      expect(text, contains('dry'));
      expect(text, contains('static'));
    });

    test('says who the board favours', () {
      final r = HandNarrator.narrate(
        _replay(
          seats: [
            _seat('a', 'Ann', ['Ah', 'Kh'], TablePosition.button, won: true),
            _seat('b', 'Bob', ['Qd', 'Qs'], TablePosition.bigBlind),
          ],
          streets: [flopStreet(const [])],
        ),
      );
      expect(_allText(r).toLowerCase(), contains('range'));
    });

    test('reads out what every live player is holding', () {
      final r = HandNarrator.narrate(
        _replay(
          seats: [
            _seat('a', 'Ann', ['Ah', 'Kh'], TablePosition.button, won: true),
            _seat('b', 'Bob', ['Qd', 'Qs'], TablePosition.bigBlind),
          ],
          streets: [flopStreet(const [])],
        ),
      );
      final text = _allText(r);
      expect(text, contains('Ann has'));
      expect(text, contains('Bob has'));
    });

    test('recognises a semi-bluff as the right kind of bluff', () {
      final r = HandNarrator.narrate(
        _replay(
          // Jh Th on a two-tone connected board is a real draw.
          board: const ['Qh', '9h', '3s', '2c', '4d'],
          seats: [
            _seat('a', 'Drawer', ['Jh', 'Th'], TablePosition.button),
            _seat('b', 'Bob', ['Ad', 'As'], TablePosition.bigBlind, won: true),
          ],
          streets: [
            ReplayStreet(
              name: 'Flop',
              round: BettingRound.flop,
              boardAfter: const ['Qh', '9h', '3s'],
              actions: [
                _act('a', 'Drawer', TablePosition.button, ActionType.bet,
                    BettingRound.flop,
                    amount: 600, potBefore: 600),
              ],
              potAfter: 1800,
            ),
          ],
        ),
      );
      expect(_allText(r).toLowerCase(), contains('semi-bluff'));
    });
  });

  group('bluff evaluation', () {
    test('endorses a well-chosen heads-up bluff in position', () {
      final r = HandNarrator.narrate(
        _replay(
          board: const ['Ad', 'Kc', '4s', '9h', '2d'],
          seats: [
            // Air, but heads-up, in position, on an ace-high board.
            _seat('a', 'Bluffer', ['7c', '5d'], TablePosition.button,
                won: true),
            _seat('b', 'Folder', ['Th', 'Ts'], TablePosition.bigBlind,
                foldedOn: BettingRound.turn),
          ],
          streets: [
            ReplayStreet(
              name: 'Turn',
              round: BettingRound.turn,
              boardAfter: const ['Ad', 'Kc', '4s', '9h'],
              actions: [
                _act('a', 'Bluffer', TablePosition.button, ActionType.bet,
                    BettingRound.turn,
                    amount: 1600, potBefore: 2000),
              ],
              potAfter: 3600,
            ),
          ],
        ),
      );
      expect(_allText(r), contains('time and the place'));
    });

    test('criticises a small multiway bluff out of position', () {
      final r = HandNarrator.narrate(
        _replay(
          board: const ['Ad', 'Kc', '4s', '9h', '3d'],
          seats: [
            // Seven-high with no outs against two overpairs: pure air.
            _seat('a', 'Bluffer', ['7c', '5d'], TablePosition.smallBlind),
            _seat('b', 'Caller', ['Th', 'Ts'], TablePosition.button,
                won: true),
            _seat('c', 'Third', ['Jd', 'Jc'], TablePosition.cutoff),
          ],
          streets: [
            ReplayStreet(
              name: 'Turn',
              round: BettingRound.turn,
              boardAfter: const ['Ad', 'Kc', '4s', '9h'],
              actions: [
                _act('a', 'Bluffer', TablePosition.smallBlind, ActionType.bet,
                    BettingRound.turn,
                    amount: 300, potBefore: 2000),
              ],
              potAfter: 2300,
            ),
          ],
        ),
      );
      final text = _allText(r);
      expect(text, contains('do not love it'));
      expect(text, contains('players to get through'));
    });
  });

  group('verdicts', () {
    test('gives every player who saw the flop a verdict', () {
      final r = HandNarrator.narrate(
        _replay(
          seats: [
            _seat('a', 'Ann', ['Ah', 'Kh'], TablePosition.button,
                won: true, finalRank: HandRank.pair),
            _seat('b', 'Bob', ['Qd', 'Qs'], TablePosition.bigBlind,
                finalRank: HandRank.pair),
            _seat('c', 'Chen', ['5d', '4s'], TablePosition.cutoff,
                foldedOn: BettingRound.flop),
          ],
          streets: [
            ReplayStreet(
              name: 'Preflop',
              round: BettingRound.preflop,
              boardAfter: const [],
              actions: const [],
              potAfter: 600,
            ),
          ],
        ),
      );
      expect(r.verdicts, hasLength(3));
      expect(
        r.verdicts.map((v) => v.name),
        containsAll(['Ann', 'Bob', 'Chen']),
      );
      for (final v in r.verdicts) {
        expect(v.line, isNotEmpty);
      }
    });

    test('credits three streets of value as a perfect hand', () {
      ReplayStreet betting(String label, BettingRound round, List<String> b) =>
          ReplayStreet(
            name: label,
            round: round,
            boardAfter: b,
            actions: [
              _act('a', 'Ann', TablePosition.button, ActionType.bet, round,
                  amount: 600, potBefore: 600),
            ],
            potAfter: 1800,
          );
      final r = HandNarrator.narrate(
        _replay(
          seats: [
            _seat('a', 'Ann', ['Kh', 'Ks'], TablePosition.button,
                won: true, net: 4000, finalRank: HandRank.threeOfAKind),
            _seat('b', 'Bob', ['Qd', 'Qs'], TablePosition.bigBlind,
                finalRank: HandRank.pair),
          ],
          streets: [
            betting('Flop', BettingRound.flop, const ['Kd', '7s', '2c']),
            betting('Turn', BettingRound.turn, const ['Kd', '7s', '2c', '9h']),
            betting(
                'River', BettingRound.river, const ['Kd', '7s', '2c', '9h', '3d']),
          ],
        ),
      );
      final ann = r.verdicts.firstWhere((v) => v.name == 'Ann');
      expect(ann.grade, VerdictGrade.excellent);
      expect(ann.line, contains('perfectly'));
    });

    test('marks a player who was bluffed off the best hand', () {
      final r = HandNarrator.narrate(
        _replay(
          board: const ['Ad', 'Kc', '4s', '9h', '2d'],
          seats: [
            _seat('a', 'Bluffer', ['7c', '5d'], TablePosition.button,
                won: true),
            // Tens are ahead of seven-high but fold.
            _seat('b', 'Folder', ['Th', 'Ts'], TablePosition.bigBlind,
                foldedOn: BettingRound.turn),
          ],
          streets: [
            ReplayStreet(
              name: 'Turn',
              round: BettingRound.turn,
              boardAfter: const ['Ad', 'Kc', '4s', '9h'],
              actions: [
                _act('a', 'Bluffer', TablePosition.button, ActionType.bet,
                    BettingRound.turn,
                    amount: 1600, potBefore: 2000),
                _act('b', 'Folder', TablePosition.bigBlind, ActionType.fold,
                    BettingRound.turn),
              ],
              potAfter: 3600,
            ),
          ],
        ),
      );
      final folder = r.verdicts.firstWhere((v) => v.name == 'Folder');
      expect(folder.line, contains('bluffed off'));
      expect(folder.grade, VerdictGrade.questionable);
    });

    test('treats a suckout loser as unlucky, not bad', () {
      final r = HandNarrator.narrate(
        _replay(
          suckout: true,
          allIn: true,
          seats: [
            _seat('a', 'Lucky', ['7c', '5d'], TablePosition.button,
                won: true, finalRank: HandRank.straight),
            _seat('b', 'Victim', ['Ah', 'As'], TablePosition.bigBlind,
                finalRank: HandRank.threeOfAKind),
          ],
          streets: [
            ReplayStreet(
              name: 'Preflop',
              round: BettingRound.preflop,
              boardAfter: const [],
              actions: const [],
              potAfter: 600,
            ),
          ],
          winnerName: 'Lucky',
          loserName: 'Victim',
        ),
      );
      final victim = r.verdicts.firstWhere((v) => v.name == 'Victim');
      expect(victim.grade, VerdictGrade.unlucky);
      expect(victim.line.toLowerCase(), contains('ignore the result'));
    });
  });

  group('summary', () {
    test('names the street where the pot actually got big', () {
      final r = HandNarrator.narrate(
        _replay(
          pot: 10000,
          seats: [
            _seat('a', 'Ann', ['Kh', 'Ks'], TablePosition.button,
                won: true, finalRank: HandRank.threeOfAKind),
            _seat('b', 'Bob', ['Qd', 'Qs'], TablePosition.bigBlind,
                finalRank: HandRank.pair),
          ],
          streets: [
            ReplayStreet(
              name: 'Preflop',
              round: BettingRound.preflop,
              boardAfter: const [],
              actions: const [],
              potAfter: 600,
            ),
            ReplayStreet(
              name: 'Turn',
              round: BettingRound.turn,
              boardAfter: const ['Kd', '7s', '2c', '9h'],
              actions: const [],
              potAfter: 9000,
            ),
          ],
        ),
      );
      expect(r.commentary.join(' '), contains('turned on the turn'));
    });

    test('is deterministic — the same hand always gets the same words', () {
      HandReplay build() => _replay(
        seats: [
          _seat('a', 'Ann', ['Ah', 'Kh'], TablePosition.button, won: true),
          _seat('b', 'Bob', ['Qd', 'Qs'], TablePosition.bigBlind),
        ],
        streets: [
          ReplayStreet(
            name: 'Preflop',
            round: BettingRound.preflop,
            boardAfter: const [],
            actions: const [],
            potAfter: 600,
          ),
        ],
      );
      expect(
        _allText(HandNarrator.narrate(build())),
        _allText(HandNarrator.narrate(build())),
      );
    });

    test('never leaves a street without a read', () {
      final r = HandNarrator.narrate(
        _replay(
          seats: [
            _seat('a', 'Ann', ['Ah', 'Kh'], TablePosition.button, won: true),
            _seat('b', 'Bob', ['Qd', 'Qs'], TablePosition.bigBlind),
          ],
          streets: [
            ReplayStreet(
              name: 'Preflop',
              round: BettingRound.preflop,
              boardAfter: const [],
              actions: const [],
              potAfter: 600,
            ),
            ReplayStreet(
              name: 'Flop',
              round: BettingRound.flop,
              boardAfter: const ['Kd', '7s', '2c'],
              actions: const [],
              potAfter: 600,
            ),
            ReplayStreet(
              name: 'Turn',
              round: BettingRound.turn,
              boardAfter: const ['Kd', '7s', '2c', '9h'],
              actions: const [],
              potAfter: 600,
            ),
            ReplayStreet(
              name: 'River',
              round: BettingRound.river,
              boardAfter: const ['Kd', '7s', '2c', '9h', '3d'],
              actions: const [],
              potAfter: 600,
            ),
          ],
        ),
      );
      for (final s in r.streets) {
        expect(s.commentary, isNotEmpty, reason: '${s.name} had no commentary');
      }
      expect(r.commentary, isNotEmpty);
    });
  });

  group('regressions', () {
    test('a failed bluff is not described as paying it off', () {
      final r = HandNarrator.narrate(
        _replay(
          board: const ['Qh', '7h', '2d', '4h', '8s'],
          seats: [
            _seat('c', 'Chen', ['Jh', 'Th'], TablePosition.cutoff,
                won: true, net: 5400, finalRank: HandRank.flush),
            // Ann bets the river with one pair and gets called.
            _seat('a', 'Ann', ['Ah', 'Kd'], TablePosition.button,
                net: -3600, finalRank: HandRank.pair),
          ],
          streets: [
            ReplayStreet(
              name: 'River',
              round: BettingRound.river,
              boardAfter: const ['Qh', '7h', '2d', '4h', '8s'],
              actions: [
                _act('a', 'Ann', TablePosition.button, ActionType.bet,
                    BettingRound.river, amount: 2275, potBefore: 6250),
                _act('c', 'Chen', TablePosition.cutoff, ActionType.call,
                    BettingRound.river,
                    amount: 2275, potBefore: 8525, toCall: 2275),
              ],
              potAfter: 10800,
            ),
          ],
        ),
      );
      final ann = r.verdicts.firstWhere((v) => v.name == 'Ann');
      expect(ann.line, isNot(contains('paid it off')));
      expect(ann.line, contains('never folding'));
    });

    test('a winner who never bet is not credited with extraction', () {
      final r = HandNarrator.narrate(
        _replay(
          pot: 10800,
          board: const ['Qh', '7h', '2d', '4h', '8s'],
          seats: [
            _seat('c', 'Chen', ['Jh', 'Th'], TablePosition.cutoff,
                won: true, net: 5400, finalRank: HandRank.flush),
            _seat('a', 'Ann', ['Ah', 'Kd'], TablePosition.button,
                net: -3600, finalRank: HandRank.pair),
          ],
          streets: [
            ReplayStreet(
              name: 'River',
              round: BettingRound.river,
              boardAfter: const ['Qh', '7h', '2d', '4h', '8s'],
              actions: [
                _act('c', 'Chen', TablePosition.cutoff, ActionType.call,
                    BettingRound.river,
                    amount: 2275, potBefore: 8525, toCall: 2275),
              ],
              potAfter: 10800,
            ),
          ],
        ),
      );
      final summary = r.commentary.join(' ');
      expect(summary, isNot(contains('Full marks')));
      expect(summary, contains('let the opponent do all the betting'));
    });

    test('nothing is "drawing dead" on the river — there is no draw left', () {
      final r = HandNarrator.narrate(
        _replay(
          board: const ['Qh', '7h', '2d', '4h', '8s'],
          seats: [
            _seat('c', 'Chen', ['Jh', 'Th'], TablePosition.cutoff,
                won: true, finalRank: HandRank.flush),
            _seat('a', 'Ann', ['Ah', 'Kd'], TablePosition.button,
                finalRank: HandRank.pair),
          ],
          streets: [
            ReplayStreet(
              name: 'River',
              round: BettingRound.river,
              boardAfter: const ['Qh', '7h', '2d', '4h', '8s'],
              actions: const [],
              potAfter: 10800,
            ),
          ],
        ),
      );
      final river = r.streets.firstWhere((s) => s.name == 'River');
      final text = river.commentary.join(' ');
      expect(text, isNot(contains('drawing dead')));
      expect(text, contains('beaten by Chen'));
    });

    test('two overcards count as live, not as a hand drawing thin', () {
      final r = HandNarrator.narrate(
        _replay(
          board: const ['Qh', '7s', '2d', '4c', '8s'],
          seats: [
            _seat('b', 'Bo', ['9s', '9c'], TablePosition.bigBlind,
                won: true, finalRank: HandRank.pair),
            _seat('a', 'Ann', ['Ah', 'Kd'], TablePosition.button,
                finalRank: HandRank.highCard),
          ],
          streets: [
            ReplayStreet(
              name: 'Flop',
              round: BettingRound.flop,
              boardAfter: const ['Qh', '7s', '2d'],
              actions: const [],
              potAfter: 2250,
            ),
          ],
        ),
      );
      final flop = r.streets.firstWhere((s) => s.name == 'Flop');
      final annLine =
          flop.commentary.firstWhere((l) => l.startsWith('Ann has'));
      // AK has six outs to beat 99 — that is live, not thin.
      expect(annLine, contains('live with 6 outs'));
    });

    test('the rule of 4 is corrected for large out counts', () {
      final r = HandNarrator.narrate(
        _replay(
          board: const ['Qh', '7h', '2d', '4h', '8s'],
          seats: [
            _seat('c', 'Chen', ['Jh', 'Th'], TablePosition.cutoff,
                won: true, finalRank: HandRank.flush),
            _seat('b', 'Bo', ['9s', '9c'], TablePosition.bigBlind,
                finalRank: HandRank.pair),
          ],
          streets: [
            ReplayStreet(
              name: 'Flop',
              round: BettingRound.flop,
              boardAfter: const ['Qh', '7h', '2d'],
              actions: const [],
              potAfter: 2250,
            ),
          ],
        ),
      );
      final flop = r.streets.firstWhere((s) => s.name == 'Flop');
      final line = flop.commentary.firstWhere((l) => l.startsWith('Chen has'));
      // 15 outs: naive rule-of-4 says 60%, the corrected figure is 53%.
      expect(line, contains('15 outs'));
      expect(line, contains('53%'));
      expect(line, isNot(contains('60%')));
    });
  });
}
