import 'dart:math';

import 'package:monte/core/domain/engine/card.dart';
import 'package:monte/core/domain/engine/game.dart';
import 'package:monte/core/domain/engine/hand_strength.dart';

/// A plausible set of two-card holdings a villain could have — the "range" a
/// player reasons about. Pure data; no engine mutation.
///
/// v1 is an unweighted set built by taking the strongest fraction of starting
/// hands (ranked by [HandStrength.preflopOf], the baked equity table), which
/// models "a villain of this tightness entered with these hands". Betting is
/// folded in by [narrowedBy], which tightens the set as the pot escalates.
/// Combo *weights* and board-filtered postflop ranges are future refinements.
class HandRange {
  /// Combos ordered strongest-first when built via [top]; order is irrelevant
  /// for equity but lets [narrowedBy] slice off the strongest fraction.
  const HandRange(this.combos);

  final List<(Card, Card)> combos;

  bool get isEmpty => combos.isEmpty;
  int get length => combos.length;

  /// Every two-card combo excluding [dead] (the hero's holes + the board).
  factory HandRange.all({Set<Card> dead = const {}}) =>
      HandRange(_combos(dead));

  /// The strongest [fraction] (in `(0,1]`) of all combos by preflop equity —
  /// i.e. a villain who continues with roughly the top `fraction` of hands.
  factory HandRange.top(double fraction, {Set<Card> dead = const {}}) {
    final all = _combos(dead)
      ..sort((a, b) => HandStrength.preflopOf(b.$1, b.$2)
          .compareTo(HandStrength.preflopOf(a.$1, a.$2)));
    final n = (all.length * fraction.clamp(0.0, 1.0)).round().clamp(1, all.length);
    return HandRange(all.sublist(0, n));
  }

  /// A tighter range reflecting shown aggression: each raise this street and
  /// each street past the flop trims the range toward its strongest hands.
  /// Assumes a ranked range (built via [top]).
  HandRange narrowedBy({int raiseCount = 0, BettingRound? street}) {
    // Each bet/raise this street tightens the range hard (a villain who puts in
    // money is far stronger than their preflop continuing range).
    var factor = pow(0.5, max(0, raiseCount)).toDouble();
    if (street == BettingRound.turn) factor *= 0.85;
    if (street == BettingRound.river) factor *= 0.7;
    final n = (combos.length * factor).round().clamp(1, combos.length);
    return HandRange(combos.sublist(0, n));
  }

  static List<(Card, Card)> _combos(Set<Card> dead) {
    final live = [
      for (final suit in Suit.values)
        for (final rank in Rank.values)
          if (!dead.contains(Card(rank, suit))) Card(rank, suit),
    ];
    final out = <(Card, Card)>[];
    for (var i = 0; i < live.length; i++) {
      for (var j = i + 1; j < live.length; j++) {
        out.add((live[i], live[j]));
      }
    }
    return out;
  }
}
