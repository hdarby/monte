/// The tournament chronicle: everything that turns real hand results into the
/// between-levels recap.
///
/// This is a barrel — the pieces live in `chronicle/`:
///
/// - `hand_digest.dart`   what the controller reports after each hand
/// - `hand_replay.dart`   a full replay of one hand, for the feature hand
/// - `level_recap.dart`   the recap the UI renders, and its line types
/// - `tournament_chronicle.dart`  the narrator that accumulates and generates
library;

export 'package:monte/features/tournament/domain/chronicle/hand_digest.dart';
export 'package:monte/features/tournament/domain/chronicle/hand_replay.dart';
export 'package:monte/features/tournament/domain/chronicle/level_recap.dart';
export 'package:monte/features/tournament/domain/chronicle/tournament_chronicle.dart';
