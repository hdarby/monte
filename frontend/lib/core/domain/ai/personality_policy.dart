import 'dart:math';

import 'package:monte/core/domain/ai/hand_range.dart';
import 'package:monte/core/domain/ai/personality.dart';
import 'package:monte/core/domain/ai/postflop_equity.dart';
import 'package:monte/core/domain/engine/actions.dart';
import 'package:monte/core/domain/engine/decision_policy.dart';
import 'package:monte/core/domain/engine/game.dart';
import 'package:monte/core/domain/engine/hand_strength.dart';
import 'package:monte/core/domain/engine/player.dart';

/// A fast, fully personality-driven policy. The four [PersonalityProfile] axes
/// shape the fold/call/bet/raise thresholds so that style is both a usable
/// standalone bot and the default self-/opponent-model for the search's
/// rollouts.
///
/// The axes are wired to be monotonic: more [PersonalityProfile.tightness] folds
/// more (lower VPIP); more [PersonalityProfile.aggression] bets/raises more;
/// more [PersonalityProfile.bluffFrequency] adds aggression with weak hands;
/// more [PersonalityProfile.riskTolerance] calls a touch wider.
class PersonalityPolicy implements DecisionPolicy {
  PersonalityPolicy(this.profile, {Random? random, this.rangeAware = false})
    : _random = random ?? Random();

  final PersonalityProfile profile;
  final Random _random;

  /// When true, postflop decisions reason about the villain's *range* via
  /// range-aware Monte-Carlo equity ([PostflopEquity]) instead of the cheap
  /// category-only [HandStrength.estimate]. Off by default so the search's
  /// rollout self-model stays fast (equity-in-rollout would be MC-in-MC).
  final bool rangeAware;

  /// Equity samples per postflop decision — modest, for live-table latency.
  static const _equityIterations = 160;

  @override
  GameAction decide(PokerGame game, Player p) {
    if (rangeAware && game.board.isNotEmpty) return _postflop(game, p);
    if (game.board.isEmpty) return _preflop(game, p);
    return _cheapPostflop(game, p);
  }

  /// Style-shaped preflop: **raise-or-fold** an opening range whose width tracks
  /// tightness (no limping — the old limp band inflated VPIP far past PFR), then
  /// 3-bet the top / flat a controlled band vs a single raise, premiums-only vs
  /// a 3-bet+. Aggression widens 3-bets and sizes; bluff adds the odd steal.
  GameAction _preflop(PokerGame game, Player p) {
    final s = HandStrength.preflop(p);
    final toCall = game.callAmount(p);
    final raises = game.raiseCountThisRound;
    final aggr = profile.aggression;
    final bluff = profile.bluffFrequency;
    final tight = profile.tightness;
    final risk = profile.riskTolerance;
    final canRaise = p.stack > toCall;

    GameAction openRaise() {
      final to = (game.minRaiseTo(p) + (game.pot * (0.4 + 0.5 * aggr)).round())
          .clamp(game.minRaiseTo(p), game.maxRaiseTo(p));
      return GameAction.raise(to);
    }

    // How strong a hand this style needs to play (tighter -> narrower opens;
    // risk appetite widens it a touch).
    final entryBar = 0.16 + 0.44 * tight - 0.02 * risk;
    final threeBetBar = 0.66 + 0.14 * tight - 0.14 * aggr;
    // Calling a raise needs more than opening; risk tolerance widens the peel.
    final flatBar = entryBar + 0.10 - 0.06 * risk;

    if (raises == 0) {
      // Aggressive styles raise their whole range; passive ones (low aggression)
      // raise only the top and limp the rest — that's what makes a station's VPIP
      // sit far above its PFR, while a maniac raises almost everything. The gate
      // is cubic so medium/high aggression barely limps; only genuinely passive
      // styles open a wide limp band. Premiums always raise (cap at 0.85).
      final passivity = 1 - aggr;
      final raiseBar =
          (entryBar + passivity * passivity * passivity * 0.8)
              .clamp(entryBar, 0.85);
      if (canRaise && s >= raiseBar) return openRaise();
      if (s >= entryBar) {
        // Play the rest passively: limp in, or take the free flop in the BB.
        return toCall == 0 ? const GameAction.check() : const GameAction.call();
      }
      if (canRaise && _random.nextDouble() < bluff * 0.10) return openRaise();
      return toCall == 0 ? const GameAction.check() : const GameAction.fold();
    }

    if (raises == 1) {
      // 3-bet for value, or occasionally as a bluff (scaled by the bluff axis);
      // else flat a controlled band, else fold.
      final bluff3bet = canRaise && _random.nextDouble() < bluff * 0.15;
      if (canRaise && (s >= threeBetBar || bluff3bet)) return openRaise();
      if (s >= flatBar) return const GameAction.call();
      return const GameAction.fold();
    }

    // Facing a 3-bet or more: premiums 4-bet, strong hands call, else fold.
    if (canRaise && s >= 0.85 - 0.08 * aggr) return openRaise();
    if (s >= 0.72) return const GameAction.call();
    return const GameAction.fold();
  }

