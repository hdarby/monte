import 'package:flutter/material.dart';

import 'package:monte/core/domain/engine/card.dart';

/// Display colour for a card suit. This is a presentation concern, kept out of
/// the framework-free engine (`core/domain/engine/card.dart`).
extension SuitColor on Suit {
  Color get color => switch (this) {
    Suit.hearts || Suit.diamonds => const Color(0xFFD32F2F),
    Suit.spades || Suit.clubs => const Color(0xFF1A1A1A),
  };
}
