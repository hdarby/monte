import 'package:flutter/material.dart';

import '../../data/table_snapshot.dart';
import '../../theme/app_theme.dart';
import '../money_format.dart';
import 'playing_card_widget.dart';

/// The centre of the table: pot, round label and the five community slots.
class CommunityBoard extends StatelessWidget {
  const CommunityBoard({super.key, required this.snapshot});

  final TableSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.black38,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppTheme.gold.withValues(alpha: 0.5)),
          ),
          child: Text(
            'POT  ${MoneyScope.of(context).format(snapshot.pot)}',
            style: const TextStyle(
              color: AppTheme.gold,
              fontSize: 20,
              fontWeight: FontWeight.bold,
              letterSpacing: 1,
            ),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < 5; i++) ...[
              i < snapshot.board.length
                  ? PlayingCardWidget(card: snapshot.board[i], width: 64)
                  : _placeholder(),
              if (i < 4) const SizedBox(width: 8),
            ],
          ],
        ),
        const SizedBox(height: 12),
        Text(
          snapshot.round.label.toUpperCase(),
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.7),
            letterSpacing: 3,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _placeholder() => Container(
        width: 64,
        height: 64 * 1.4,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white12),
          color: Colors.black12,
        ),
      );
}
