import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:monte/core/domain/engine/actions.dart';
import 'package:monte/core/domain/engine/card.dart' as poker;
import 'package:monte/core/domain/engine/game.dart';
import 'package:monte/core/domain/hand_history.dart';
import 'package:monte/core/theme/app_theme.dart';
import 'package:monte/features/history/presentation/history_view_model.dart';
import 'package:monte/features/table/presentation/widgets/playing_card_widget.dart';

/// Reviews recorded hands (newest first): board, each dealt player's exposed
/// cards (folded/mucked hands stay face-down), and the result. Data comes from
/// [historyViewModelProvider]; only cards that were actually shown are stored.
class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(historyViewModelProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Hand History'),
        backgroundColor: AppTheme.surface,
      ),
      body: state.isEmpty
          ? const Center(
              child: Text(
                'No hands played yet.',
                style: TextStyle(color: Colors.white54, fontSize: 16),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: state.hands.length,
              itemBuilder: (_, i) => _HandCard(hand: state.hands[i]),
            ),
    );
  }
}

class _HandCard extends StatelessWidget {
  const _HandCard({required this.hand});

  final HandHistory hand;

  @override
  Widget build(BuildContext context) {
    final wonById = {for (final r in hand.results) r.playerId: r};
    return Card(
      color: AppTheme.surface,
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'Hand #${hand.handNumber}',
                  style: const TextStyle(
                    color: AppTheme.gold,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  'blinds ${hand.smallBlind}/${hand.bigBlind}',
                  style: const TextStyle(color: Colors.white38, fontSize: 12),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _board(),
            const SizedBox(height: 12),
            for (final p in hand.players) _playerRow(p, wonById[p.id]),
            if (hand.actions.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Divider(color: Colors.white12, height: 1),
              const SizedBox(height: 10),
              _actionLog(),
            ],
          ],
        ),
      ),
    );
  }

  /// The betting sequence, grouped by street with the board revealed as it came.
  Widget _actionLog() {
    final names = {for (final p in hand.players) p.id: p.name};
    final rows = <Widget>[];
    BettingRound? street;
    for (final a in hand.actions) {
      if (a.street != street) {
        street = a.street;
        rows.add(_streetHeader(street));
      }
      rows.add(_actionLine(names[a.playerId] ?? a.playerId, a));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: rows,
    );
  }

  Widget _streetHeader(BettingRound street) {
    final board = switch (street) {
      BettingRound.flop => hand.board.take(3),
      BettingRound.turn => hand.board.take(4),
      BettingRound.river => hand.board.take(5),
      _ => const <String>[],
    }.join(' ');
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 2),
      child: Text(
        board.isEmpty ? street.label.toUpperCase() : '${street.label.toUpperCase()}  $board',
        style: const TextStyle(
          color: AppTheme.gold,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 1,
        ),
      ),
    );
  }

  Widget _actionLine(String name, ActionRecord a) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 1),
        child: Row(
          children: [
            Expanded(
              child: Text(
                '$name ${_describe(a)}',
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
            ),
            Text(
              'pot ${a.potAfter}',
              style: const TextStyle(color: Colors.white24, fontSize: 11),
            ),
          ],
        ),
      );

  static String _describe(ActionRecord a) => switch (a.type) {
        ActionType.fold => 'folds',
        ActionType.check => 'checks',
        ActionType.call => 'calls ${a.amount}',
        ActionType.bet => 'bets ${a.amount}',
        ActionType.raise => 'raises to ${a.amount}',
        ActionType.allIn => 'all-in ${a.amount}',
      };

  Widget _board() {
    if (hand.board.isEmpty) {
      return const Text(
        '(folded preflop — no board)',
        style: TextStyle(color: Colors.white38, fontSize: 12),
      );
    }
    return Row(
      children: [
        for (final code in hand.board) ...[
          PlayingCardWidget(card: poker.Card.fromCode(code), width: 34),
          const SizedBox(width: 4),
        ],
      ],
    );
  }

  Widget _playerRow(HandPlayer p, HandResultRecord? result) {
    final btn = p.isButton ? ' [BTN]' : '';
    final net = hand.netFor(p.id);
    final netColor = net > 0
        ? Colors.greenAccent
        : (net < 0 ? Colors.redAccent : Colors.white54);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          _holeCards(p),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${p.name}$btn',
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                ),
                if (result != null && result.amountWon > 0)
                  Text(
                    'wins ${result.amountWon}'
                    '${result.handRank != null ? ' (${result.handRank})' : ''}',
                    style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 12,
                    ),
                  ),
              ],
            ),
          ),
          Text(
            net > 0 ? '+$net' : '$net',
            style: TextStyle(color: netColor, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Widget _holeCards(HandPlayer p) {
    // Revealed players show their cards; folded/mucked hands stay face-down.
    final faceDown = !p.revealed || p.holeCards.length < 2;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < 2; i++) ...[
          PlayingCardWidget(
            card: faceDown ? null : poker.Card.fromCode(p.holeCards[i]),
            faceDown: faceDown,
            width: 30,
          ),
          if (i == 0) const SizedBox(width: 3),
        ],
      ],
    );
  }
}
