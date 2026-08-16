import 'package:flutter/material.dart';

import 'package:monte/core/domain/engine/chip_breakdown.dart';
import 'package:monte/core/presentation/widgets/chip_stack_view.dart';
import 'package:monte/core/theme/app_theme.dart';
import 'package:monte/core/util/format.dart';

/// A single chip drawn **face-on**, for a legend entry.
///
/// The stack itself draws chips edge-on, which is how you read a stack across a
/// table but is close to useless for identifying one colour from another. Face-on
/// shows the body colour and the edge spots at once, which is what actually
/// distinguishes a 100 from a 500,000 — both are black, and only the spots tell
/// them apart.
class ChipSwatch extends StatelessWidget {
  const ChipSwatch({super.key, required this.denomination, this.size = 14});

  final int denomination;
  final double size;

  /// Edge spots, evenly spaced around the rim.
  static const _spots = 6;

  @override
  Widget build(BuildContext context) {
    final colors = chipColorFor(denomination);
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _ChipFacePainter(
          body: colors.body,
          edge: colors.edge,
          spot: colors.spot,
          spots: _spots,
        ),
      ),
    );
  }
}

class _ChipFacePainter extends CustomPainter {
  const _ChipFacePainter({
    required this.body,
    required this.edge,
    required this.spot,
    required this.spots,
  });

  final Color body;
  final Color edge;
  final Color? spot;
  final int spots;

  @override
  void paint(Canvas canvas, Size size) {
    final centre = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2;

    canvas.drawCircle(centre, r, Paint()..color = edge);
    canvas.drawCircle(centre, r * 0.88, Paint()..color = body);

    // Edge spots as arcs around the rim — the real identifying mark.
    final c = spot;
    if (c != null) {
      final paint = Paint()
        ..color = c
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.24;
      final rect = Rect.fromCircle(center: centre, radius: r * 0.82);
      const sweep = 0.42;
      for (var i = 0; i < spots; i++) {
        final start = (i * 2 * 3.14159265 / spots) - sweep / 2;
        canvas.drawArc(rect, start, sweep, false, paint);
      }
    }

    // A pale inner face, so the chip reads as a chip rather than a dot.
    canvas.drawCircle(
      centre,
      r * 0.52,
      Paint()..color = Color.lerp(body, Colors.white, 0.22)!,
    );
  }

  @override
  bool shouldRepaint(_ChipFacePainter old) =>
      old.body != body || old.edge != edge || old.spot != spot;
}

/// The chips in play and what each is worth, with the count this player holds.
///
/// Denominations are a tournament's private language: a level's colour-up
/// silently retires the small chips and introduces new ones, and nothing on the
/// felt says which is which. Reading a stack — yours or an opponent's — means
/// knowing that the orange ones are 5,000 and the beige ones are 250,000.
class ChipLegend extends StatelessWidget {
  const ChipLegend({
    super.key,
    required this.denominations,
    this.minDenomination = 1,
    this.amount,
    this.title,
  });

  /// Every denomination in play, ascending.
  final List<int> denominations;

  /// The smallest chip still on the table at this level; anything below it has
  /// been coloured up and is no longer in play.
  final int minDenomination;

  /// When given, the legend also shows how many of each chip this stack holds.
  final int? amount;

  final String? title;

  @override
  Widget build(BuildContext context) {
    final inPlay = [
      for (final d in denominations)
        if (d >= minDenomination) d,
    ]..sort((a, b) => b.compareTo(a)); // biggest first, like a real rack

    final held = <int, int>{};
    final total = amount;
    if (total != null && total > 0 && inPlay.isNotEmpty) {
      final breakdown = ChipBreakdown.of(
        total,
        denominations: denominations,
        minDenomination: minDenomination,
        maxColumns: inPlay.length,
      );
      for (final c in breakdown.columns) {
        held[c.denomination] = (held[c.denomination] ?? 0) + c.count;
      }
    }

    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xF01B1B1B),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white24),
          boxShadow: const [
            BoxShadow(color: Colors.black87, blurRadius: 14, offset: Offset(0, 5)),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title ?? 'Chips in play',
              style: TextStyle(
                color: AppTheme.gold.withValues(alpha: 0.85),
                fontSize: 9,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.0,
              ),
            ),
            const SizedBox(height: 5),
            for (final d in inPlay)
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ChipSwatch(denomination: d),
                    const SizedBox(width: 6),
                    Text(
                      formatChips(d),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (held.containsKey(d)) ...[
                      const SizedBox(width: 5),
                      Text(
                        '× ${held[d]}',
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
