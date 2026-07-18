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
    this.onCoach,
  });

  final SeatView seat;
  final bool compact;

  /// Tapped to open the in-hand coach. Only shown on the human seat.
  final VoidCallback? onCoach;

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

    final showButton = seat.isButton && buttonPlacement != ButtonPlacement.none;
    final showCoach = seat.isHuman && onCoach != null;
    if (!showButton && !showCoach) return box;

    // Overlays straddle the box edges (clipped none) so they read as attached.
    return Stack(
      clipBehavior: Clip.none,
      children: [
        box,
        if (showButton) _button(),
        if (showCoach) _coachIcon(),
      ],
    );
  }

  /// A small "?" coach button pinned to the seat's top-right corner.
  Widget _coachIcon() => Positioned(
    top: -10,
    right: -10,
    child: Material(
      color: AppTheme.gold,
      shape: const CircleBorder(),
      elevation: 2,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onCoach,
        child: const Padding(
          padding: EdgeInsets.all(4),
          child: Icon(Icons.school, size: 16, color: Colors.black),
        ),
      ),
    ),
  );

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
    final ms = _moneyStatus(money);
    // A bet/won amount can be far too long for the small compact tag, so on the
    // bot seats (which only show card backs anyway) we paint it as a banner over
    // the whole card footprint — maximum room, so it rarely has to shrink. The
    // human keeps their live cards; their amount renders in the tag below.
    final overwriteCards = ms != null && !seat.isHuman;
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
          overwriteCards ? _moneyBanner(ms) : _cards(),
          const SizedBox(height: 6),
          _name(),
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
          _statusLine(money, suppressMoney: overwriteCards),
        ],
      ),
    );
  }

  /// The player's name, scaled to fit the seat width without ellipsis. If the
  /// full name is too wide even at the base size, it collapses to a first
  /// initial + last name ("Jonathan Little" → "J. Little"); [FittedBox] then
  /// shrinks whatever remains just enough to fit, so a name is never truncated.
  Widget _name() {
    final base = compact ? 13.0 : 15.0;
    return SizedBox(
      width: _contentWidth,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.center,
        child: Text(
          _displayName(base),
          maxLines: 1,
          softWrap: false,
          style: TextStyle(fontWeight: FontWeight.w600, fontSize: base),
        ),
      ),
    );
  }

  /// Full name if it fits at [fontSize]; otherwise "F. Lastname".
  String _displayName(double fontSize) {
    final full = seat.name.trim();
    if (_fits(full, fontSize)) return full;
    final parts = full.split(RegExp(r'\s+'));
    if (parts.length >= 2 && parts.first.isNotEmpty) {
      return '${parts.first[0]}. ${parts.last}';
    }
    return full;
  }

  /// Whether [text] fits within [_contentWidth] at [fontSize] on one line.
  bool _fits(String text, double fontSize) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w600),
      ),
      maxLines: 1,
      textDirection: TextDirection.ltr,
    )..layout();
    return tp.width <= _contentWidth;
  }

  /// The bet / won status as a `(text, bg, fg)` triple, or null when the seat
  /// has no monetary state to show. Shared by the over-card banner (bots) and
  /// the tag below (human) so both read the same colours and wording.
  ({String text, Color bg, Color fg})? _moneyStatus(MoneyFormat money) {
    if (seat.wonAmount > 0) {
      return (
        text: '${seat.wonIsChop ? 'CHOP' : 'WON'} +${money.format(seat.wonAmount)}',
        bg: AppTheme.gold,
        fg: Colors.black,
      );
    }
    if (seat.currentBet > 0) {
      // Escalate the colour with the raise level: blinds/limps stay neutral, the
      // initial raise is yellow, a 3-bet orange, a 4-bet+ red. A call takes the
      // colour of the level it called.
      final bg = switch (seat.raiseLevel) {
        >= 3 => AppTheme.alarmRed,
        2 => AppTheme.warnOrange,
        1 => AppTheme.betYellow,
        _ => AppTheme.feltEdge,
      };
      final fg = seat.raiseLevel == 1 ? Colors.black : Colors.white;
      final verb = seat.wagerIsCall ? 'CALL' : 'BET';
      return (text: '$verb ${money.format(seat.currentBet)}', bg: bg, fg: fg);
    }
    return null;
  }

  /// A bet/won amount painted across the whole card footprint, giving even long
  /// amounts room to render large; [FittedBox] shrinks only if truly necessary.
  Widget _moneyBanner(({String text, Color bg, Color fg}) ms) => Container(
    width: _contentWidth,
    height: _cardWidth * 1.4,
    alignment: Alignment.center,
    padding: const EdgeInsets.symmetric(horizontal: 6),
    decoration: BoxDecoration(
      color: ms.bg,
      borderRadius: BorderRadius.circular(8),
    ),
    child: FittedBox(
      fit: BoxFit.scaleDown,
      child: Text(
        ms.text,
        maxLines: 1,
        softWrap: false,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: ms.fg,
          fontSize: 16,
          fontWeight: FontWeight.bold,
        ),
      ),
    ),
  );

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

  /// The tag beneath the stack. When [suppressMoney] is set the bet/won amount
  /// is already shown as the over-card banner, so this only carries the
  /// remaining states (folded / all-in / made-hand label).
  Widget _statusLine(MoneyFormat money, {bool suppressMoney = false}) {
    final ms = suppressMoney ? null : _moneyStatus(money);
    // Won takes priority over everything else at showdown.
    if (ms != null && seat.wonAmount > 0) return _tag(ms.text, ms.bg, ms.fg);
    if (seat.folded) return _tag('FOLDED', Colors.white24, Colors.white);
    if (seat.allIn) return _tag('ALL-IN', AppTheme.chip, Colors.white);
    if (seat.handLabel != null) {
      return _tag(seat.handLabel!.toUpperCase(), Colors.white12, Colors.white);
    }
    if (ms != null) return _tag(ms.text, ms.bg, ms.fg);
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
    // Scale the text down to fit rather than ellipsising it, so amounts stay
    // fully legible even in the narrow compact seats.
    child: FittedBox(
      fit: BoxFit.scaleDown,
      child: Text(
        text,
        maxLines: 1,
        softWrap: false,
        style: TextStyle(color: fg, fontSize: 11, fontWeight: FontWeight.bold),
      ),
    ),
  );
}
