// ignore_for_file: avoid_print
//
// One-off generator: bakes [ProfileCalibrator]'s live calibration for every
// shipped pro (builtInProfiles ++ homeGameProfiles, skipping amateurs — they
// use AmateurPolicy, never ProfileCalibrator) into a static cache. Without
// this, seating any pro not already in the 3-entry cache costs ~1.5s of
// synchronous simulation (5000 hands x 8 iterations) at seat-creation time,
// on the UI thread — real seat-startup latency, not a cosmetic loading-screen
// problem. A tournament field seats dozens of distinct named pros at once, so
// this is the actual multi-second "spinning wheel" the app showed on start.
//
//   dart run tool/bake_calibration_cache.dart
//
// Prints the generated `_cache` map entries to paste into
// lib/core/domain/ai/profile_calibrator.dart. Pure Dart; not shipped.
import 'package:monte/core/domain/ai/home_game_profiles.dart';
import 'package:monte/core/domain/ai/player_profile.dart';
import 'package:monte/core/domain/ai/player_profiles.dart';
import 'package:monte/core/domain/ai/profile_calibrator.dart';
import 'package:monte/core/domain/ai/profile_decider.dart';

void main() {
  final all = [...builtInProfiles, ...homeGameProfiles];
  final pros = <String, PlayerProfile>{};
  for (final p in all) {
    if (isAmateurProfile(p)) continue;
    final b = p.strategicBaseline;
    final key = '${b.vpipTarget}_${b.pfrTarget}_${b.threeBetFrequency}_6';
    pros.putIfAbsent(key, () => p);
  }

  stderr(
    'Calibrating ${pros.length} unique preflop-target combinations '
    '(out of ${all.length} profiles)...',
  );

  const calibrator = ProfileCalibrator();
  final buf = StringBuffer();
  var i = 0;
  for (final entry in pros.entries) {
    i++;
    final ranges = calibrator.calibrate(entry.value);
    stderr('[$i/${pros.length}] ${entry.key} <- ${entry.value.name}');
    buf.writeln(
      "    '${entry.key}': const PreflopRanges("
      'vpip: ${ranges.vpip}, pfr: ${ranges.pfr}, '
      'threeBet: ${ranges.threeBet}), '
      '// ${entry.value.name}',
    );
  }

  print('\n=== Paste into ProfileCalibrator._cache ===\n');
  print(buf.toString());
}

void stderr(String s) => print(s);
