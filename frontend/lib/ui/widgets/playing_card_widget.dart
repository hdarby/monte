import 'package:flutter/material.dart';

import '../../engine/card.dart' as poker;

/// Renders a single playing card, face-up or face-down.
class PlayingCardWidget extends StatelessWidget {
  const PlayingCardWidget({
    super.key,
    this.card,
    this.faceDown = false,
    this.width = 56,
    this.dimmed = false,
  });

  final poker.Card? card;
  final bool faceDown;
  final double width;

  /// Greyed out, e.g. for a folded player.
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    final height = width * 1.4;
    final radius = BorderRadius.circular(width * 0.13);

    if (faceDown || card == null) {
      return Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          borderRadius: radius,
          gradient: const LinearGradient(
            colors: [Color(0xFF1A3A6B), Color(0xFF2E5C9E)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          border: Border.all(color: Colors.white24, width: 1.5),
        ),
        child: Center(
          child: Container(
            width: width * 0.6,
            height: height * 0.7,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(width * 0.08),
              border: Border.all(color: Colors.white24),
            ),
          ),
        ),
      );
    }

    final c = card!;
    return Opacity(
      opacity: dimmed ? 0.45 : 1,
      child: Container(
        width: width,
        height: height,
        padding: EdgeInsets.all(width * 0.08),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: radius,
          boxShadow: const [
            BoxShadow(color: Colors.black38, blurRadius: 4, offset: Offset(0, 2)),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              c.rank.label,
              style: TextStyle(
                color: c.suit.color,
                fontSize: width * 0.34,
                fontWeight: FontWeight.bold,
                height: 1,
              ),
            ),
            Expanded(
              child: Center(
                child: Text(
                  c.suit.symbol,
                  style: TextStyle(color: c.suit.color, fontSize: width * 0.5),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
