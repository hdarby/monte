import 'dart:math';

import 'package:monte/core/domain/ai/home_game_profiles.dart';
import 'package:monte/core/domain/ai/player_profile.dart';
import 'package:monte/core/domain/ai/player_profiles.dart';
import 'package:monte/features/tournament/domain/name_pool.dart';

/// Assembles the bot field for a tournament: the personalities the owner
/// explicitly picked (under their real names) plus an alternating
/// recreational/pro mix to fill the remaining seats.
///
/// Auto-filled seats play a real personality's *style* but wear a unique
/// generated name, so a large field never shows the same person twice.
///
/// Pure and seedable — pass a seeded [Random] to get a reproducible field. This
/// used to live inside the lobby widget's `State`, which made it untestable.
class FieldBuilder {
  FieldBuilder({
    required this.humanName,
    List<PlayerProfile>? recreational,
    List<PlayerProfile>? pros,
    Random? rng,
  }) : _rng = rng ?? Random(),
       recreational = _pool(recreational ?? homeGameProfiles, humanName),
       pros = _pool(pros ?? builtInProfiles, humanName);

  final String humanName;
  final Random _rng;

  /// The selectable pools, alphabetical and with the human's own namesake
  /// removed — you shouldn't face a bot playing "you".
  final List<PlayerProfile> recreational;
  final List<PlayerProfile> pros;

  static List<PlayerProfile> _pool(List<PlayerProfile> src, String humanName) {
    final me = humanName.trim().toLowerCase();
    return [
      for (final p in src)
        if (p.name.trim().toLowerCase() != me) p,
    ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }

  /// Every selectable profile, both pools combined.
  List<PlayerProfile> get all => [...recreational, ...pros];

  PlayerProfile? byId(String id) => all.where((p) => p.id == id).firstOrNull;

  /// Effective entrants for a lobby selection: the chosen [fieldSize], grown so
  /// every explicitly selected player fits (each takes a seat, the human takes
  /// one, the rest auto-fill).
  int entrantsFor({required int fieldSize, required int selectedCount}) =>
      max(fieldSize, selectedCount + 1);

  /// Seats per table: short-handed only when the whole field fits on one table.
  int tableSizeFor(int entrants) =>
      entrants <= 9 ? entrants.clamp(2, 9) : 9;

  /// Builds the `entrants - 1` bot profiles, shuffled so the selected players
  /// aren't clustered at one table.
  /// Maps a [buyIn] to a 0–1 "stakes pressure": how much this event's price
  /// tightens the players and thins out the recreationals.
  ///
  /// Log-scaled, because the step from $100 to $1,000 means far more than the
  /// step from $9,000 to $10,000. 0 at a $100 event, 1 at the $10,000 Main.
  static double stakesPressure(int buyIn) {
    if (buyIn <= 100) return 0.0;
    if (buyIn >= 10000) return 1.0;
    return (log(buyIn / 100) / log(100)).clamp(0.0, 1.0);
  }

  List<PlayerProfile> build({
    required Set<String> selectedIds,
    required int entrants,
    int buyIn = 0,
  }) {
    // Both halves of the buy-in effect: a tougher *mix* (fewer recreationals as
    // the price climbs), and every player sharpening up (`atStakes`).
    final pressure = buyIn > 0 ? stakesPressure(buyIn) : 0.0;
    final field = [
      for (final id in selectedIds) byId(id),
    ].whereType<PlayerProfile>().toList();

    final botsNeeded = entrants - 1;
    final used = <String>{humanName, for (final p in field) p.name};

    var i = 0;
    while (field.length < botsNeeded) {
      // Alternate the pools so the field stays a believable mix. At a big
      // buy-in the rotation is weighted toward pros: a $10k field is roughly
      // three-quarters regulars, a $100 field roughly half recreational.
      final proShare = 0.5 + 0.25 * pressure;
      final preferred = ((i * proShare) % 1.0) >= proShare ? recreational : pros;
      i++;
      final src = preferred.isNotEmpty
          ? preferred
          : (recreational.isNotEmpty ? recreational : pros);
      if (src.isEmpty) break;
      final profile = src[_rng.nextInt(src.length)]
          .atStakes(pressure)
          .renamed(uniqueName(used), generated: true);
      field.add(profile);
    }
    return field.take(botsNeeded).toList()..shuffle(_rng);
  }

  /// Draws a "First Last" name not already in [used], adding it to the set.
  /// Falls back to a numeric suffix once the pool is exhausted (huge fields).
  String uniqueName(Set<String> used) {
    for (var attempt = 0; attempt < 1000; attempt++) {
      final name = _randomName();
      if (used.add(name)) return name;
    }
    final base = _randomName();
    var n = 2;
    while (!used.add('$base $n')) {
      n++;
    }
    return '$base $n';
  }

  String _randomName() =>
      '${firstNames[_rng.nextInt(firstNames.length)]} '
      '${lastNames[_rng.nextInt(lastNames.length)]}';
}
