import 'package:flutter/material.dart';

import 'package:monte/core/domain/engine/chip_breakdown.dart';

/// Casino chip colours by denomination, following standard US/WSOP convention.
///
/// Values not in the table fall back to the next one down, so an unusual
/// denomination still gets a sensible, stable colour rather than grey.
const _chipColors = <int, ({Color body, Color edge})>{
  1: (body: Color(0xFFF5F5F5), edge: Color(0xFF9E9E9E)), // white
  5: (body: Color(0xFFE53935), edge: Color(0xFF8E1B18)), // red
  25: (body: Color(0xFF2E7D32), edge: Color(0xFF134716)), // green
  100: (body: Color(0xFF212121), edge: Color(0xFF000000)), // black
  500: (body: Color(0xFF7B1FA2), edge: Color(0xFF3E0F52)), // purple
  1000: (body: Color(0xFFFDD835), edge: Color(0xFF9A8100)), // yellow
  5000: (body: Color(0xFFEF6C00), edge: Color(0xFF7A3600)), // orange
  25000: (body: Color(0xFF00ACC1), edge: Color(0xFF00565F)), // light blue
  100000: (body: Color(0xFFD81B60), edge: Color(0xFF6D0D30)), // magenta
  500000: (body: Color(0xFF6D4C41), edge: Color(0xFF33231C)), // brown
  1000000: (body: Color(0xFF1565C0), edge: Color(0xFF0A3260)), // blue
  5000000: (body: Color(0xFFC0CA33), edge: Color(0xFF5F651A)), // lime
};

({Color body, Color edge}) chipColorFor(int denomination) {
  if (_chipColors.containsKey(denomination)) return _chipColors[denomination]!;
  final keys = _chipColors.keys.toList()..sort();
  var pick = keys.first;
  for (final k in keys) {
    if (k <= denomination) pick = k;
  }
  return _chipColors[pick]!;
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
    this.maxColumns = 3,
    this.maxChips = 30,
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

    // Capacity is fixed by the space available: how many chips fit in a column,
    // times how many columns we allow. Deriving the total from this (rather than
    // clipping each column afterwards) is what keeps height monotonic — clipping
    // per column made a single-denomination monster stack draw *shorter* than a
    // mixed one, which is exactly backwards.
    final perColumn = (maxHeight / (chipHeight + 0.6)).floor().clamp(1, 40);
    final capacity = (perColumn * maxColumns).clamp(1, maxChips);

    final ref = reference > 0 ? reference : amount;
    final total = (capacity * amount / ref).round().clamp(1, capacity);

    // Fill left to right, biggest chips first, each column to its limit before
    // starting the next — the way a real stack grows.
    final columnsUsed = (total / perColumn).ceil();
    final denoms = breakdown.columns.map((c) => c.denomination).toList();

    final drawn = <ChipColumn>[];
    var left = total;
    for (var i = 0; i < columnsUsed; i++) {
      final n = left > perColumn ? perColumn : left;
      left -= n;
      // Biggest denomination on the left; past the breakdown's variety, reuse
      // the smallest chip it found.
      final d = i < denoms.length ? denoms[i] : denoms.last;
      drawn.add(ChipColumn(denomination: d, count: n));
      if (left <= 0) break;
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
    required this.highlight,
  });

  final double width;
  final double height;
  final Color body;
  final Color edge;
  final bool highlight;

  @override
  Widget build(BuildContext context) => Container(
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
      borderRadius: BorderRadius.circular(height / 2 + 0.6),
      border: Border.all(color: edge.withValues(alpha: 0.9), width: 0.3),
    ),
  );
}
