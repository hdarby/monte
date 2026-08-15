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
  /// the seat that fired it.
  void onFired(String triggerId, String playerId);
}

/// Counts firings in memory, by trigger and by player.
class CountingTriggerObserver implements TriggerObserver {
  final Map<String, int> _byTrigger = {};
  final Map<String, Map<String, int>> _byPlayer = {};

  @override
  void onFired(String triggerId, String playerId) {
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
