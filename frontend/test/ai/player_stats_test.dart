import 'package:flutter_test/flutter_test.dart';
import 'package:monte/core/domain/ai/player_stats.dart';
import 'package:monte/core/domain/engine/actions.dart';
import 'package:monte/core/domain/engine/game.dart';
import 'package:monte/core/domain/hand_history.dart';

/// Builds a 6-handed hand with the button at seat 0, so seats are
/// [BTN, SB, BB, UTG, MP, CO] at indices 0..5.
HandHistory _hand(List<ActionRecord> actions, {List<String> board = const []}) {
  const ids = ['btn', 'sb', 'bb', 'utg', 'mp', 'co'];
  return HandHistory(
    handNumber: 1,
    smallBlind: 50,
    bigBlind: 100,
    players: [
      for (var i = 0; i < ids.length; i++)
        HandPlayer(
          id: ids[i],
          name: ids[i],
          startingStack: 10000,
          holeCards: const [],
          isButton: i == 0,
          revealed: false,
        ),
    ],
    actions: actions,
    board: board,
    results: const [],
    finalStacks: const {},
  );
}

ActionRecord _a(String id, ActionType t, {int amount = 0, BettingRound street = BettingRound.preflop}) =>
    ActionRecord(playerId: id, street: street, type: t, amount: amount, potAfter: 0);

PlayerStats _statsFor(HandHistory h, String id) {
  final book = PlayerStatsBook();
  book.observe(h, (seat) => seat); // identity = seat id
  return book.read(id)!;
}

