import 'package:flutter/material.dart';
import 'package:monte/core/util/format.dart';

/// A player name that shows as much of itself as will fit: the full
/// "First Last" when there's room, falling back to the abbreviated
/// "F. Last" (the seat-display convention) when there isn't.
///
/// Used by the tournament standings, where the panel is narrow enough that a
/// plain ellipsis would truncate most names but wide enough that many still fit.
class AdaptivePlayerName extends StatelessWidget {
  const AdaptivePlayerName({
    super.key,
    required this.name,
    required this.style,
    this.isHuman = false,
  });

  final String name;
  final bool isHuman;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final full = displayName(firstLastName(name), isHuman: isHuman);
        final short = displayName(abbreviateName(name), isHuman: isHuman);

        // Measure the full name; only abbreviate when it genuinely overflows.
        final painter = TextPainter(
          text: TextSpan(text: full, style: style),
          maxLines: 1,
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: double.infinity);

        return Text(
          painter.width <= constraints.maxWidth ? full : short,
          overflow: TextOverflow.ellipsis,
          maxLines: 1,
          style: style,
        );
      },
    );
  }
}
