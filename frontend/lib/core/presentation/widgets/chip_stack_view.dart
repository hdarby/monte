import 'package:flutter/material.dart';

import 'package:monte/core/domain/engine/chip_breakdown.dart';

/// Casino chip colours by denomination: body plus edge spots.
///
/// Edge spots are what actually distinguishes chips in play — 100 and 500,000
/// are both black, and it is the blue vs red spots that tell them apart. Seen
/// side-on they read as vertical stripes across the chip's rim, which is exactly
/// how you identify a stack across a real table.
///
/// A null [spot] means a solid chip, which is normal at the low denominations.
const _chipColors = <int, ({Color body, Color? spot})>{
  1: (body: Color(0xFFF5F5F5), spot: null), // white
  5: (body: Color(0xFFD32F2F), spot: null), // red
  25: (body: Color(0xFF2E7D32), spot: null), // green
  100: (body: Color(0xFF1A1A1A), spot: Color(0xFF1565C0)), // black / blue
  500: (body: Color(0xFF6A1B9A), spot: Color(0xFFF57C00)), // purple / orange
  1000: (body: Color(0xFFFDD835), spot: Color(0xFF757575)), // yellow / gray
  5000: (body: Color(0xFFF4511E), spot: Color(0xFFFFFFFF)), // blaze / white
  25000: (body: Color(0xFF1B5E20), spot: Color(0xFF8B0000)), // forest / dk red
  100000: (body: Color(0xFF1565C0), spot: Color(0xFFFDD835)), // blue / yellow
  250000: (body: Color(0xFFD7CCA3), spot: Color(0xFF8C6A3F)), // beige / bronze
  500000: (body: Color(0xFF1A1A1A), spot: Color(0xFFD32F2F)), // black / red
  1000000: (body: Color(0xFFEF6C00), spot: Color(0xFFFDD835)), // orange / yellow
  5000000: (body: Color(0xFF9E9E9E), spot: Color(0xFF6A1B9A)), // gray / purple
};

/// The body and spot colours for a denomination, plus a derived rim shade.
///
/// An unlisted denomination falls back to the next one down, so an unusual chip
/// set still gets a stable, sensible colour rather than grey.
({Color body, Color? spot, Color edge}) chipColorFor(int denomination) {
  var pick = _chipColors[denomination];
  if (pick == null) {
    final keys = _chipColors.keys.toList()..sort();
    var best = keys.first;
    for (final k in keys) {
      if (k <= denomination) best = k;
    }
    pick = _chipColors[best]!;
  }
  return (
    body: pick.body,
    spot: pick.spot,
    // The rim is the body in shadow — what gives the slab its cylinder edge.
    edge: Color.lerp(pick.body, Colors.black, 0.55)!,
  );
}

/// A player's chips, drawn side-on: one column per denomination, its height the
/// number of chips held.
///
/// Deliberately a *view of the stack*, not a replacement for the number — the
/// numeric total stays on the seat. This is table flavour: you should be able to
/// glance at the felt and see who is deep and who is short without reading.
class ChipStackView extends StatelessWidget {
  const ChipStackView({
    super.key,
    required this.amount,
    required this.denominations,
    required this.reference,
    this.minDenomination = 1,
    this.maxHeight = 34,
    this.chipWidth = 13,
    this.chipHeight = 3.2,
    this.maxColumns = 5,
    this.maxChips = 60,
  });

  /// The chip count to draw.
  final int amount;

  /// The denominations in play, ascending.
  final List<int> denominations;

  /// The stack that fills the graphic — normally the biggest stack at the table.
  ///
  /// Height has to mean something *comparable across seats*, so it is scaled
  /// against a shared reference rather than drawn as literal chip counts. Drawn
  /// literally, greedy denominations invert the picture: a 500,000 stack is one
  /// plaque and a 5,000 stack is one chip, so the chip leader would look
  /// identical to the short stack.
  final int reference;

  /// The smallest chip actually on the table at this level.
  final int minDenomination;

  /// Tallest the stack may be drawn.
  final double maxHeight;

  final double chipWidth;
  final double chipHeight;
  final int maxColumns;

  /// Chips drawn for a stack equal to [reference].
  final int maxChips;

