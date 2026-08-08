import 'package:monte/core/domain/ai/player_stats.dart';

/// A decider's read access to accumulated opponent statistics, keyed by the
/// seat id a player occupies in the *current* game. The game/table layer binds
/// a seat→identity resolver behind this, so a policy can ask "what do I know
/// about the player in this seat?" without knowing how identity is derived or
/// where the stats are stored. Pure domain — no persistence dependency.
abstract class OpponentReads {
  /// Accumulated stats for the opponent in [seatPlayerId], or null if unknown.
  PlayerStats? forSeat(String seatPlayerId);
}
