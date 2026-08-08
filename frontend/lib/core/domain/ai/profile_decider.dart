import 'dart:math';

import 'package:monte/core/domain/ai/amateur_policy.dart';
import 'package:monte/core/domain/ai/home_game_profiles.dart';
import 'package:monte/core/domain/ai/opponent_reads.dart';
import 'package:monte/core/domain/ai/player_profile.dart';
import 'package:monte/core/domain/ai/profile_calibrator.dart';
import 'package:monte/core/domain/ai/profile_policy.dart';
import 'package:monte/core/domain/ai/profile_postflop_policy.dart';
import 'package:monte/core/domain/engine/decision_policy.dart';

/// Builds the brain that plays a given [profile] — the single source of truth for
/// "how does this personality play", shared by the cash table and tournaments.
///
/// - **Recreational** profiles (skill &lt; 1.0, or any home-game roster member)
///   use the degraded [AmateurPolicy], which builds its own intentionally-leaky
///   ranges so amateurs stay believably worse than the pros.
/// - **Pros** use calibrated preflop frequencies ([ProfilePolicy]) plus the fast,
///   range-aware [ProfilePostflopPolicy] expressing the GTO↔exploit dial. Ranges
///   are baked for the built-in pros, so construction is instant.
/// Whether [p] plays the degraded recreational brain (a home-game roster member
/// or any sub-1.0 skill), rather than the disciplined pro brain.
bool isAmateurProfile(PlayerProfile p) =>
    p.skill < 1.0 || homeGameProfiles.any((a) => a.id == p.id);

DecisionPolicy deciderForProfile(
  PlayerProfile profile, {
  Random? random,
  OpponentReads? reads,
}) {
  if (isAmateurProfile(profile)) {
    return AmateurPolicy(profile, random: random);
  }
  return ProfilePolicy(
    profile,
    random: random,
    ranges: const ProfileCalibrator().rangesFor(profile),
    postflop: ProfilePostflopPolicy(profile, random: random, reads: reads),
    reads: reads,
  );
}
