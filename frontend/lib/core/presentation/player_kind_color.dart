import 'package:flutter/material.dart';

import 'package:monte/core/domain/ai/player_kind.dart';

/// The single source of truth for the pro / rec / human colour coding.
///
/// Blue behind recreational players, red behind pros, amber for the human.
/// Explicitly-chosen personalities get a stronger tint than anonymous
/// auto-generated field filler, so the players you picked stand out from the
/// crowd in a big tournament.
///
/// Both the tournament standings and the table seats read from here, so the two
/// can't drift apart.
extension PlayerKindColor on PlayerKind {
  /// The base hue for this kind.
  Color get hue => switch (this) {
    PlayerKind.human => Colors.amber,
    PlayerKind.pro => Colors.red,
    PlayerKind.amateur => Colors.blue,
  };

  /// The background tint for a row or seat box.
  ///
  /// [generated] dims the tint for anonymous filler players. [strength] scales
  /// the whole thing — the seats sit on a busy felt and need a touch more than
  /// the flat standings list to read at a glance.
  Color tint({bool generated = false, double strength = 1.0}) {
    final alpha = switch (this) {
      PlayerKind.human => 0.22,
      PlayerKind.pro => generated ? 0.09 : 0.22,
      PlayerKind.amateur => generated ? 0.10 : 0.24,
    };
    return hue.withValues(alpha: (alpha * strength).clamp(0.0, 1.0));
  }

  /// A stronger version of [hue] for borders and badge text, which need to read
  /// against the felt rather than sit behind content.
  Color get accent => switch (this) {
    PlayerKind.human => Colors.amber,
    PlayerKind.pro => Colors.red.shade300,
    PlayerKind.amateur => Colors.blue.shade300,
  };
}
