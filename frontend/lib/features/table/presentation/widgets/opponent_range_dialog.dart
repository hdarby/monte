import 'dart:math';

import 'package:flutter/material.dart' hide Card;
import 'package:monte/core/domain/ai/opponent_range_read.dart';
import 'package:monte/core/domain/engine/card.dart';

/// A 13×13 starting-hand grid reading a tapped opponent's likely holding: cell
/// colour shows where the hero stands (green = hero ahead, red = hero behind,
/// amber = coin-flip), cell opacity shows how likely the opponent holds it, and
/// super-premiums their passive line makes unlikely are struck through.
class OpponentRangeDialog extends StatelessWidget {
  const OpponentRangeDialog({
    super.key,
    required this.opponentName,
    required this.heroHole,
    required this.board,
    required this.vpip,
    required this.preflopRaiseLevel,
    required this.raisedPostflop,
    this.position = RangePosition.unknown,
  });

  final String opponentName;
  final List<Card> heroHole;
  final List<Card> board;
  final bool vpip;
  final int preflopRaiseLevel;
  final bool raisedPostflop;
  final RangePosition position;

  static const _ahead = Color(0xFF2E7D32); // hero ahead — green
  static const _behind = Color(0xFFC62828); // hero behind — red
  static const _split = Color(0xFFEF8E3B); // coin-flip — amber

  @override
  Widget build(BuildContext context) {
    // A one-off read on tap; a fixed seed keeps the picture stable if rebuilt.
    final read = OpponentRangeRead.estimate(
      heroHole: heroHole,
      board: board,
      vpip: vpip,
      preflopRaiseLevel: preflopRaiseLevel,
      raisedPostflop: raisedPostflop,
      position: position,
      random: Random(7),
    );
    final maxW = max(read.maxWeight, 0.0001);

    return AlertDialog(
      title: Text("$opponentName — likely range", style: const TextStyle(fontSize: 16)),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(read.note,
                style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.primary,
                    fontStyle: FontStyle.italic)),
            const SizedBox(height: 10),
            LayoutBuilder(builder: (context, box) {
              final cell = box.maxWidth / 13;
              return Column(
                children: [
                  for (var row = 0; row < 13; row++)
                    Row(
                      children: [
                        for (var col = 0; col < 13; col++)
                          _cell(read.cells[row * 13 + col], cell, maxW),
                      ],
                    ),
                ],
              );
            }),
            const SizedBox(height: 10),
            _legend(),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close')),
      ],
    );
  }

  Widget _cell(RangeReadCell c, double size, double maxW) {
    final base = switch (c.stance) {
      RangeStance.ahead => _ahead,
      RangeStance.behind => _behind,
      RangeStance.split => _split,
    };
    // Opacity tracks likelihood; negligible cells nearly vanish.
    final opacity = c.combos == 0 ? 0.0 : (0.12 + 0.88 * (c.weight / maxW));
    // Subtract the 0.5px margin on each side so 13 cells + margins fit the row
    // exactly (otherwise the Row overflows by 13px).
    final inner = (size - 1).clamp(0.0, size);
    return Container(
      width: inner,
      height: inner,
      margin: const EdgeInsets.all(0.5),
      decoration: BoxDecoration(
        color: c.combos == 0
            ? Colors.black12
            : base.withValues(alpha: opacity.clamp(0.0, 1.0)),
        borderRadius: BorderRadius.circular(2),
        border: c.unlikelyPremium
            ? Border.all(color: Colors.white70, width: 1)
            : null,
      ),
      alignment: Alignment.center,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          c.label,
          style: TextStyle(
            fontSize: 9,
            color: Colors.white.withValues(alpha: c.negligible ? 0.35 : 0.95),
            fontWeight: FontWeight.w600,
            decoration:
                c.unlikelyPremium ? TextDecoration.lineThrough : null,
          ),
        ),
      ),
    );
  }

  Widget _legend() => Wrap(
        spacing: 12,
        runSpacing: 4,
        children: [
          _swatch(_ahead, 'You ahead'),
          _swatch(_behind, 'You behind'),
          _swatch(_split, 'Coin-flip'),
          Row(mainAxisSize: MainAxisSize.min, children: const [
            Text('A̶A̶',
                style: TextStyle(
                    fontSize: 11,
                    color: Colors.white70,
                    decoration: TextDecoration.lineThrough)),
            SizedBox(width: 4),
            Text('unlikely', style: TextStyle(fontSize: 11, color: Colors.white70)),
          ]),
          const Text('· brighter = more likely',
              style: TextStyle(fontSize: 11, color: Colors.white54)),
        ],
      );

  Widget _swatch(Color c, String label) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 12, height: 12, color: c),
          const SizedBox(width: 4),
          Text(label, style: const TextStyle(fontSize: 11, color: Colors.white70)),
        ],
      );
}
