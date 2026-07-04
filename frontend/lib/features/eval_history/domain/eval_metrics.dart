import 'package:monte/core/domain/engine/actions.dart';
import 'package:monte/core/domain/engine/game.dart';
import 'package:monte/features/eval_history/domain/eval_hand.dart';

/// Aggregated tuning metrics for one model/type over a hand sample. Raw counts
/// are stored; rates are getters so tests can assert either.
class ModelMetrics {
  ModelMetrics(this.modelId, this.modelLabel);

  final String modelId;
  final String modelLabel;

  int hands = 0;
  int vpipHands = 0;
  int pfrHands = 0;
  int threeBetHands = 0;
  int limpHands = 0;

  int sawFlop = 0;
  int showdowns = 0;
  int showdownWins = 0;

  int postflopAggressive = 0;
  int postflopCalls = 0;

  int stealOpportunities = 0;
  int stealAttempts = 0;
  int stealSuccesses = 0;

  int riverSeen = 0;
  int riverBets = 0;
  int riverFacingBet = 0;
  int riverFolds = 0;

  int netChips = 0;
  double _netBb = 0;

  double _vpipTargetSum = 0;
  double _pfrTargetSum = 0;
  double _threeBetTargetSum = 0;
  int _targetSamples = 0;

  double _pct(int n, int d) => d == 0 ? 0 : n / d * 100;

  double get vpip => _pct(vpipHands, hands);
  double get pfr => _pct(pfrHands, hands);
  double get threeBet => _pct(threeBetHands, hands);
  double get limp => _pct(limpHands, hands);

  /// Postflop aggression factor: (bets+raises)/calls.
  double get aggressionFactor {
    if (postflopCalls == 0) return postflopAggressive == 0 ? 0 : double.infinity;
    return postflopAggressive / postflopCalls;
  }

  double get stealAttemptPct => _pct(stealAttempts, stealOpportunities);
  double get stealSuccessPct => _pct(stealSuccesses, stealAttempts);
  double get wtsd => _pct(showdowns, sawFlop); // went to showdown
  double get wonAtShowdown => _pct(showdownWins, showdowns);
  double get riverBetPct => _pct(riverBets, riverSeen);
  double get foldToRiverBet => _pct(riverFolds, riverFacingBet);
  double get bbPer100 => hands == 0 ? 0 : _netBb / hands * 100;

  /// Averaged expected targets (present only for profile-based models).
  double? get vpipTarget =>
      _targetSamples == 0 ? null : _vpipTargetSum / _targetSamples * 100;
  double? get pfrTarget =>
      _targetSamples == 0 ? null : _pfrTargetSum / _targetSamples * 100;
  double? get threeBetTarget =>
      _targetSamples == 0 ? null : _threeBetTargetSum / _targetSamples * 100;

  /// Measured minus target (percentage points), or null when no target exists.
  double? get vpipDelta => vpipTarget == null ? null : vpip - vpipTarget!;
  double? get pfrDelta => pfrTarget == null ? null : pfr - pfrTarget!;
}

/// Computes per-model tuning metrics from a full-information [EvalHand] sample —
/// the read-only counterpart to the on-disk tuning history.
class EvalMetrics {
  static const _stealSeats = {'BTN', 'CO', 'SB'};

  /// Aggregates metrics grouped by model id (a named profile's id, or
  /// `brain:style` for a custom bot). The human seat groups under `human`.
  static Map<String, ModelMetrics> byModel(List<EvalHand> hands) {
    final out = <String, ModelMetrics>{};
    for (final hand in hands) {
      _accumulate(hand, out);
    }
    return out;
  }

