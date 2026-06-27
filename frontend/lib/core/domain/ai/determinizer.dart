import 'dart:math';

import 'package:monte/core/domain/engine/card.dart';
import 'package:monte/core/domain/engine/game.dart';
import 'package:monte/core/domain/engine/player.dart';

/// Samples a plausible hidden world consistent with what one player (the "hero")
/// can see, turning the imperfect-information game into a concrete one the
/// engine can play forward. This is the determinization step of ISMCTS.
///
/// The hero keeps their real hole cards and the real board; every other player
/// still in the hand is dealt fresh hole cards drawn uniformly from the cards
/// the hero cannot see, and the remaining undealt cards (the future board) are
/// the rest, shuffled. Folded players are excluded — they never reach showdown.
///
/// Baseline sampling is uniform; range-weighted sampling (using betting history
/// and opponent models) can replace the pool draw later without touching the
/// search.
class Determinizer {
  Determinizer({Random? random}) : _random = random ?? Random();

  final Random _random;

  /// Returns a determinized clone of [game] from [hero]'s perspective.
  PokerGame determinize(PokerGame game, Player hero) {
    final clone = game.clone();
    final heroClone = clone.players.firstWhere((p) => p.id == hero.id);

    // Everything the hero can see is off the table for sampling.
    final known = <Card>{...heroClone.hole, ...clone.board};
    final pool = [
      for (final suit in Suit.values)
        for (final rank in Rank.values)
          if (!known.contains(Card(rank, suit))) Card(rank, suit),
    ]..shuffle(_random);

    var next = 0;
    for (final p in clone.players) {
      if (p.id == hero.id) continue;
      p.hole.clear();
      if (p.inHand) {
        p.hole
          ..add(pool[next++])
          ..add(pool[next++]);
      }
    }

    // The unused remainder becomes the future board (burns + community cards).
    clone.loadRemainingDeck(pool.sublist(next));
    return clone;
  }
}
