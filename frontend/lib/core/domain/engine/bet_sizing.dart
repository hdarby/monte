/// The arithmetic every policy uses to turn a *decision about size* into a legal
/// chip amount.
///
/// This existed as an identical six-line closure copy-pasted into six policies
/// (`BotStrategy`, `ProfilePolicy`, `AmateurPolicy` twice, `PersonalityPolicy`
/// twice, `ProfilePostflopPolicy`). That duplication is the reason bet sizing
/// was hard to find and hard to change: there was no single place to look, so
/// the *interesting* question — what size, and why — was buried in six copies of
/// the *boring* one, how to snap and clamp it.
///
/// Nothing here decides a size. It converts one to chips, snaps it to a
/// human-looking denomination ([snapBet]) and clamps it legal. The judgement
/// lives in the callers, and — for preflop opens — in `OpenSizing`.
library;

import 'package:monte/core/domain/engine/bet_snap.dart';
import 'package:monte/core/domain/engine/game.dart';
import 'package:monte/core/domain/engine/player.dart';

/// Raise **to** [potFraction] of the pot on top of the minimum legal raise.
///
/// Note this is not "a bet of `potFraction × pot`": the minimum raise is already
/// baked in, which is why a `0.5` preflop produces 2.75 BB rather than 0.75 BB.
int potRaiseTo(PokerGame game, Player p, double potFraction) {
  final raw = game.minRaiseTo(p) + (game.pot * potFraction).round();
  return snapBet(raw, smallBlind: game.smallBlind, bigBlind: game.bigBlind)
      .clamp(game.minRaiseTo(p), game.maxRaiseTo(p));
}

/// Bet [potFraction] of the pot when there is nothing to call.
int potBetTo(PokerGame game, Player p, double potFraction) {
  final raw = p.currentBet + (game.pot * potFraction).round();
  return snapBet(raw, smallBlind: game.smallBlind, bigBlind: game.bigBlind)
      .clamp(p.currentBet + game.bigBlind, p.currentBet + p.stack);
}

/// Snap and clamp an already-decided total "to" amount for a raise.
///
/// For callers that compute the size some other way than a pot fraction — an
/// open-raise sized in big blinds, for one.
int snapRaiseTo(PokerGame game, Player p, int rawTo) =>
    snapBet(rawTo, smallBlind: game.smallBlind, bigBlind: game.bigBlind)
        .clamp(game.minRaiseTo(p), game.maxRaiseTo(p));
