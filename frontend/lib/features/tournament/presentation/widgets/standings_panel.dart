import 'package:flutter/material.dart';
import 'package:monte/core/presentation/widgets/adaptive_player_name.dart';
import 'package:monte/core/util/format.dart';
import 'package:monte/features/tournament/domain/tournament_snapshot.dart';

/// The tournament standings shown in place of the hand log: a boxed, titled
/// panel wrapping the scrollable list (auto-centered on the human).
class StandingsPanel extends StatelessWidget {
  const StandingsPanel({super.key, required this.rows, required this.total});
  final List<StandingRow> rows;

  /// The full field size — [rows] is only a window around the human, so this
  /// is passed separately rather than read off `rows.length`.
  final int total;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 260,
      margin: const EdgeInsets.only(right: 16, top: 16, bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0a0a0a),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white10, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'STANDINGS · $total',
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 11,
              letterSpacing: 1.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            height: 1,
            color: Colors.white10,
          ),
          const SizedBox(height: 12),
          // Only the main tournament-page panel gets the flip-clock cascade —
          // see StandingsList's `animated` doc.
          Expanded(child: StandingsList(rows: rows, animated: true)),
        ],
      ),
    );
  }
}

/// A lazy, scrollable standings list (handles thousands of entries) that opens
/// scrolled to center the human's row and follows them as their rank moves.
class StandingsList extends StatefulWidget {
  const StandingsList({super.key, required this.rows, this.animated = false});
  final List<StandingRow> rows;

  /// Whether rows flip like a mechanical clock display on every refresh.
  /// Defaults to **off** — a compact popup (e.g. `YourStandingDialog`) may
  /// not have enough width/height for the 3D perspective transform to render
  /// cleanly, which showed up as a real graphics glitch there. Only the main
  /// tournament-page side panel (`StandingsPanel`) opts in.
  final bool animated;

  @override
  State<StandingsList> createState() => _StandingsListState();
}

class _StandingsListState extends State<StandingsList> {
  // Must match _StandingsRow's actual rendered height exactly (card height +
  // bottom margin) — a mismatch here clips every row to less than its content,
  // which is what was cutting names/chips off mid-row.
  static const double _itemExtent = 28;
  late final ScrollController _controller;
  int _lastCenteredIndex = -1;

  @override
  void initState() {
    super.initState();
    _controller = ScrollController();
    WidgetsBinding.instance.addPostFrameCallback((_) => _centerOnYou());
  }

  @override
  void didUpdateWidget(covariant StandingsList old) {
    super.didUpdateWidget(old);
    // Re-center whenever the player's position in the standings changes (chips
    // shift, players bust), smoothly following them — but don't fight the user's
    // manual scrolling when their rank is unchanged.
    final i = widget.rows.indexWhere((r) => r.isHuman);
    if (i != _lastCenteredIndex) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _centerOnYou(animate: true),
      );
    }
  }

  void _centerOnYou({bool animate = false}) {
    if (!_controller.hasClients) return;
    final i = widget.rows.indexWhere((r) => r.isHuman);
    if (i < 0) return;
    _lastCenteredIndex = i;
    final pos = _controller.position;
    final target = (i * _itemExtent - (pos.viewportDimension - _itemExtent) / 2)
        .clamp(0.0, pos.maxScrollExtent);
    if (animate) {
      _controller.animateTo(
        target,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    } else {
      _controller.jumpTo(target);
    }
  }

  /// The absolute row index currently at (or just above) the top of the
  /// viewport — the cascade's reference point, so it always starts from the
  /// top of the *visible* area rather than from row 0 of the whole windowed
  /// list (which the player may be scrolled far past).
  int get _topVisibleIndex {
    if (!_controller.hasClients) return 0;
    return (_controller.position.pixels / _itemExtent)
        .floor()
        .clamp(0, widget.rows.isEmpty ? 0 : widget.rows.length - 1);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final topVisible = _topVisibleIndex;
    return ListView.builder(
      controller: _controller,
      itemExtent: _itemExtent,
      itemCount: widget.rows.length,
      itemBuilder: (context, i) {
        final r = widget.rows[i];
        // Keyed on name so a row keeps its own animation state as standings
        // reorder — otherwise the state at a given list index gets reused for
        // whichever player now occupies that slot.
        return _StandingsRow(
          key: ValueKey(r.name),
          row: r,
          animated: widget.animated,
          cascadeIndex: (i - topVisible).clamp(0, 1 << 30),
        );
      },
    );
  }
}

/// One standings line: place, name, and chips. When [animated] and this row's
/// own place/chips/busted status changes, the name flips like a mechanical
/// clock display — place and chips themselves never animate, only the name,
/// and only when *this* row actually moved. Busted players are greyed out
/// with strikethrough.
class _StandingsRow extends StatefulWidget {
  const _StandingsRow({
    super.key,
    required this.row,
    required this.animated,
    required this.cascadeIndex,
  });
  final StandingRow row;
  final bool animated;
  final int cascadeIndex;

