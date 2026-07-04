import 'package:meta/meta.dart';

import 'package:monte/core/domain/ai/player_profile.dart';

/// Per-model tuned preflop baselines produced by the offline auto-tuner. Keyed
/// by model id (an amateur profile's id, e.g. `H005`). These are the *effective
/// inputs* fed to the decider — the immutable code profiles stay untouched; a
/// tuned baseline is swapped in at decider-build time via [apply].
@immutable
class ProfileOverrides {
  const ProfileOverrides(this.byModel);

  const ProfileOverrides.empty() : byModel = const {};

  final Map<String, StrategicBaseline> byModel;

  int get length => byModel.length;
  bool get isEmpty => byModel.isEmpty;

  /// Returns [profile] with its strategic baseline replaced by the tuned one,
  /// when an override exists for its id; otherwise returns it unchanged. Only the
  /// preflop baseline is swapped — skill, behavioral modifiers, and identity are
  /// preserved.
  PlayerProfile apply(PlayerProfile profile) {
    final tuned = byModel[profile.id];
    return tuned == null ? profile : profile.withStrategicBaseline(tuned);
  }

  ProfileOverrides withEntry(String modelId, StrategicBaseline baseline) =>
      ProfileOverrides({...byModel, modelId: baseline});

  factory ProfileOverrides.fromJson(Map<String, dynamic> json) =>
      ProfileOverrides({
        for (final e in json.entries)
          e.key: StrategicBaseline.fromJson(
            (e.value as Map).cast<String, dynamic>(),
          ),
      });

  Map<String, dynamic> toJson() => {
    for (final e in byModel.entries) e.key: e.value.toJson(),
  };
}
