import 'package:meta/meta.dart';

/// The record of one color-up (chip race): the small chip retired, the new
/// smallest chip in play, and the signed chip delta each affected player took
/// away from the race (winners positive, players raced off negative). Surfaced
/// to the table so the human sees "who won what".
@immutable
class ColorUpEvent {
  const ColorUpEvent({
    required this.oldUnit,
    required this.newUnit,
    required this.deltas,
  });

  final int oldUnit;
  final int newUnit;

  /// player id -> chips gained (+) or lost (-) in the race. Only non-zero
  /// entries are kept.
  final Map<String, int> deltas;
}

/// The physical chip denominations a tournament is played with, plus the rules
/// that decide which chips are still in play at a given blind level and how a
/// **color-up** (chip race) redistributes the small chips that get retired.
///
/// Pure data + arithmetic — no engine or UI dependency. The controller reads
/// [smallestChip] to constrain bet granularity (via the engine's `chipUnit`)
/// and calls [colorUp] when a level change retires a denomination.
@immutable
class ChipSet {
  /// [denominations] must be ascending and positive (e.g. 25, 100, 500, ...).
  ChipSet(this.denominations)
      : assert(denominations.isNotEmpty),
        assert(_isAscendingPositive(denominations));

  final List<int> denominations;

  static bool _isAscendingPositive(List<int> d) {
    for (var i = 0; i < d.length; i++) {
      if (d[i] <= 0) return false;
      if (i > 0 && d[i] <= d[i - 1]) return false;
    }
    return true;
  }

  /// The standard large-field WSOP ladder, big enough for an 8,000-runner Main
  /// Event (a 60k start scales to hundreds of millions in play at the end).
  factory ChipSet.wsop() => ChipSet(const [
        25, 100, 500, 1000, 5000, 25000, 100000, 500000, 1000000, 5000000,
      ]);

  /// The smallest denomination still needed to make every betting unit at a
  /// level exactly: the largest chip that divides the small blind, big blind
  /// and ante (ignoring any that are zero). This is the unit every wager must
  /// be a multiple of — anything smaller has been colored up.
  int smallestChip({
    required int smallBlind,
    required int bigBlind,
    required int ante,
  }) {
    final units = [smallBlind, bigBlind, ante].where((u) => u > 0).toList();
    if (units.isEmpty) return denominations.first;
    var best = denominations.first;
    for (final d in denominations) {
      if (units.every((u) => u % d == 0)) best = d;
    }
    return best;
  }

  /// Runs a chip race that rounds every stack to a multiple of [newUnit],
  /// conserving the total exactly: each stack's odd remainder is pooled, then
  /// whole [newUnit] chips are awarded to the players with the largest
  /// remainders (a chip race — biggest odd stack wins the first chip). Returns
  /// the signed chip delta per player id (winners positive, losers negative).
  ///
  /// [stacks] maps player id -> current chips. Assumes the total is already a
  /// multiple of the *old* (smaller) unit, so the pooled remainder is an exact
  /// multiple of [newUnit] and nothing is created or destroyed.
  Map<String, int> colorUp(Map<String, int> stacks, int newUnit) {
    if (newUnit <= 1) return {for (final id in stacks.keys) id: 0};
    final deltas = <String, int>{};
    final remainders = <MapEntry<String, int>>[];
    var pool = 0;
    stacks.forEach((id, chips) {
      final rem = chips % newUnit;
      deltas[id] = -rem; // rounded down for now; race adds whole chips back
      pool += rem;
      if (rem > 0) remainders.add(MapEntry(id, rem));
    });

    // Award the pooled chips as whole [newUnit] units, largest remainder first
    // (ties broken by id for determinism). This is the "race": your odd chips
    // buy you a shot at a full chip, best partial stack wins first.
    remainders.sort((a, b) =>
        b.value != a.value ? b.value - a.value : a.key.compareTo(b.key));
    var chipsToAward = pool ~/ newUnit;
    var i = 0;
    while (chipsToAward > 0 && remainders.isNotEmpty) {
      final id = remainders[i % remainders.length].key;
      deltas[id] = deltas[id]! + newUnit;
      chipsToAward--;
      i++;
    }
    // If the pooled remainder wasn't a whole number of new chips (odd chips can
    // exist after a chopped pot), keep the leftover on the top-remainder stack
    // so the total is conserved exactly — never silently destroyed.
    final leftover = pool - (pool ~/ newUnit) * newUnit;
    if (leftover > 0 && remainders.isNotEmpty) {
      deltas[remainders.first.key] = deltas[remainders.first.key]! + leftover;
    }
    return deltas;
  }
}
