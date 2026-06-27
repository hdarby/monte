import 'package:poker_client/core/domain/engine/actions.dart';
import 'package:poker_client/core/domain/engine/game.dart';
import 'package:poker_client/core/domain/hand_history.dart';

/// Accumulated per-player statistics over a set of hands.
class PlayerStats {
  PlayerStats(this.id, this.name);

  final String id;
  final String name;

  int hands = 0;

  /// Hands where the player voluntarily put money in preflop (call/bet/raise).
  int vpipHands = 0;

  /// Hands where the player raised or bet preflop.
  int pfrHands = 0;

  /// Postflop aggressive (bet/raise) and passive (call) action counts, used for
  /// the Aggression Factor.
  int aggressiveActions = 0;
  int callActions = 0;

  /// Net chips won/lost, and the same expressed in big blinds.
  int netChips = 0;
  double netBigBlinds = 0;

  /// Voluntarily Put money In Pot, as a percentage.
  double get vpip => hands == 0 ? 0 : vpipHands / hands * 100;

  /// PreFlop Raise, as a percentage.
  double get pfr => hands == 0 ? 0 : pfrHands / hands * 100;

  /// Aggression Factor: (bets + raises) / calls, postflop. Infinity if the
  /// player was aggressive but never called; 0 if no postflop action.
  double get aggressionFactor {
    if (callActions == 0) {
      return aggressiveActions == 0 ? 0 : double.infinity;
    }
    return aggressiveActions / callActions;
  }

  String get aggressionLabel {
    final af = aggressionFactor;
    if (af == double.infinity) return '∞';
    return af.toStringAsFixed(2);
  }

  /// Win rate in big blinds per 100 hands.
  double get bbPer100 => hands == 0 ? 0 : netBigBlinds / hands * 100;
}

/// Computes [PlayerStats] from recorded [HandHistory] objects.
class PokerAnalytics {
  /// Returns stats per player, ordered by net big blinds (best first).
  static List<PlayerStats> compute(List<HandHistory> histories) {
    final byId = <String, PlayerStats>{};

    for (final hand in histories) {
      for (final player in hand.players) {
        final stats = byId.putIfAbsent(
          player.id,
          () => PlayerStats(player.id, player.name),
        );
        stats.hands++;

        final mine = hand.actions.where((a) => a.playerId == player.id);

        final preflop = mine.where((a) => a.street == BettingRound.preflop);
        if (preflop.any((a) => _isVoluntary(a.type))) stats.vpipHands++;
        if (preflop.any((a) => _isRaise(a.type))) stats.pfrHands++;

        for (final a in mine.where((a) => a.street != BettingRound.preflop)) {
          if (_isRaise(a.type)) {
            stats.aggressiveActions++;
          } else if (a.type == ActionType.call) {
            stats.callActions++;
          }
        }

        final net = hand.netFor(player.id);
        stats.netChips += net;
        stats.netBigBlinds += hand.bigBlind == 0 ? 0 : net / hand.bigBlind;
      }
    }

    final list = byId.values.toList()
      ..sort((a, b) => b.netBigBlinds.compareTo(a.netBigBlinds));
    return list;
  }

  static bool _isVoluntary(ActionType t) =>
      t == ActionType.call ||
      t == ActionType.bet ||
      t == ActionType.raise ||
      t == ActionType.allIn;

  static bool _isRaise(ActionType t) =>
      t == ActionType.bet || t == ActionType.raise || t == ActionType.allIn;
}
