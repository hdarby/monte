import 'package:meta/meta.dart';

import 'package:monte/core/domain/engine/game.dart';

/// Records when a signature move actually fires.
///
/// Deliberately built alongside the moves rather than after them. `GeneralTraits`
/// and `EngineTriggers` are both authored on every profile and read by nothing,
/// and nobody noticed because there was no way to ask "did this ever do
/// anything?". Six moves across 140 players is a great deal of behaviour to add
/// on faith; this is how it gets checked.
///
/// Pure domain — no I/O. A test or the analytics screen supplies an
/// implementation; production passes null and pays nothing.
abstract class TriggerObserver {
  /// [triggerId] is the characteristic id (e.g. `Slow_Play_Trap`), [playerId]
  /// the seat that fired it, [street] the round it happened on.
  ///
  /// The street is what lets the recap attach the move to the right block —
  /// "that check on the flop was the trap" reads very differently from the same
  /// sentence floating loose at the end of the hand.
  void onFired(String triggerId, String playerId, BettingRound street);
}

/// One signature move, as it fired.
@immutable
class FiredTrigger {
  const FiredTrigger(this.triggerId, this.playerId, this.street);

  final String triggerId;
  final String playerId;
  final BettingRound street;

  @override
  bool operator ==(Object other) =>
      other is FiredTrigger &&
      other.triggerId == triggerId &&
      other.playerId == playerId &&
      other.street == street;

  @override
  int get hashCode => Object.hash(triggerId, playerId, street);

  @override
  String toString() => '$triggerId($playerId@${street.name})';
}

/// Collects the moves fired during a single hand, so the recap can talk about
/// them. Drained and cleared by the recorder once the hand is written up.
class TriggerLog implements TriggerObserver {
  final List<FiredTrigger> _fired = [];

  @override
  void onFired(String triggerId, String playerId, BettingRound street) =>
      _fired.add(FiredTrigger(triggerId, playerId, street));

  List<FiredTrigger> get fired => List.unmodifiable(_fired);

  bool get isEmpty => _fired.isEmpty;

  /// Returns what fired and resets for the next hand.
  List<FiredTrigger> drain() {
    final out = List<FiredTrigger>.unmodifiable(_fired);
    _fired.clear();
    return out;
  }

  void clear() => _fired.clear();
}

/// Counts firings in memory, by trigger and by player.
class CountingTriggerObserver implements TriggerObserver {
  final Map<String, int> _byTrigger = {};
  final Map<String, Map<String, int>> _byPlayer = {};

  @override
  void onFired(String triggerId, String playerId, BettingRound street) {
    _byTrigger[triggerId] = (_byTrigger[triggerId] ?? 0) + 1;
    (_byPlayer[triggerId] ??= {})[playerId] =
        ((_byPlayer[triggerId] ??= {})[playerId] ?? 0) + 1;
  }

  /// Total firings of [triggerId].
  int count(String triggerId) => _byTrigger[triggerId] ?? 0;

  /// Firings of [triggerId] by [playerId].
  int countFor(String triggerId, String playerId) =>
      _byPlayer[triggerId]?[playerId] ?? 0;

  /// Every trigger that fired at least once.
  Iterable<String> get fired => _byTrigger.keys;

  Map<String, int> get totals => Map.unmodifiable(_byTrigger);

  void clear() {
    _byTrigger.clear();
    _byPlayer.clear();
  }

  @override
  String toString() {
    final rows = _byTrigger.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return rows.map((e) => '${e.key}=${e.value}').join(' ');
  }
}
