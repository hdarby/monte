import 'package:monte/core/domain/ai/player_profile.dart';
import 'package:monte/core/domain/ai/profile_decider.dart';

/// What sort of player is in a seat: the human, a pro-calibre personality, or a
/// recreational ("rec") one.
///
/// Shared by the table seats and the tournament standings so both agree on the
/// classification — and, via `core/presentation/player_kind_color.dart`, on the
/// colour that represents it.
enum PlayerKind {
  human,
  pro,
  amateur;

  /// Classifies a seat from its personality. A null [profile] with
  /// [isHuman] false means an untracked bot, which is treated as a pro (the
  /// default brain is a solid, non-recreational one).
  static PlayerKind of(PlayerProfile? profile, {required bool isHuman}) {
    if (isHuman) return PlayerKind.human;
    if (profile != null && isAmateurProfile(profile)) return PlayerKind.amateur;
    return PlayerKind.pro;
  }

  /// A short label for the seat badge / legend.
  String get label => switch (this) {
    PlayerKind.human => 'YOU',
    PlayerKind.pro => 'PRO',
    PlayerKind.amateur => 'REC',
  };
}
