import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:poker_client/core/domain/engine/card.dart' as poker;

/// Renders a single playing card, face-up or face-down.
///
/// Face-up cards mimic a real card: a rank+suit index in the top-left, the same
/// index inverted (rotated 180°) in the bottom-right, and a large suit pip in
/// the absolute centre.
class PlayingCardWidget extends StatelessWidget {
  const PlayingCardWidget({
    super.key,
    this.card,
    this.faceDown = false,
    this.width = 56,
  });

  final poker.Card? card;
  final bool faceDown;
  final double width;

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
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: radius,
        boxShadow: const [
          BoxShadow(color: Colors.black38, blurRadius: 4, offset: Offset(0, 2)),
        ],
      ),
      child: Stack(
        children: [
          // Large pip in the absolute centre of the card.
          Center(
            child: Text(
              c.suit.symbol,
              style: TextStyle(color: c.suit.color, fontSize: width * 0.52),
            ),
          ),
          // Top-left index.
          Positioned(top: width * 0.08, left: width * 0.1, child: _index(c)),
          // Bottom-right index, inverted like a real card.
          Positioned(
            bottom: width * 0.08,
            right: width * 0.1,
            child: Transform.rotate(angle: math.pi, child: _index(c)),
          ),
        ],
      ),
    );
  }

  /// A stacked rank-over-suit corner index.
  Widget _index(poker.Card c) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          c.rank.label,
          style: TextStyle(
            color: c.suit.color,
            fontSize: width * 0.28,
            fontWeight: FontWeight.bold,
            height: 1,
          ),
        ),
        Text(
          c.suit.symbol,
          style: TextStyle(
            color: c.suit.color,
            fontSize: width * 0.22,
            height: 1,
          ),
        ),
      ],
    );
  }
}
