import 'package:monte/core/util/format.dart';
import 'package:monte/features/tournament/domain/chronicle/chronicle_grammar.dart';
import 'package:monte/features/tournament/domain/chronicle/player_meta.dart';

/// Leaderboard swings that span the *whole tournament*, not just one level:
/// a former big name busting or fading long after they last led the field,
/// and a genuine multi-level comeback from being crippled. Distinct from
/// `TournamentChronicle`'s own same-level storylines (a bully, a within-level
/// comeback) — those compare a level's start to its end; everything here
/// compares against history that predates the level just played.
class LeaderboardStorylines {
  const LeaderboardStorylines._();

  /// How prominent a player has to have been for a leaderboard-swing
  /// storyline to be worth telling — the same "running deep" bar
  /// `TournamentChronicle._riserLines` uses, so "was a big name" means the
  /// same thing everywhere in the recap.
  static const prominentRank = 100;

  /// Updates every active player's tournament-wide history — best rank ever
  /// and whether they've ever started a level on crumbs — so a bust or a
  /// comeback many levels later can still be recognised as one. Must run
  /// before any of the generators below, once per `buildRecap` call.
  static void updateHistory({
    required Map<String, PlayerMeta> meta,
    required List<String> ranked,
    required Map<String, int> rankOf,
    required int crumbs,
    required int levelJustFinished,
  }) {
    for (final id in ranked) {
      final m = meta[id];
      if (m == null) continue;
      final rank = rankOf[id]!;
      if (rank < m.bestRankEver) m.bestRankEver = rank;
      if (!m.wasCrippledEarlier &&
          m.levelStartChips > 0 &&
          m.levelStartChips <= crumbs) {
        m.wasCrippledEarlier = true;
        m.crippledAtLevel = levelJustFinished;
      }
    }
  }

  /// A named personality (or the human) who was once top-100 and has now
  /// busted — "how the mighty have fallen," told once per player.
  static List<String> fallenStar({
    required Map<String, PlayerMeta> meta,
    required List<String> eliminated,
    required Map<String, int> finishPlaces,
    required Map<String, int> prizes,
  }) {
    final out = <String>[];
    for (final id in eliminated) {
      final m = meta[id];
      if (m == null || !m.isPersonality) continue;
      if (m.bestRankEver > prominentRank || m.fallenStarAnnounced) continue;
      m.fallenStarAnnounced = true;
      final place = finishPlaces[id];
      final prize = prizes[id] ?? 0;
      final placeStr = place != null ? ' in ${ordinal(place)}' : '';
      final cash = prize > 0 ? ' for \$${formatChips(prize)}' : '';
      out.add('${ChronicleGrammar.who(m, capital: true)} '
          '${ChronicleGrammar.was(m)} as high as ${ordinal(m.bestRankEver)} '
          'overall earlier in the tournament — '
          '${m.isHuman ? 'you busted' : 'busted'} this level$placeStr$cash.');
    }
    return out;
  }

  /// A named personality (or the human) who was once top-100 and is still in,
  /// but has fallen to crumbs — the mirror of [fallenStar] for someone who
  /// hasn't busted yet, just faded. Told once per player.
  static List<String> fadedLeader({
    required Map<String, PlayerMeta> meta,
    required Map<String, int> currentChips,
    required int crumbs,
    required int bigBlind,
  }) {
    final out = <String>[];
    meta.forEach((id, m) {
      if (!m.isPersonality || m.fadedLeaderAnnounced) return;
      if (m.bestRankEver > prominentRank) return;
      final chips = currentChips[id];
      if (chips == null || chips > crumbs) return;
      m.fadedLeaderAnnounced = true;
      out.add('${ChronicleGrammar.who(m, capital: true)} once cracked the '
          'top $prominentRank; now down to '
          '${ChronicleGrammar.amt(chips, bigBlind)} and fighting for a '
          'double.');
    });
    return out.take(2).toList();
  }

  /// A genuine across-the-tournament comeback: crippled several levels ago,
  /// healthy again now. Distinct from `TournamentChronicle._comebackLines`,
  /// which only covers a swing within a single level — this is the "back
  /// from the dead" arc that plays out over the whole event. Told once per
  /// player.
  static List<String> backFromDead({
    required Map<String, PlayerMeta> meta,
    required int levelJustFinished,
    required Map<String, int> currentChips,
    required int avgStack,
  }) {
    if (avgStack <= 0) return const [];
    final out = <String>[];
    meta.forEach((id, m) {
      if (!m.isPersonality || m.backFromDeadAnnounced) return;
      if (!m.wasCrippledEarlier) return;
      // Same-level recoveries already have their own storyline above; this
      // one is for a recovery that took real time.
      if (m.crippledAtLevel >= levelJustFinished - 1) return;
      final chips = currentChips[id];
      if (chips == null || chips < avgStack) return;
      m.backFromDeadAnnounced = true;
      out.add('${ChronicleGrammar.who(m, capital: true)} '
          '${ChronicleGrammar.was(m)} down to fumes back on level '
          '${m.crippledAtLevel} — ${ChronicleGrammar.has(m)} clawed all the '
          'way back into contention.');
    });
    return out.take(2).toList();
  }
}
