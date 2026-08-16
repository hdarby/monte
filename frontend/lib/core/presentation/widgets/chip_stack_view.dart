import 'package:flutter/material.dart';

import 'package:monte/core/domain/engine/chip_breakdown.dart';
import 'package:monte/core/presentation/widgets/chip_legend.dart';

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
  // Solid black, deliberately: the 500,000 is also black, and leaving the 100
  // unspotted is what tells the cheapest chip on the table from the dearest.
  100: (body: Color(0xFF1A1A1A), spot: null), // black
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
class ChipStackView extends StatefulWidget {
  const ChipStackView({
    super.key,
    required this.amount,
    required this.denominations,
    this.minDenomination = 1,
    this.maxHeight = 34,
    this.chipWidth = 13,
    this.chipHeight = 3.2,
    this.maxColumns = defaultMaxColumns,
    this.showLegendOnHover = true,
  });

  /// The chip count to draw.
  final int amount;

  /// The denominations in play, ascending.
  final List<int> denominations;

  /// The smallest chip actually on the table at this level.
  final int minDenomination;

  /// Tallest the stack may be drawn.
  final double maxHeight;

  final double chipWidth;
  final double chipHeight;

  /// How many denominations the stack is spread across (see [ChipBreakdown]).
  final int maxColumns;

  /// Shared with [ChipLegend] so the legend's counts are the chips on screen.
  static const defaultMaxColumns = 4;

  /// Whether hovering the stack pops a legend of the chips in play.
  ///
  /// A tournament's denominations are its private language — a colour-up
  /// silently retires the small chips and brings in new ones, and nothing on the
  /// felt says which is which. The legend is how you learn that the orange ones
  /// are 5,000.
  final bool showLegendOnHover;

  @override
  State<ChipStackView> createState() => _ChipStackViewState();
}

class _ChipStackViewState extends State<ChipStackView> {
  final OverlayPortalController _legend = OverlayPortalController();

  @override
  Widget build(BuildContext context) {
    final amount = widget.amount;
    final denominations = widget.denominations;
    final minDenomination = widget.minDenomination;
    final maxHeight = widget.maxHeight;
    final chipWidth = widget.chipWidth;
    final chipHeight = widget.chipHeight;

    // Drawn exactly as broken down — the legend shows these same counts, and a
    // legend that disagrees with the picture beside it is worse than none.
    //
    // Height is therefore literal chip count, not a scale against the chip
    // leader. The scaled version made the two disagree by construction, and it
    // bought less than it looked: the size signal is really carried by *colour*,
    // since only a big stack has the top denominations in it at all. The exact
    // number stays on the seat regardless.
    final breakdown = ChipBreakdown.of(
      amount,
      denominations: denominations,
      minDenomination: minDenomination,
      maxColumns: widget.maxColumns,
    );
    if (breakdown.isEmpty) return SizedBox(height: maxHeight);

    // Tall columns are clipped to what the seat has room for rather than
    // spilling sideways, so a pile of small change can't crowd out the
    // denominations above it.
    final perColumn = (maxHeight / (chipHeight + 0.6)).floor().clamp(1, 40);
    final drawn = [
      for (final c in breakdown.columns)
        ChipColumn(
          denomination: c.denomination,
          count: c.count > perColumn ? perColumn : c.count,
        ),
    ];

    final stack = SizedBox(
      height: maxHeight,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final column in drawn)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 1),
              child: ChipColumnView(
                column: column,
                chipWidth: chipWidth,
                chipHeight: chipHeight,
              ),
            ),
        ],
      ),
    );

    if (!widget.showLegendOnHover) return stack;

    return MouseRegion(
      onEnter: (_) => _legend.show(),
      onExit: (_) => _legend.hide(),
      child: OverlayPortal(
        controller: _legend,
        // Centred on screen rather than anchored to the stack. A seat-anchored
        // popup runs off the edge for the seats around the rim of the felt —
        // which is most of them — and there is no good side to flip to when the
        // seat is in a corner. Non-interactive, so it can never swallow a click
        // meant for the felt underneath.
        overlayChildBuilder: (context) => Positioned.fill(
          child: IgnorePointer(
            child: Center(
              child: ChipLegend(
                denominations: denominations,
                minDenomination: minDenomination,
                amount: amount,
              ),
            ),
          ),
        ),
        child: stack,
      ),
    );
  }
}

/// One denomination's column of chips, seen edge-on.
///
/// Public so a test can find the columns and read what they represent. It used
/// to carry its own `Tooltip`, which tests scraped for the denomination — but a
/// per-column tooltip and the whole-stack legend both fire on the same hover,
/// so the tooltip went and the denomination is exposed directly instead.
class ChipColumnView extends StatelessWidget {
  const ChipColumnView({
    super.key,
    required this.column,
    required this.chipWidth,
    required this.chipHeight,
  });

  /// The denomination this column is made of.
  int get denomination => column.denomination;

  final ChipColumn column;
  final double chipWidth;
  final double chipHeight;

  @override
  Widget build(BuildContext context) {
    final colors = chipColorFor(column.denomination);

    return Column(
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
    );
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
