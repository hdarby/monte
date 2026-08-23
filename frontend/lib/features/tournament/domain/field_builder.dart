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

  /// Draws a recreational, weighted toward the competent ones.
  ///
  /// A uniform draw made Dave Coyle at 75% VPIP exactly as likely as Phil
  /// DiPinto at 24%, which is fine for one home game and absurd as the sampling
  /// model for a thousand-runner field: every table got a maniac and pots ran
  /// five and six ways. Real large fields are mostly unremarkable players with
  /// a wild one occasionally.
  ///
  /// Weight rises steeply with skill, so the solid recs dominate the field and
  /// the caricatures still turn up — just at the frequency they actually do.
  PlayerProfile _drawRec(List<PlayerProfile> pool) {
    var total = 0.0;
    for (final p in pool) {
      total += _recWeight(p);
    }
    var roll = _rng.nextDouble() * total;
    for (final p in pool) {
      roll -= _recWeight(p);
      if (roll <= 0) return p;
    }
    return pool.last;
  }

  /// Cubed skill, then penalised for extreme looseness.
  ///
  /// Skill alone was not enough: at a cheap buy-in nothing tightens the pool
  /// (`atStakes` scales with stakes pressure, which is zero at $100), so the
  /// 40%+ VPIP profiles still made up a fifth of the field and pots still ran
  /// five ways. Looseness is the trait that actually causes it, so weight
  /// against it directly rather than hoping skill correlates.
  ///
  /// They are damped, never excluded — a large field does contain maniacs, and
  /// removing them would be its own kind of wrong.
  static double _recWeight(PlayerProfile p) {
    final s = p.skill.clamp(0.05, 1.0);
    final vpip = p.strategicBaseline.vpipTarget;
    // 1.0 at a normal 30% VPIP, falling away steeply past 40%.
    final loose = vpip <= 0.32
        ? 1.0
        : (1.0 - 2.2 * (vpip - 0.32)).clamp(0.04, 1.0);
    return (0.02 + s * s * s) * loose;
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
      // Alternate the pools so the field stays a believable mix.
      //
      // This used to run 0.5 + 0.25 * pressure — half pros at a $100 event and
      // three-quarters at the Main. Both are badly wrong, and wrong in the
      // direction that makes the game feel unfair. A $100 tournament is almost
      // entirely recreational; even the Main Event, the most prestigious field
      // in poker, is overwhelmingly satellite winners, amateurs and businessmen
      // taking their annual shot — professionals are a large minority at most.
      // Pros only actually dominate a field above the Main, in the high rollers
      // where the buy-in itself is the filter.
      //
      // So: ~25% pros at $100, ~48% at the $10k Main, climbing past that only
      // above it. [stakesPressure] saturates at $10k, hence the separate term.
      //
      // The floor is 25% rather than the 12% a real cheap field would have,
      // because the recreational pool is not a cross-section of amateurs — it is
      // twenty-nine specific people, several of them deliberate caricatures
      // (50/8, 75/35, 44/14), built to be identifiable at one nine-handed table.
      // A few of those among nine players is realistic. Four-fifths of a
      // thousand-runner field drawn from them is bingo: measured live, a level-1
      // feature hand went seven ways. Real fields are soft; they are not that.
      final beyondMain = buyIn > 10000
          ? (log(buyIn / 10000) / log(10)).clamp(0.0, 1.0)
          : 0.0;
      final proShare = (0.25 + 0.23 * pressure + 0.40 * beyondMain)
          .clamp(0.20, 0.85);
      final preferred = ((i * proShare) % 1.0) >= proShare ? recreational : pros;
      i++;
      final src = preferred.isNotEmpty
          ? preferred
          : (recreational.isNotEmpty ? recreational : pros);
      if (src.isEmpty) break;
      final profile = (identical(src, recreational) ? _drawRec(src) : src[_rng.nextInt(src.length)])
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
