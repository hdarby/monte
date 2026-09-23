import 'package:flutter/material.dart';
import 'package:monte/features/tournament/domain/chronicle/hand_replay.dart';
import 'package:monte/features/tournament/presentation/widgets/feature_hand_view.dart';

/// Shown from the action bar's "previous hand" button — a player who looked
/// away or acted too quickly to read the result can still see what just
/// happened at their own table. Independent of the level recap's one
/// narrated feature hand, which may be a different table or never chosen at
/// all: this is always *this* player's own most recent hand.
class PreviousHandDialog extends StatelessWidget {
  const PreviousHandDialog({
    super.key,
    required this.hand,
    required this.bigBlind,
    required this.fallbackSummary,
  });

  /// The narrated replay, or null when the hand ended too early for one (see
  /// [ReplayBuilder.build]) — [fallbackSummary] carries that case instead.
  final HandReplay? hand;
  final int bigBlind;
  final String? fallbackSummary;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('The previous hand'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380, maxHeight: 460),
        child: SingleChildScrollView(
          child: hand != null
              ? FeatureHandView(hand: hand!, bigBlind: bigBlind)
              : Text(
                  fallbackSummary ?? 'No hand has been played yet.',
                  style: const TextStyle(fontSize: 13, height: 1.3),
                ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Back to the felt'),
        ),
      ],
    );
  }
}
