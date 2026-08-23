import 'package:flutter_test/flutter_test.dart';
import 'package:monte/core/domain/ai/player_read.dart';
import 'package:monte/core/domain/ai/player_stats.dart';

/// Live reads are kept apart from the historical tags because the two decay
/// differently: a tag is a hundred hands of evidence, a live flag can be true
/// this orbit and false the next. Presenting them alike would make the volatile
/// ones look as settled as the durable ones.
void main() {
  test('a seat read defaults to no live flags', () {
    final r = SeatRead(mine: PlayerRead.of(PlayerStats()));
    expect(r.live, isEmpty);
  });

  test('each live kind is distinguishable, for colouring', () {
    const reads = [
      LiveRead('steaming', LiveReadKind.tilt),
      LiveRead('running hot', LiveReadKind.rush),
      LiveRead('has your number', LiveReadKind.danger),
    ];
    expect(reads.map((l) => l.kind).toSet(), hasLength(3));
  });

  test('every live kind has a distinct colour slot', () {
    // The card switches exhaustively on kind, so a new one must be handled.
    expect(LiveReadKind.values, hasLength(4));
  });

  group('the blind and 3-bet tags', () {
    PlayerStats stats({
      double foldBlind = 0.55,
      double fold3 = 0.55,
      int hands = 200,
    }) {
      final s = PlayerStats()
        ..hands = hands.toDouble()
        ..blindStealFaced = 100
        ..foldBlindSteal = foldBlind * 100
        ..faced3bet = 100
        ..foldTo3bet = fold3 * 100;
      return s;
    }

    test('a blind that cannot be stolen is worth knowing about', () {
      expect(PlayerRead.of(stats(foldBlind: 0.25)).tags,
          contains('defends blinds hard'));
      expect(PlayerRead.of(stats(foldBlind: 0.85)).tags,
          contains('folds blinds to steals'));
    });

    test('3-bet folding is reported at both extremes', () {
      expect(PlayerRead.of(stats(fold3: 0.80)).tags,
          contains('overfolds to 3-bets'));
      expect(PlayerRead.of(stats(fold3: 0.20)).tags,
          contains('never folds to a 3-bet'));
    });

    test('the limp gap is read from VPIP minus PFR', () {
      PlayerStats gap(double vpip, double pfr) => PlayerStats()
        ..hands = 200
        ..vpip = vpip * 200
        ..pfr = pfr * 200;
      expect(PlayerRead.of(gap(0.42, 0.14)).tags, contains('limps a lot'));
      expect(PlayerRead.of(gap(0.22, 0.19)).tags, contains('raise or fold'));
    });

    test('squeezing is reported at both extremes', () {
      PlayerStats sq(double rate) => PlayerStats()
        ..hands = 200
        ..squeezeOpp = 100
        ..squeeze = rate * 100;
      expect(PlayerRead.of(sq(0.14)).tags, contains('squeezes light'));
      expect(PlayerRead.of(sq(0.0)).tags, contains('never squeezes'));
    });

    test('a thin sample claims neither', () {
      expect(PlayerRead.of(stats(foldBlind: 0.25, hands: 10)).tags, isEmpty);
    });
  });
}
