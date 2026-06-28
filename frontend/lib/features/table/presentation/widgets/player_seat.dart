import 'package:flutter/material.dart';

import 'package:monte/features/table/domain/table_snapshot.dart';
import 'package:monte/core/theme/app_theme.dart';
import 'package:monte/core/presentation/money_format.dart';
import 'package:monte/features/table/presentation/widgets/dealer_button.dart';
import 'package:monte/features/table/presentation/widgets/playing_card_widget.dart';

/// Where the dealer button sits relative to a seat box. Always the edge facing
/// the centre of the table, so the button unambiguously fronts one player.
enum ButtonPlacement { none, above, below, left, right }

/// One player's seat: name, stack, hole cards and live status.
class PlayerSeat extends StatelessWidget {
  const PlayerSeat({
    super.key,
    required this.seat,
    this.compact = false,
    this.buttonPlacement = ButtonPlacement.none,
    this.showBehavior = false,
  });

  final SeatView seat;
  final bool compact;

  /// Which edge of this box the dealer button hugs. Only honoured when this
  /// seat actually has the button ([SeatView.isButton]).
  final ButtonPlacement buttonPlacement;

  /// Whether to show this seat's behavior model badge ([SeatView.behavior]).
  final bool showBehavior;

  /// One hole-card's width; the seat's whole footprint is derived from this so
  /// the box stays a fixed size regardless of name/badge/status text length.
  double get _cardWidth => compact ? 34.0 : 60.0;

  /// The seat's content width: two cards plus the gap between them. Names,
  /// badges and status tags are all bounded to this so they can't widen the box
  /// and make neighbouring seats overlap.
  double get _contentWidth => _cardWidth * 2 + 4;

  @override
  Widget build(BuildContext context) {
    final highlight = seat.isCurrent;
    final money = MoneyScope.of(context);

    // A dead (folded) hand fades back so it's obviously out of play.
    final box = AnimatedOpacity(
      duration: const Duration(milliseconds: 250),
      opacity: seat.folded ? 0.4 : 1,
      child: _seat(highlight, money),
    );

    if (!seat.isButton || buttonPlacement == ButtonPlacement.none) return box;

    // The button straddles the centre-facing edge — mostly outside the box, a
    // little overlap so it reads as attached to this seat.
    return Stack(
      clipBehavior: Clip.none,
      children: [box, _button()],
    );
  }

  Widget _button() {
    final button = DealerButton(size: compact ? 26 : 30);
    // Above/below seats clear the hole cards entirely (the disc sits on the felt
    // between the player and the board); side seats tuck just off the inner
    // edge, where there are no cards to hide behind.
    const edge = -34.0;
    const side = -18.0;
    switch (buttonPlacement) {
      case ButtonPlacement.above:
        return Positioned(
          top: edge,
          left: 0,
          right: 0,
          child: Center(child: button),
        );
      case ButtonPlacement.below:
        return Positioned(
          bottom: edge,
          left: 0,
          right: 0,
          child: Center(child: button),
        );
      case ButtonPlacement.left:
        return Positioned(
          left: side,
          top: 0,
          bottom: 0,
          child: Center(child: button),
        );
      case ButtonPlacement.right:
        return Positioned(
          right: side,
          top: 0,
          bottom: 0,
          child: Center(child: button),
        );
      case ButtonPlacement.none:
        return const SizedBox.shrink();
    }
  }

  Widget _seat(bool highlight, MoneyFormat money) {
    // The box shrink-wraps its widest child — the two hole cards. Names, badges
    // and status tags are each bounded to [_contentWidth], so none of them can
    // grow the box past the cards and overlap the next seat.
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: highlight
            ? AppTheme.gold.withValues(alpha: 0.18)
            : Colors.black26,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: highlight ? AppTheme.gold : Colors.white10,
          width: highlight ? 2 : 1,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _cards(),
          const SizedBox(height: 6),
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: _contentWidth),
            child: Text(
              seat.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: compact ? 13 : 15,
              ),
            ),
          ),
          if (showBehavior && seat.behavior != null) _behaviorBadge(),
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

  Widget _cards() {
    final faceDown = seat.holeCards == null;
    final cards = seat.holeCards ?? const [];
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < 2; i++) ...[
          PlayingCardWidget(
            card: faceDown ? null : (i < cards.length ? cards[i] : null),
            faceDown: faceDown,
            width: _cardWidth,
          ),
          if (i == 0) const SizedBox(width: 4),
        ],
      ],
    );
  }

  /// A small muted badge naming the bot's behavior model (brain + style),
  /// bounded to the seat width and ellipsised if a label is unusually long.
  Widget _behaviorBadge() => Container(
    margin: const EdgeInsets.only(top: 3),
    constraints: BoxConstraints(maxWidth: _contentWidth),
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
    decoration: BoxDecoration(
      color: Colors.black.withValues(alpha: 0.3),
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: AppTheme.gold.withValues(alpha: 0.35)),
    ),
    child: Text(
      seat.behavior!,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: AppTheme.gold.withValues(alpha: 0.85),
        fontSize: compact ? 9.5 : 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.3,
      ),
    ),
  );

  Widget _statusLine(MoneyFormat money) {
    if (seat.wonAmount > 0) {
      return _tag(
        'WON +${money.format(seat.wonAmount)}',
        AppTheme.gold,
        Colors.black,
      );
    }
    if (seat.folded) return _tag('FOLDED', Colors.white24, Colors.white);
    if (seat.allIn) return _tag('ALL-IN', AppTheme.chip, Colors.white);
    if (seat.handLabel != null) {
      return _tag(seat.handLabel!.toUpperCase(), Colors.white12, Colors.white);
    }
    if (seat.currentBet > 0) {
      return _tag(
        'BET ${money.format(seat.currentBet)}',
        AppTheme.feltEdge,
        Colors.white,
      );
    }
    return const SizedBox(height: 22);
  }

  Widget _tag(String text, Color bg, Color fg) => Container(
    margin: const EdgeInsets.only(top: 4),
    constraints: BoxConstraints(maxWidth: _contentWidth),
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(color: fg, fontSize: 11, fontWeight: FontWeight.bold),
    ),
  );
}