void main() {
  test('a late-position steal and a blind fold to it are recorded', () {
    // UTG/MP fold, CO opens (steal), folds around, BB folds to the steal.
    final h = _hand([
      _a('utg', ActionType.fold),
      _a('mp', ActionType.fold),
      _a('co', ActionType.raise, amount: 300),
      _a('btn', ActionType.fold),
      _a('sb', ActionType.fold),
      _a('bb', ActionType.fold),
    ]);
    final co = _statsFor(h, 'co');
    expect(co.steal, 1);
    expect(co.stealOpp, 1);
    expect(co.pfr, 1);
    expect(co.vpip, 1);

    final bb = _statsFor(h, 'bb');
    expect(bb.blindStealFaced, 1);
    expect(bb.foldBlindSteal, 1);
    expect(bb.vpip, 0);
  });

  test('a 3-bet and the opener folding to it are recorded', () {
    // UTG opens, CO 3-bets, UTG folds.
    final h = _hand([
      _a('utg', ActionType.raise, amount: 300),
      _a('mp', ActionType.fold),
      _a('co', ActionType.raise, amount: 900),
      _a('btn', ActionType.fold),
      _a('sb', ActionType.fold),
      _a('bb', ActionType.fold),
      _a('utg', ActionType.fold),
    ]);
    final co = _statsFor(h, 'co');
    expect(co.threeBet, 1);
    expect(co.threeBetOpp, 1);

    final utg = _statsFor(h, 'utg');
    expect(utg.pfr, 1);
    expect(utg.faced3bet, 1);
    expect(utg.foldTo3bet, 1);
  });

  test('a squeeze over an open and a caller is recorded', () {
    // UTG opens, MP calls, BTN squeezes.
    final h = _hand([
      _a('utg', ActionType.raise, amount: 300),
      _a('mp', ActionType.call, amount: 300),
      _a('co', ActionType.fold),
      _a('btn', ActionType.raise, amount: 1200),
      _a('sb', ActionType.fold),
      _a('bb', ActionType.fold),
      _a('utg', ActionType.fold),
      _a('mp', ActionType.fold),
    ]);
    final btn = _statsFor(h, 'btn');
    expect(btn.squeeze, 1);
    expect(btn.squeezeOpp, 1);
    expect(btn.threeBet, 1); // a squeeze is also a 3-bet
  });

  test('a preflop aggressor c-bets the flop; a caller folds to it', () {
    final h = _hand([
      _a('co', ActionType.raise, amount: 300),
      _a('btn', ActionType.fold),
      _a('sb', ActionType.fold),
      _a('bb', ActionType.call, amount: 200),
      _a('utg', ActionType.fold),
      _a('mp', ActionType.fold),
      // Flop: BB checks, CO (preflop aggressor) c-bets, BB folds.
      _a('bb', ActionType.check, street: BettingRound.flop),
      _a('co', ActionType.bet, amount: 250, street: BettingRound.flop),
      _a('bb', ActionType.fold, street: BettingRound.flop),
    ], board: ['Ah', '7d', '2c']);
    final co = _statsFor(h, 'co');
    expect(co.cbet, 1);
    expect(co.cbetOpp, 1);

    final bb = _statsFor(h, 'bb');
    expect(bb.cbetFaced, 1);
    expect(bb.foldToCbet, 1);
  });

  test('reads accumulate over repeated hands and stay recency-weighted', () {
    final book = PlayerStatsBook();
    HandHistory steal() => _hand([
          _a('utg', ActionType.fold),
          _a('mp', ActionType.fold),
          _a('co', ActionType.raise, amount: 300),
          _a('btn', ActionType.fold),
          _a('sb', ActionType.fold),
          _a('bb', ActionType.fold),
        ]);
    for (var i = 0; i < 20; i++) {
      book.observe(steal(), (seat) => seat);
    }
    final co = book.read('co')!;
    // The read has firmed up (many observed hands) and CO looks like a stealer.
    expect(co.hands, greaterThan(10));
    expect(co.confidence, greaterThan(0.4));
    expect(co.stealRate, greaterThan(0.7)); // shrinkage prior keeps it < 1
    // Recency decay bounds the running total (it never grows to 20).
    expect(co.hands, lessThan(20));
  });

  test('the human is read per-observer, not as a shared global', () {
    // btn is the human and opens (steal); co is a real personality, bb a
    // generated filler; both observe the human this hand.
    final h = _hand([
      _a('utg', ActionType.fold),
      _a('mp', ActionType.fold),
      _a('co', ActionType.fold),
      _a('btn', ActionType.raise, amount: 300),
      _a('sb', ActionType.fold),
      _a('bb', ActionType.fold),
    ]);
    final book = PlayerStatsBook();
    book.observe(h, (seat) {
      switch (seat) {
        case 'btn':
          return PlayerStatsBook.humanIdentity;
        case 'co':
          return 'proX';
        case 'bb':
          return 'gen:seat3';
        default:
          return null;
      }
    });
    // The `human` key is the human's own self-view (their HUD stats)...
    expect(book.read(PlayerStatsBook.humanIdentity)!.pfr, 1);
    // ...and each observer separately holds its own impression of the open.
    expect(book.read(PlayerStatsBook.meKey('proX'))!.pfr, 1);
    expect(book.read(PlayerStatsBook.meKey('gen:seat3'))!.pfr, 1);
    // A seat that folded pre and never shared a decision still counts the hand.
    expect(book.read(PlayerStatsBook.meKey('proX'))!.hands, 1);

    // Persistence keeps the durable personality + its read of the human, and
    // drops everything about the generated filler.
    final persist = book.persistable();
    expect(persist.read('proX'), isNotNull);
    expect(persist.read(PlayerStatsBook.meKey('proX')), isNotNull);
    expect(persist.read('gen:seat3'), isNull);
    expect(persist.read(PlayerStatsBook.meKey('gen:seat3')), isNull);
  });

  test('json round-trips the book', () {
    final book = PlayerStatsBook();
    book.observe(
      _hand([
        _a('co', ActionType.raise, amount: 300),
        _a('btn', ActionType.fold),
        _a('sb', ActionType.fold),
        _a('bb', ActionType.fold),
        _a('utg', ActionType.fold),
        _a('mp', ActionType.fold),
      ]),
      (seat) => seat,
    );
    final restored = PlayerStatsBook.decode(book.encode());
    expect(restored.read('co')!.pfr, 1);
    expect(restored.read('co')!.steal, 1);
  });
}