  @override
  State<_StandingsRow> createState() => _StandingsRowState();
}

class _StandingsRowState extends State<_StandingsRow>
    with SingleTickerProviderStateMixin {
  static const _staggerPerRow = Duration(milliseconds: 45);
  static const _maxStagger = Duration(milliseconds: 1400);

  late AnimationController _controller;
  late Animation<double> _flipAnim;
  late String _prevKey;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1400),
      vsync: this,
    );
    _flipAnim = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
    _prevKey = _makeKey(widget.row);
  }

  // Place + chips, not just name: a row's own rank/stack changing is what
  // "this row actually moved" means. Keyed on the row's own values only — not
  // on a shared "something somewhere changed" generation counter, which used
  // to flip every visible row on every single hand (most of which don't
  // touch a given row at all) and read as constant, meaningless flicker.
  String _makeKey(StandingRow r) => '${r.place}-${r.chips}-${r.busted}';

  @override
  void didUpdateWidget(covariant _StandingsRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.animated) return;
    final newKey = _makeKey(widget.row);
    if (newKey != _prevKey) {
      _prevKey = newKey;
      // Rows that change in the same tick (common — a hand can move several
      // neighbours' ranks/stacks at once) still cascade together by visible
      // position, since each schedules its own delayed start this same frame.
      final delay = _staggerPerRow * widget.cascadeIndex;
      final capped = delay > _maxStagger ? _maxStagger : delay;
      Future<void>.delayed(capped, () {
        if (mounted) _controller.forward(from: 0);
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.row;
    final trailing = r.busted
        ? (r.prize > 0 ? 'out·\$${r.prize}' : 'out')
        : formatChips(r.chips);
    final isBusted = r.busted;
    final nameColor = isBusted
        ? Colors.grey
        : _colorForKind(r.isHuman ? StandingKind.human : r.kind, r.generated);
    final chipsColor =
        isBusted ? Colors.grey : Colors.white.withValues(alpha: 0.95);

    final nameText = AdaptivePlayerName(
      name: r.name,
      isHuman: r.isHuman,
      style: TextStyle(
        fontSize: 12,
        fontWeight: r.isHuman ? FontWeight.w800 : FontWeight.w600,
        color: nameColor,
        decoration: isBusted ? TextDecoration.lineThrough : null,
      ),
    );

    final nameSlot = widget.animated
        ? AnimatedBuilder(
            animation: _flipAnim,
            builder: (context, child) {
              // Flip-clock effect: rotate about the X axis (a horizontal
              // hinge, top edge tipping toward the viewer). Past the 90°
              // midpoint the face is seen from behind, so it must be
              // corrected with another X rotation (same axis as the outer
              // one) — correcting with Y instead mirrors left/right onto a
              // top/bottom rotation and renders upside-down.
              final angle = _flipAnim.value * 3.14159;
              final isPastMidpoint = angle > 1.5707963;
              return Transform(
                alignment: Alignment.center,
                transform: Matrix4.identity()
                  ..setEntry(3, 2, 0.0015)
                  ..rotateX(angle),
                child: isPastMidpoint
                    ? Transform(
                        alignment: Alignment.center,
                        transform: Matrix4.identity()..rotateX(3.14159),
                        child: child,
                      )
                    : child,
              );
            },
            child: nameText,
          )
        : nameText;

    return Container(
      height: 24,
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFF151515),
        borderRadius: BorderRadius.circular(3),
        border: Border.all(
          color: isBusted ? Colors.grey[700]! : Colors.white.withValues(alpha: 0.15),
          width: 0.5,
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            // Wide enough for a 5-digit place (large fields go into the
            // thousands) — the previous 22px clipped the last digit of
            // anything past 3 digits, e.g. "2930" rendering as "293".
            width: 34,
            child: Text(
              '${r.place}',
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.visible,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Colors.white54,
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: nameSlot,
            ),
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 78),
            child: Text(
              trailing,
              textAlign: TextAlign.right,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: chipsColor,
                fontFeatures: const [FontFeature.tabularFigures()],
                letterSpacing: -0.3,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Get the pro/rec color for a kind. Matches the table seat colors.
  ///
  /// [generated] players (anonymous auto-filled field, not an actual chosen
  /// personality) are dimmed relative to the ones the owner explicitly
  /// picked, so a big field's filler doesn't visually compete with them.
  static Color _colorForKind(StandingKind kind, bool generated) {
    const proColor = Color(0xFFEE6666); // warm red
    const recColor = Color(0xFF6699FF); // blue
    const humanColor = Color(0xFFFFC857); // amber/gold

    if (kind == StandingKind.human) return humanColor;
    final base = kind == StandingKind.amateur ? recColor : proColor;
    return generated ? base.withValues(alpha: 0.55) : base;
  }
}
