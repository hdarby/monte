import 'package:monte/core/domain/engine/actions.dart';
import 'package:monte/core/domain/engine/game.dart';
import 'package:monte/core/domain/engine/player.dart';

/// Maps No-Limit Hold'em's continuous bet space down to a small, discrete menu
/// of candidate actions, so the search tree stays tractable.
///
/// The menu is: fold (only when facing a bet), the passive action (check or
/// call), a bet/raise to each configured fraction of the pot, and an all-in.
/// Every action returned is legal for the player at the given position — the
/// engine's own [PokerGame.minRaiseTo]/[PokerGame.maxRaiseTo] bounds are applied
/// and duplicate sizes are collapsed.
class ActionAbstraction {
  const ActionAbstraction({
    this.potFractions = const [0.5, 0.75, 1.0],
    this.includeAllIn = true,
  });

  /// Bet/raise sizes as fractions of the current pot (added on top of the
  /// amount needed to call). Personality can widen or narrow this later.
  final List<double> potFractions;

  /// Whether to always offer a shove (bet/raise to the entire stack).
  final bool includeAllIn;

  /// The discrete set of candidate actions for [p] at [game]'s current position.
  List<GameAction> actionsFor(PokerGame game, Player p) {
    final actions = <GameAction>[];
    final toCall = game.callAmount(p);

    // Folding is only meaningful when there's a bet to face; folding when you
    // could check for free is strictly dominated, so we never offer it.
    if (toCall > 0) actions.add(const GameAction.fold());

    // The passive action.
    actions.add(
      toCall == 0 ? const GameAction.check() : const GameAction.call(),
    );

    // Aggressive actions, only if the player can actually put in more than the
    // current bet (i.e. has chips beyond a call).
    final maxTo = game.maxRaiseTo(p);
    if (maxTo > game.currentBet) {
      final minTo = game.minRaiseTo(p);
      final isBet = game.currentBet == 0;
      final seen = <int>{};

      for (final f in potFractions) {
        final target = (game.currentBet + game.pot * f).round().clamp(
          minTo,
          maxTo,
        );
        // Skip sizes that collapse onto an all-in (handled below) or duplicate
        // an already-offered size.
        if (target < maxTo && seen.add(target)) {
          actions.add(
            isBet ? GameAction.bet(target) : GameAction.raise(target),
          );
        }
      }

      if (includeAllIn) {
        actions.add(isBet ? GameAction.bet(maxTo) : GameAction.raise(maxTo));
      }
    }

    return actions;
  }
}