  @override
  Widget build(BuildContext context) {
    final breakdown = ChipBreakdown.of(
      amount,
      denominations: denominations,
      minDenomination: minDenomination,
      maxColumns: maxColumns,
    );
    if (breakdown.isEmpty) return SizedBox(height: maxHeight);

    // Capacity is fixed by the space available: chips per column x columns.
    // Deriving the total from this (rather than clipping each column afterwards)
    // keeps height monotonic in stack size — clipping per column made a
    // single-denomination monster draw *shorter* than a mixed one.
    final perColumn = (maxHeight / (chipHeight + 0.6)).floor().clamp(1, 40);
    final capacity = (perColumn * maxColumns).clamp(1, maxChips);

    final ref = reference > 0 ? reference : amount;
    final total = (capacity * amount / ref).round().clamp(1, capacity);

    // Allocate the drawn chips across denominations in proportion to how many
    // of each the player *actually holds*, so the colours on screen reflect the
    // real composition of the stack rather than an arbitrary column order.
    final held = breakdown.chipCount;
    final alloc = <int, int>{};
    var assigned = 0;
    for (var i = 0; i < breakdown.columns.length; i++) {
      final c = breakdown.columns[i];
      final isLast = i == breakdown.columns.length - 1;
      var n = isLast
          ? total - assigned
          : (total * (held <= 0 ? 0 : c.count / held)).round();
      if (n < 1 && !isLast) n = 1;
      if (assigned + n > total) n = total - assigned;
      if (n <= 0) continue;
      alloc[c.denomination] = n;
      assigned += n;
    }

    // Lay them out largest denomination first, spilling into a fresh column of
    // the same colour whenever one fills up — the way a real stack is set down.
    final drawn = <ChipColumn>[];
    for (final entry in alloc.entries) {
      var remaining = entry.value;
      while (remaining > 0 && drawn.length < maxColumns) {
        final n = remaining > perColumn ? perColumn : remaining;
        drawn.add(ChipColumn(denomination: entry.key, count: n));
        remaining -= n;
      }
      if (drawn.length >= maxColumns) break;
    }

    return SizedBox(
      height: maxHeight,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final column in drawn)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 1),
              child: _Column(
                column: column,
                chipWidth: chipWidth,
                chipHeight: chipHeight,
              ),
            ),
        ],
      ),
    );
  }
}

/// One denomination's column of chips, seen edge-on.
class _Column extends StatelessWidget {
  const _Column({
    required this.column,
    required this.chipWidth,
    required this.chipHeight,
  });

  final ChipColumn column;
  final double chipWidth;
  final double chipHeight;

  @override
  Widget build(BuildContext context) {
    final colors = chipColorFor(column.denomination);

    return Tooltip(
      message: _short(column.denomination),
      waitDuration: const Duration(milliseconds: 400),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          for (var i = 0; i < column.count; i++)
            _Chip(
              width: chipWidth,
              height: chipHeight,
              body: colors.body,
              edge: colors.edge,
              spot: colors.spot,
              // The top chip of a column catches the light.
              highlight: i == column.count - 1,
            ),
        ],
      ),
    );
  }

  /// 25000 -> "25k", 1000000 -> "1M".
  static String _short(int v) {
    if (v >= 1000000) {
      final m = v / 1000000;
      return '${m == m.roundToDouble() ? m.round() : m}M';
    }
    if (v >= 1000) {
      final k = v / 1000;
      return '${k == k.roundToDouble() ? k.round() : k}k';
    }
    return '$v';
  }
}

/// A single chip seen from the side: a thin rounded slab with a darker rim.
class _Chip extends StatelessWidget {
  const _Chip({
    required this.width,
    required this.height,
    required this.body,
    required this.edge,
    required this.spot,
    required this.highlight,
  });

  final double width;
  final double height;
  final Color body;
  final Color edge;

  /// Edge-spot colour, or null for a solid chip.
  final Color? spot;

  final bool highlight;

  /// Edge spots, seen side-on, as vertical stripes across the rim. Built as a
  /// horizontal gradient with hard stops so it stays crisp at ~3px tall.
  static const _spotCount = 3;

  LinearGradient? get _spots {
    final c = spot;
    if (c == null) return null;
    final colors = <Color>[];
    final stops = <double>[];
    // Three stripes, each ~14% of the width, evenly spaced.
    const band = 0.14;
    for (var i = 0; i < _spotCount; i++) {
      final centre = (i + 1) / (_spotCount + 1);
      final from = (centre - band / 2).clamp(0.0, 1.0);
      final to = (centre + band / 2).clamp(0.0, 1.0);
      colors.addAll([Colors.transparent, c, c, Colors.transparent]);
      stops.addAll([from - 0.001, from, to, to + 0.001]);
    }
    return LinearGradient(colors: colors, stops: stops);
  }

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(height / 2 + 0.6);
    final spots = _spots;

    return Container(
      width: width,
      height: height,
      margin: const EdgeInsets.only(bottom: 0.6),
      decoration: BoxDecoration(
        // A vertical gradient reads as a cylinder edge rather than a flat bar.
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color.lerp(body, Colors.white, highlight ? 0.45 : 0.22)!,
            body,
            edge,
          ],
          stops: const [0.0, 0.55, 1.0],
        ),
        borderRadius: radius,
        border: Border.all(color: edge.withValues(alpha: 0.9), width: 0.3),
      ),
      // Edge spots sit over the body, inset so the rim still reads as a rim.
      child: spots == null
          ? null
          : ClipRRect(
              borderRadius: radius,
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: height * 0.18),
                child: DecoratedBox(
                  decoration: BoxDecoration(gradient: spots),
                  child: const SizedBox.expand(),
                ),
              ),
            ),
    );
  }
}
