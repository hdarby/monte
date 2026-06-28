import 'package:meta/meta.dart';

import 'package:monte/core/domain/ai/decider_factory.dart';
import 'package:monte/core/domain/ai/personality.dart';
import 'package:monte/core/domain/ai/player_profile.dart';

/// One bot seat's behavior model. Either a *custom* bot ([brain] + [style]) or,
/// when [profile] is set, a calibrated named player profile that overrides them.
/// This is the per-seat unit the New Game setup produces and the table builds
/// deciders from.
@immutable
class BotSpec {
  const BotSpec({
    this.brain = BotType.heuristic,
    this.style = PersonalityArchetype.balanced,
    this.profile,
  });

  /// The decision engine (heuristic / personality / MCTS).
  final BotType brain;

  /// The playing-style archetype shaping the brain (ignored by the heuristic).
  final PersonalityArchetype style;

  /// When set, this seat plays the named, stat-calibrated profile instead of the
  /// [brain] + [style] combination.
  final PlayerProfile? profile;

  bool get isProfile => profile != null;

  BotSpec copyWith({BotType? brain, PersonalityArchetype? style}) => BotSpec(
    brain: brain ?? this.brain,
    style: style ?? this.style,
    profile: profile,
  );

  /// Replaces (or clears, when null) the named profile, keeping brain + style.
  BotSpec withProfile(PlayerProfile? profile) =>
      BotSpec(brain: brain, style: style, profile: profile);

  /// A short label for a seat badge — the profile name, or "Maniac · MCTS"
  /// style. The heuristic ignores personality, so it shows only the brain.
  String get label => profile != null
      ? profile!.name
      : brain.usesPersonality
      ? '${style.shortLabel} · ${brain.shortLabel}'
      : 'Heuristic';

  @override
  bool operator ==(Object other) =>
      other is BotSpec &&
      other.brain == brain &&
      other.style == style &&
      other.profile?.id == profile?.id;

  @override
  int get hashCode => Object.hash(brain, style, profile?.id);
}
