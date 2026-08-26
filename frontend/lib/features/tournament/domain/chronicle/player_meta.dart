import 'package:monte/features/tournament/domain/tournament_snapshot.dart'
    show StandingKind;

/// Running per-player metagame counters, shared by every recap generator in
/// `chronicle/`. The `L`-suffixed fields are reset each level (recaps talk
/// about "this level"); the rest are tournament-wide.
class PlayerMeta {
  PlayerMeta(this.name, this.kind);
  String name;
  StandingKind kind;

  /// A real, named personality (a chosen pro/reg) or the human — i.e. not an
  /// anonymous generated filler. These are the players the recap tells stories
  /// about. The human is included deliberately: they are as much a character in
  /// the tournament as anyone else, and leaving them out made the recap read
  /// like it was about somebody else's game.
  bool isPersonality = false;

  /// True for the human's seat, so prose can address them in second person
  /// ("you are running hot") instead of third ("Alex is running hot").
  bool get isHuman => kind == StandingKind.human;

  int levelStartChips = 0;

  // Per-level.
  int handsWonL = 0;
  int showdownsL = 0;
  int knockoutsL = 0;
  int luckyWinsL = 0; // won an all-in while behind on the flop
  int badBeatsL = 0; // lost an all-in while ahead on the flop
  int bigLossesL = 0; // lost a big pot at showdown holding a strong hand
  int biggestPotL = 0;
  String? biggestPotHandL; // hero's hand in their biggest won pot this level

  // Preflop play-style, human only (see `HandDigest`'s `*Human` fields) — how
  // the level went, not just what it cost or won.
  int handsDealtL = 0;
  int vpipL = 0;
  int rfiL = 0;
  int stealChancesL = 0;
  int stealAttemptsL = 0;

  // Tournament-wide.
  int knockouts = 0;

  /// The best (lowest-numbered) overall rank ever held, across every level —
  /// how `LeaderboardStorylines` knows someone was ever prominent, not just
  /// what they are doing this level.
  int bestRankEver = 1 << 30;

  /// Whether this player ever *started* a level on crumbs (see
  /// `TournamentChronicle._crumbs`) — the same bar, just remembered for the
  /// rest of the tournament instead of only compared against that same
  /// level's end.
  bool wasCrippledEarlier = false;
  int crippledAtLevel = 0;

  /// Each cross-level storyline fires at most once per player — a "how the
  /// mighty have fallen" line reads worse the second time it's said about the
  /// same person.
  bool fallenStarAnnounced = false;
  bool fadedLeaderAnnounced = false;
  bool backFromDeadAnnounced = false;
}
