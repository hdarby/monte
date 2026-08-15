import 'package:monte/core/domain/ai/player_kind.dart';
import 'package:monte/core/domain/ai/player_profile.dart';
import 'package:monte/core/domain/ai/player_stats.dart';
import 'package:monte/core/domain/ai/stack_context.dart';
import 'package:monte/core/domain/engine/game.dart';
import 'package:monte/core/domain/engine/hand_evaluator.dart';
import 'package:monte/core/domain/engine/player.dart';

/// The shared predicate vocabulary a signature move is written against.
///
/// The spec imagined `engine_triggers` as a fully data-driven rule — a
/// `trigger_condition` object plus an `action_modifier` of multipliers. Half of
/// that works and half does not: the *conditions* genuinely are reusable data,
/// but the *actions* are not multipliers. "Check your monster and spring it
/// later" is a different **line**, not a bigger bet, and no amount of
/// `bet_size_multiplier` expresses it.
///
/// So the conditions live here, shared and uniformly named, and each move's
/// action is written as code in the policy that owns it. That is why
/// `EngineTriggers` on three profiles has sat unread since it was authored:
/// there was never a multiplier that could say what those players actually do.
///
/// Every predicate reads only state the engine already exposes, so a move can be
/// added without touching the engine.
class TriggerContext {
  TriggerContext({
    required this.game,
    required this.hero,
    required this.profile,
    required this.stack,
    this.villainStats,
    this.villainKind,
  });

  factory TriggerContext.of(
    PokerGame game,
    Player hero,
    PlayerProfile profile, {
    PlayerStats? villainStats,
    PlayerKind? villainKind,
  }) =>
      TriggerContext(
        game: game,
        hero: hero,
        profile: profile,
        stack: StackContext.of(game, hero),
        villainStats: villainStats,
        villainKind: villainKind,
      );

  final PokerGame game;
  final Player hero;
  final PlayerProfile profile;
  final StackContext stack;

  /// Accumulated reads on the opponent this decision is about, when known.
  final PlayerStats? villainStats;

  /// Whether that opponent is a pro, a recreational player, or the human.
  final PlayerKind? villainKind;

  /// How well this player executes [id] (0 = they don't have the move).
  double proficiency(String id) => profile.proficiencyOf(id);

  /// Whether they have it at all.
  bool has(String id) => proficiency(id) > 0;

  // ---- Position and action ---------------------------------------------------

  /// Every live opponent has already acted this round, so the hero closes it.
  bool get inPosition => game.players
      .where((x) => x.inHand && !identical(x, hero))
      .every((x) => x.hasActedThisRound);

  /// Nothing to call — it is checked to us (or we open the street).
  bool get checkedToMe => game.callAmount(hero) == 0;

  bool get facingBet => game.callAmount(hero) > 0;

  bool get isPreflopAggressor => hero.raisedPreflop;

  /// Called a bet on the flop — the setup half of a float.
  bool get calledFlop => hero.calledBetOnFlop;

  bool get onFlop => game.round == BettingRound.flop;
  bool get onTurn => game.round == BettingRound.turn;
  bool get onRiver => game.round == BettingRound.river;

  /// Live opponents still in the hand.
  int get liveOpponents =>
      game.players.where((x) => x.inHand && !identical(x, hero)).length;

  bool get headsUp => liveOpponents == 1;

  // ---- Hand strength ---------------------------------------------------------

  /// The hero's made hand on the current board, or null preflop.
  HandRank? get madeRank {
    if (game.board.length < 3 || hero.hole.length < 2) return null;
    return HandEvaluator.evaluate([...hero.hole, ...game.board]).rank;
  }

  /// At least [rank] — "top pair or better" style predicates.
  bool madeAtLeast(HandRank rank) {
    final made = madeRank;
    return made != null && made.index >= rank.index;
  }

  /// Whether the hero holds top pair *specifically* — a pair using the highest
  /// board card. The hand that gets people stacked, and the hand a sticky player
  /// refuses to fold.
  bool get hasTopPair {
    if (game.board.length < 3 || hero.hole.length < 2) return false;
    if (madeRank != HandRank.pair) return false;
    final top = game.board.map((c) => c.rank.value).reduce((a, b) => a > b ? a : b);
    return hero.hole.any((c) => c.rank.value == top);
  }

  // ---- Stack and tournament --------------------------------------------------

  double get spr => stack.spr;
  bool sprBelow(double v) => stack.spr < v;
  StackRegime get regime => stack.regime;

  // ---- Opponent read ---------------------------------------------------------

  /// A recreational opponent, either by their seat class or by an established
  /// read that they show down weak. Underbluffing the river is a population
  /// tendency of exactly this group.
  bool get villainIsRecreational {
    if (villainKind == PlayerKind.amateur) return true;
    final st = villainStats;
    return st != null && st.established && st.aggressionFactor < 0.8;
  }

  /// The read is trustworthy enough to act on.
  bool get trustsReads {
    final st = villainStats;
    return st != null && st.established;
  }
}
