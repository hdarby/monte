import 'package:flutter/material.dart';

import 'package:poker_client/features/table/domain/table_snapshot.dart';
import 'package:poker_client/core/theme/app_theme.dart';
import 'package:poker_client/core/presentation/money_format.dart';
import 'package:poker_client/features/table/presentation/widgets/playing_card_widget.dart';

/// One player's seat: name, stack, hole cards and live status.
class PlayerSeat extends StatelessWidget {
  const PlayerSeat({super.key, required this.seat, this.compact = false});

  final SeatView seat;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final cardWidth = compact ? 34.0 : 60.0;
    final highlight = seat.isCurrent;
    final money = MoneyScope.of(context);

    // A dead (folded) hand fades back so it's obviously out of play.
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 250),
      opacity: seat.folded ? 0.4 : 1,
      child: _seat(cardWidth, highlight, money),
    );
  }

  Widget _seat(double cardWidth, bool highlight, MoneyFormat money) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: highlight ? AppTheme.gold.withValues(alpha: 0.18) : Colors.black26,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: highlight ? AppTheme.gold : Colors.white10,
          width: highlight ? 2 : 1,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _cards(cardWidth),
          const SizedBox(height: 6),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (seat.isButton) _badge('D', AppTheme.gold, Colors.black),
              if (seat.isButton) const SizedBox(width: 4),
              Text(
                seat.name,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: compact ? 13 : 15,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            money.format(seat.stack),
            style: TextStyle(
              color: AppTheme.gold,
              fontSize: compact ? 12 : 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          _statusLine(money),
        ],
      ),
    );
  }

  Widget _cards(double width) {
    final faceDown = seat.holeCards == null;
    final cards = seat.holeCards ?? const [];
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < 2; i++) ...[
          PlayingCardWidget(
            card: faceDown ? null : (i < cards.length ? cards[i] : null),
            faceDown: faceDown,
            width: width,
          ),
          if (i == 0) const SizedBox(width: 4),
        ],
      ],
    );
  }

  Widget _statusLine(MoneyFormat money) {
    if (seat.wonAmount > 0) {
      return _tag('WON +${money.format(seat.wonAmount)}', AppTheme.gold,
          Colors.black);
    }
    if (seat.folded) return _tag('FOLDED', Colors.white24, Colors.white);
    if (seat.allIn) return _tag('ALL-IN', AppTheme.chip, Colors.white);
    if (seat.handLabel != null) {
      return _tag(seat.handLabel!.toUpperCase(), Colors.white12, Colors.white);
    }
    if (seat.currentBet > 0) {
      return _tag('BET ${money.format(seat.currentBet)}', AppTheme.feltEdge,
          Colors.white);
    }
    return const SizedBox(height: 22);
  }

  Widget _tag(String text, Color bg, Color fg) => Container(
        margin: const EdgeInsets.only(top: 4),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration:
            BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
        child: Text(text,
            style: TextStyle(
                color: fg, fontSize: 11, fontWeight: FontWeight.bold)),
      );

  Widget _badge(String text, Color bg, Color fg) => Container(
        width: 20,
        height: 20,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
        child: Text(text,
            style: TextStyle(
                color: fg, fontSize: 12, fontWeight: FontWeight.bold)),
      );
}
