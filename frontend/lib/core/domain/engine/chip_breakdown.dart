import 'package:meta/meta.dart';

/// How many chips of one denomination a player is holding.
@immutable
class ChipColumn {
  const ChipColumn({required this.denomination, required this.count});

  final int denomination;
  final int count;

  int get value => denomination * count;
}

/// Breaks a chip count into the physical chips a dealer would actually have
/// pushed across the table.
///
/// Greedy from the largest denomination down, exactly as a real stack colours
/// up: a 60,000 stack at the WSOP is not sixty 1,000 chips, it is a few 25,000s,
/// some 5,000s and change.
///
/// Pure engine math with no Flutter — the visual side lives in
/// `core/presentation/widgets/chip_stack_view.dart`.
@immutable
class ChipBreakdown {
  const ChipBreakdown(this.columns);

  /// Decomposes [amount] using [denominations] (ascending), largest first.
  ///
  /// [minDenomination] drops chips smaller than the smallest one actually in
  /// play — a tournament at a 100/100 level has no 25 chips on the table, so a
  /// stack should never be drawn with them.
  ///
  /// [maxColumns] keeps the graphic readable by folding the smallest chips into
  /// the last column it kept: a player with eight denominations of change would
  /// otherwise render as an unreadable smear.
  factory ChipBreakdown.of(
    int amount, {
    required List<int> denominations,
    int minDenomination = 1,
    int maxColumns = 4,
  }) {
    if (amount <= 0 || denominations.isEmpty) {
      return const ChipBreakdown([]);
    }

    final usable =
        denominations.where((d) => d >= minDenomination && d > 0).toList()
          ..sort();
    if (usable.isEmpty) return const ChipBreakdown([]);

    // Largest first, greedily.
    var remaining = amount;
    final columns = <ChipColumn>[];
    for (final d in usable.reversed) {
      if (remaining < d) continue;
      final count = remaining ~/ d;
      remaining -= count * d;
      columns.add(ChipColumn(denomination: d, count: count));
      if (columns.length == maxColumns) break;
    }

    if (columns.isEmpty) {
      // Amount is smaller than the smallest chip in play: show a single chip so
      // a short stack never renders as nothing at all.
      return ChipBreakdown([
        ChipColumn(denomination: usable.first, count: 1),
      ]);
    }

    // Any unrepresented remainder is folded into the smallest kept column, so
    // the drawn stack always adds up to at least the real amount.
    if (remaining > 0) {
      final last = columns.removeLast();
      final extra = (remaining / last.denomination).ceil();
      columns.add(
        ChipColumn(
          denomination: last.denomination,
          count: last.count + extra,
        ),
      );
    }
    return ChipBreakdown(columns);
  }

  /// Denominations held, largest first.
  final List<ChipColumn> columns;

  bool get isEmpty => columns.isEmpty;

  /// Total chips (physical count, not value) — how tall the whole thing is.
  int get chipCount => columns.fold(0, (a, c) => a + c.count);

  /// Total value of the drawn chips. Always >= the amount asked for.
  int get value => columns.fold(0, (a, c) => a + c.value);
}
