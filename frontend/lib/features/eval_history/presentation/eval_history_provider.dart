import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:monte/features/eval_history/data/file_eval_history_store.dart';
import 'package:monte/features/eval_history/domain/auto_tuner.dart';
import 'package:monte/features/eval_history/domain/eval_hand.dart';
import 'package:monte/features/eval_history/domain/profile_overrides.dart';

/// The permanent tuning-history store. Defaults to a no-op so headless/test runs
/// and the pure engine never touch disk; `main` overrides it with a file-backed
/// [FileEvalHistoryStore] pointed at the app-support directory. Kept alive for
/// the app's lifetime so its append stream survives game rebuilds — the game
/// composition root routes every finished hand's full-information record here.
final evalHistoryStoreProvider = Provider<EvalHistoryStore>(
  (ref) => const NoopEvalHistoryStore(),
);

/// The persisted, per-model preflop tuning overrides produced by the offline
/// auto-tuner. Hydrated from SharedPreferences; empty until the owner tunes.
final profileOverridesProvider =
    NotifierProvider<ProfileOverridesController, ProfileOverrides>(
  ProfileOverridesController.new,
);

class ProfileOverridesController extends Notifier<ProfileOverrides> {
  static const _key = 'profile_overrides';

  @override
  ProfileOverrides build() {
    _hydrate();
    return const ProfileOverrides.empty();
  }

  Future<void> _hydrate() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null) return;
      state = ProfileOverrides.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    } catch (_) {
      // No prefs available (e.g. headless tests) or a corrupt/stale blob —
      // fall back to no overrides.
    }
  }

  /// Runs one offline calibration step over [hands] and persists the result, so
  /// the tuned personalities take effect on the next game/simulation. Returns the
  /// number of models whose parameters changed this pass.
  Future<int> autoTune(List<EvalHand> hands) async {
    final before = state;
    final tuned = AutoTuner.tune(before, hands);
    var changed = 0;
    tuned.byModel.forEach((id, b) {
      final old = before.byModel[id];
      if (old == null ||
          old.vpipTarget != b.vpipTarget ||
          old.pfrTarget != b.pfrTarget ||
          old.threeBetFrequency != b.threeBetFrequency) {
        changed++;
      }
    });
    state = tuned;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(tuned.toJson()));
    return changed;
  }

  /// Reverts every personality to its code-defined type (clears overrides).
  Future<void> reset() async {
    state = const ProfileOverrides.empty();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