  static void _accumulate(EvalHand hand, Map<String, ModelMetrics> out) {
    final bb = hand.bigBlind;
    final showdownHappened = hand.results.any((r) => r.handRank != null);
    final winners = {
      for (final r in hand.results)
        if (r.amountWon > 0) r.playerId,
    };
    final posOf = {for (final p in hand.players) p.id: p.position};

    // --- Preflop pass (ordered): VPIP/PFR/3bet/limp + steal opp/attempt. ---
    final vpip = <String>{};
    final pfr = <String>{};
    final threeBet = <String>{};
    final limp = <String>{};
    final stealOpp = <String>{};
    final stealAttempt = <String>{};
    var raiseCount = 0;
    var opened = false; // someone voluntarily entered the pot
    for (final a in hand.actions) {
      if (a.street != BettingRound.preflop) continue;
      final aggressive = _isRaise(a.type);
      final voluntary = _isVoluntary(a.type);

      // Steal chance: unopened pot reaching a late seat.
      if (!opened && _stealSeats.contains(posOf[a.playerId])) {
        stealOpp.add(a.playerId);
        if (aggressive) stealAttempt.add(a.playerId);
      }

      if (voluntary) vpip.add(a.playerId);
      if (aggressive) {
        pfr.add(a.playerId);
        if (raiseCount >= 1) threeBet.add(a.playerId);
        raiseCount++;
      } else if (a.type == ActionType.call && raiseCount == 0) {
        limp.add(a.playerId);
      }
      if (voluntary) opened = true;
    }
    // A steal succeeds when it takes the pot preflop uncontested.
    final stealSuccess = <String>{
      for (final id in stealAttempt)
        if (hand.board.isEmpty && winners.contains(id)) id,
    };

    // --- Postflop + river + net, per player. ---
    for (final p in hand.players) {
      final m = out.putIfAbsent(
        p.modelId,
        () => ModelMetrics(p.modelId, p.modelLabel),
      );
      m.hands++;
      if (vpip.contains(p.id)) m.vpipHands++;
      if (pfr.contains(p.id)) m.pfrHands++;
      if (threeBet.contains(p.id)) m.threeBetHands++;
      if (limp.contains(p.id)) m.limpHands++;
      if (stealOpp.contains(p.id)) m.stealOpportunities++;
      if (stealAttempt.contains(p.id)) m.stealAttempts++;
      if (stealSuccess.contains(p.id)) m.stealSuccesses++;

      m.netChips += p.net;
      if (bb != 0) m._netBb += p.net / bb;

      if (p.vpipTarget != null) {
        m._vpipTargetSum += p.vpipTarget!;
        m._pfrTargetSum += p.pfrTarget ?? 0;
        m._threeBetTargetSum += p.threeBetTarget ?? 0;
        m._targetSamples++;
      }

      // Reached flop / showdown (WTSD / W$SD).
      final reachedFlop = hand.board.length >= 3 &&
          (p.foldStreet == null || p.foldStreet != 'preflop');
      if (reachedFlop) m.sawFlop++;
      final atShowdown =
          !p.folded && showdownHappened && hand.board.length == 5;
      if (atShowdown) {
        m.showdowns++;
        if (winners.contains(p.id)) m.showdownWins++;
      }

      // Postflop aggression factor.
      for (final a in hand.actions) {
        if (a.playerId != p.id || a.street == BettingRound.preflop) continue;
        if (_isRaise(a.type)) {
          m.postflopAggressive++;
        } else if (a.type == ActionType.call) {
          m.postflopCalls++;
        }
      }

      // River: was the player at the river, did they bet, did they fold to a bet?
      final atRiver =
          hand.board.length >= 5 && (p.foldStreet == null || p.foldStreet == 'river');
      if (atRiver) {
        m.riverSeen++;
        var facedBet = false, folded = false, bet = false;
        for (final a in hand.actions) {
          if (a.playerId != p.id || a.street != BettingRound.river) continue;
          if (_isRaise(a.type)) bet = true;
          if (a.type == ActionType.call) facedBet = true;
          if (a.type == ActionType.fold) {
            facedBet = true;
            folded = true;
          }
        }
        if (bet) m.riverBets++;
        if (facedBet) m.riverFacingBet++;
        if (folded) m.riverFolds++;
      }
    }
  }

  static bool _isVoluntary(ActionType t) =>
      t == ActionType.call ||
      t == ActionType.bet ||
      t == ActionType.raise ||
      t == ActionType.allIn;

  static bool _isRaise(ActionType t) =>
      t == ActionType.bet || t == ActionType.raise || t == ActionType.allIn;
}
