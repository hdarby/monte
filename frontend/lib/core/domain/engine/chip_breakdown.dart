import 'package:meta/meta.dart';

/// How many chips of one denomination a player is holding.
@immutable
class ChipColumn {
  const ChipColumn({required this.denomination, required this.count});

  final int denomination;
  final int count;

  int get value => denomination * count;
}

/// Breaks a chip count into the physical chips a player would actually be
/// sitting behind.
///
/// **Not minimal change.** Greedy from the top gives the fewest chips that make
/// the number — 60,000 becomes 2x25,000 and 2x5,000 — and no real stack looks
/// like that. Chips arrive from blinds, antes and dragged pots, not from a
/// cashier making change, so a stack is a *spread*: one or two of the biggest
/// denomination, a working pile of the next one down, and more of each as they
/// get smaller. The same 60,000 is really 1x25,000, 6x5,000, 4x1,000 and change.
///
/// That spread is the whole point of the graphic. Minimal change collapses most
/// stacks onto one or two colours, so every seat looks alike and the colours
/// carry no information.
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
  /// [maxColumns] caps how many denominations the spread runs to: a player with
  /// eight denominations of change renders as an unreadable smear, and the last
  /// denomination kept absorbs whatever is left over.
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

    // Largest first, but holding value back for the smaller chips rather than
    // taking every chip a denomination can cover.
    //
    // The biggest denomination keeps only about half, because that top chip is
    // the one a player has just been paid in and hasn't broken yet; below it
    // each denomination keeps most of what reaches it, which is what makes the
    // counts grow as the chips get smaller. The last column takes the rest, so
    // the spread always adds up exactly.
    var remaining = amount;
    final columns = <ChipColumn>[];
    final desc = usable.reversed.toList();
    for (var i = 0; i < desc.length; i++) {
      final d = desc[i];
      if (remaining < d) continue;
      // Last column when we've run out of room, or nothing smaller can be paid.
      final isLast = columns.length == maxColumns - 1 ||
          !desc.skip(i + 1).any((x) => x <= remaining - d);
      final keep = columns.isEmpty ? 0.5 : 0.9;
      final count =
          isLast ? remaining ~/ d : (remaining * keep ~/ d).clamp(1, remaining ~/ d);
      remaining -= count * d;
      columns.add(ChipColumn(denomination: d, count: count));
      if (isLast) break;
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
