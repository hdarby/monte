import 'package:monte/core/domain/ai/personality.dart';
import 'package:monte/core/domain/engine/actions.dart';
import 'package:monte/core/domain/engine/game.dart';
import 'package:monte/core/domain/hand_history.dart';

/// Running observations of one opponent's tendencies, accumulated hand by hand.
///
/// Frequencies are reported with **shrinkage toward a population prior**: with
/// few hands seen they sit near the prior, converging to the observed rate as the
/// sample grows. This keeps early reads from being wild — exploitation should
/// scale with confidence, not pounce on a 3-hand sample.
class OpponentObservations {
  /// Hands the player was dealt into.
  int hands = 0;

  /// Hands where they voluntarily put money in preflop / raised preflop.
  int vpipHands = 0;
  int pfrHands = 0;

  /// Postflop aggressive (bet/raise) vs passive (call) action counts.
  int postflopAggressive = 0;
  int postflopCalls = 0;

  /// Pseudo-hands of prior; ~one orbit, so reads firm up over a session.
  static const double _priorWeight = 12;
  static const double _vpipPrior = 0.24;
  static const double _pfrPrior = 0.18;

  double get vpip =>
      (vpipHands + _vpipPrior * _priorWeight) / (hands + _priorWeight);
  double get pfr =>
      (pfrHands + _pfrPrior * _priorWeight) / (hands + _priorWeight);

  /// Aggression factor: postflop (bets+raises)/calls. Infinity if aggressive but
  /// never calling; 1.0 as a neutral default with no postflop sample.
  double get aggressionFactor {
    if (postflopCalls == 0) {
      return postflopAggressive == 0 ? 1.0 : double.infinity;
    }
    return postflopAggressive / postflopCalls;
  }

  /// How much to trust these reads, in [0, 1] — grows with sample size.
  double get confidence => hands / (hands + _priorWeight);

  /// The playing style these reads imply, as a [PersonalityProfile] the search
  /// can model the opponent with: looser VPIP → lower tightness; higher postflop
  /// aggression factor → more aggression/bluffing.
  PersonalityProfile readProfile() {
    final tightness = (1.05 - vpip * 1.2).clamp(0.05, 0.95);
    final af = aggressionFactor.isFinite ? aggressionFactor : 4.0;
    final aggression = (0.25 + 0.16 * af).clamp(0.10, 0.95);
    final bluff = (0.10 + 0.18 * af).clamp(0.05, 0.90);
    return PersonalityProfile(
      aggression: aggression,
      bluffFrequency: bluff,
      tightness: tightness,
      riskTolerance: 0.5,
    );
  }
}

/// Per-opponent tendency tracker for one table/session. Fed completed hands; read
/// by exploitative deciders (Phase 3b).
class OpponentModel {
  final Map<String, OpponentObservations> _byId = {};

  /// Observations for [playerId] (created empty on first access).
  OpponentObservations of(String playerId) =>
      _byId.putIfAbsent(playerId, OpponentObservations.new);

  /// Player ids seen so far.
  Iterable<String> get knownPlayers => _byId.keys;

  /// Folds a completed [hand] into every dealt player's running observations.
  void observe(HandHistory hand) {
    for (final player in hand.players) {
      final o = of(player.id);
      o.hands++;

      final mine = hand.actions.where((a) => a.playerId == player.id);
      final preflop = mine.where((a) => a.street == BettingRound.preflop);
      if (preflop.any((a) => _voluntary(a.type))) o.vpipHands++;
      if (preflop.any((a) => _aggressive(a.type))) o.pfrHands++;

      for (final a in mine.where((a) => a.street != BettingRound.preflop)) {
        if (_aggressive(a.type)) {
          o.postflopAggressive++;
        } else if (a.type == ActionType.call) {
          o.postflopCalls++;
        }
      }
    }
  }

  static bool _voluntary(ActionType t) =>
      t == ActionType.call ||
      t == ActionType.bet ||
      t == ActionType.raise ||
      t == ActionType.allIn;

  static bool _aggressive(ActionType t) =>
      t == ActionType.bet || t == ActionType.raise || t == ActionType.allIn;
}