  /// Cheap, category-only postflop used as the search's rollout self-model
  /// (kept fast — the range-aware brain above is for real decisions).
  GameAction _cheapPostflop(PokerGame game, Player p) {
    final s = HandStrength.estimate(game, p);
    final toCall = game.callAmount(p);
    final bb = game.bigBlind;
    final preflop = game.board.isEmpty;
    final raises = game.raiseCountThisRound;
    final aggr = profile.aggression;
    final bluff = profile.bluffFrequency;
    final tight = profile.tightness;
    final risk = profile.riskTolerance;
    final canRaise = p.stack > toCall;

    GameAction raiseBy(double fraction) {
      final to = (game.minRaiseTo(p) + (game.pot * fraction).round()).clamp(
        game.minRaiseTo(p),
        game.maxRaiseTo(p),
      );
      return GameAction.raise(to);
    }

    // No bet to face: check, or bet for value (threshold falls with aggression)
    // or as a bluff (more likely with weaker hands and a higher bluff axis).
    if (toCall == 0) {
      final wantsValue = s > 0.72 - 0.30 * aggr;
      final wantsBluff = _random.nextDouble() < bluff * (1 - s) * 0.6;
      if ((wantsValue || wantsBluff) && p.stack > bb) {
        final size = (game.pot * (0.4 + 0.6 * aggr)).round().clamp(bb, p.stack);
        return GameAction.bet(p.currentBet + size);
      }
      return const GameAction.check();
    }

    final potOdds = toCall / (game.pot + toCall);
    final callThreshold = potOdds * (1 + 0.8 * tight) - 0.15 * risk;

    // Facing a 3-bet or more: only genuinely strong hands re-raise — otherwise
    // two "raise range" hands escalate to an all-in with junk. Continue with a
    // strong hand, else fold.
    if (raises >= 2) {
      if (canRaise && s > 0.90 - 0.12 * aggr) return raiseBy(0.5 + 0.4 * aggr);
      final floor = preflop ? 0.60 : 0.45;
      if (s >= floor && s >= callThreshold) return const GameAction.call();
      return const GameAction.fold();
    }

    // Unraised or facing a single raise: value/bluff raise, then call/fold by
    // pot odds (scaled by tightness and risk tolerance).
    final wantsRaiseValue = s > 0.82 - 0.30 * aggr;
    final wantsRaiseBluff = _random.nextDouble() < bluff * (1 - s) * 0.4;
    if (canRaise && (wantsRaiseValue || wantsRaiseBluff)) {
      return raiseBy(0.3 + 0.5 * aggr);
    }
    if (s >= callThreshold) return const GameAction.call();
    return const GameAction.fold();
  }

  /// Range-aware postflop: reason about hero equity vs the villain's perceived
  /// continuing range, then let the axes shape the value/bluff/continue lines.
  /// Facing more raises tightens the perceived range (via [HandRange.narrowedBy]),
  /// so equity itself drops in reraised pots — no ad-hoc raise clamps needed.
  GameAction _postflop(PokerGame game, Player p) {
    final toCall = game.callAmount(p);
    final bb = game.bigBlind;
    final raises = game.raiseCountThisRound;
    final aggr = profile.aggression;
    final bluff = profile.bluffFrequency;
    final tight = profile.tightness;
    final risk = profile.riskTolerance;
    final canRaise = p.stack > toCall;

    // Perceived villain range: a fairly tight default continuing range (a player
    // who put money in isn't playing half the deck), tightened further by shown
    // aggression and street. (Per-opponent reads are a later refinement.)
    final dead = {...p.hole, ...game.board};
    final range = HandRange.top(0.40, dead: dead)
        .narrowedBy(raiseCount: raises, street: game.round);
    final eq = PostflopEquity.equity(
      p.hole,
      game.board,
      range,
      iterations: _equityIterations,
      random: _random,
    );

    // A semibluffing hand: not yet good, but with real equity to improve.
    final isDraw = eq >= 0.32 && eq <= 0.55;

    GameAction betBy(double fraction) {
      final size = (game.pot * fraction).round().clamp(bb, p.stack);
      return GameAction.bet(p.currentBet + size);
    }

    GameAction raiseBy(double fraction) {
      final to = (game.minRaiseTo(p) + (game.pot * fraction).round()).clamp(
        game.minRaiseTo(p),
        game.maxRaiseTo(p),
      );
      return GameAction.raise(to);
    }

    // No bet to face: value-bet when ahead of the range (aggression bets a bit
    // thinner), or (semi)bluff — weak hands and draws, gated by bluffFrequency.
    // The value bar stays above a coin-flip so passive types don't stab at air.
    if (toCall == 0) {
      final wantsValue = eq > 0.60 - 0.14 * aggr;
      final bluffChance = bluff * ((1 - eq) * 0.5 + (isDraw ? 0.6 * aggr : 0.0));
      final wantsBluff = _random.nextDouble() < bluffChance;
      if ((wantsValue || wantsBluff) && p.stack > bb) {
        return betBy(0.4 + 0.6 * aggr);
      }
      return const GameAction.check();
    }

    // Facing a bet. Continue needs real equity vs the (now tight) betting range;
    // tightness raises the bar (nits overfold), risk tolerance lowers it a touch
    // (stations/gamblers peel). Kept strictly above pot odds so we're not calling
    // every marginal spot.
    final potOdds = toCall / (game.pot + toCall);
    final continueEq =
        (potOdds * (1 + 1.1 * tight) - 0.10 * risk).clamp(0.0, 1.0);

    final wantsValueRaise = eq > 0.74 - 0.12 * aggr;
    final wantsBluffRaise =
        isDraw && _random.nextDouble() < bluff * 0.5 * (0.4 + aggr);
    if (canRaise && (wantsValueRaise || wantsBluffRaise)) {
      return raiseBy(0.3 + 0.5 * aggr);
    }
    if (eq >= continueEq) return const GameAction.call();
    return const GameAction.fold();
  }
}
