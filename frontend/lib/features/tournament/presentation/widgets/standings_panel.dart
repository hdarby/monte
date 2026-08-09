import 'package:flutter/material.dart';
import 'package:monte/core/presentation/player_kind_color.dart';
import 'package:monte/core/presentation/widgets/adaptive_player_name.dart';
import 'package:monte/core/util/format.dart';
import 'package:monte/features/tournament/domain/tournament_snapshot.dart';

/// The tournament standings shown in place of the hand log: a boxed, titled
/// panel wrapping the scrollable list (auto-centered on the human).
class StandingsPanel extends StatelessWidget {
  const StandingsPanel({super.key, required this.rows});
  final List<StandingRow> rows;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 240,
      margin: const EdgeInsets.only(right: 16, top: 16, bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black26,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'STANDINGS · ${rows.length}',
            style: const TextStyle(
              color: Colors.white54,
              fontSize: 12,
              letterSpacing: 2,
              fontWeight: FontWeight.bold,
            ),
          ),
          const Divider(color: Colors.white12),
          Expanded(child: StandingsList(rows: rows)),
        ],
      ),
    );
  }
}

/// A lazy, scrollable standings list (handles thousands of entries) that opens
/// scrolled to center the human's row and follows them as their rank moves.
class StandingsList extends StatefulWidget {
  const StandingsList({super.key, required this.rows});
  final List<StandingRow> rows;

  @override
  State<StandingsList> createState() => _StandingsListState();
}

class _StandingsListState extends State<StandingsList> {
  static const double _itemExtent = 24;
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

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      controller: _controller,
      itemExtent: _itemExtent,
      itemCount: widget.rows.length,
      itemBuilder: (context, i) => _StandingsRow(row: widget.rows[i]),
    );
  }
}

/// One standings line: place, adaptive name, and chips (or the payout once
/// busted). Busted players keep their brain tint and are marked by grey,
/// struck-through text rather than by losing their colour.
class _StandingsRow extends StatelessWidget {
  const _StandingsRow({required this.row});
  final StandingRow row;

  @override
  Widget build(BuildContext context) {
    final r = row;
    final trailing = r.busted
        ? (r.prize > 0 ? 'out·\$${r.prize}' : 'out')
        : formatChips(r.chips);
    final weight = r.isHuman ? FontWeight.bold : FontWeight.w400;
    final color = r.busted ? Colors.grey : Colors.white;

    return Container(
      color: _tint(r),
      padding: const EdgeInsets.symmetric(horizontal: 6),
      alignment: Alignment.centerLeft,
      child: Row(
        children: [
          SizedBox(
            width: 30,
            child: Text(
              '${r.place}',
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.visible,
              style: TextStyle(fontSize: 9, fontWeight: weight, color: color),
            ),
          ),
          Expanded(
            child: AdaptivePlayerName(
              name: r.name,
              isHuman: r.isHuman,
              style: TextStyle(
                fontSize: 11,
                fontWeight: weight,
                color: color,
                decoration: r.busted ? TextDecoration.lineThrough : null,
              ),
            ),
          ),
          const SizedBox(width: 4),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 84),
            child: Text(
              trailing,
              textAlign: TextAlign.right,
              overflow: TextOverflow.visible,
              maxLines: 1,
              softWrap: false,
              style: TextStyle(
                fontSize: 11,
                fontWeight: weight,
                color: color,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Subtle brain tint: blue behind recreational players, red behind pros,
  /// amber for the human (whose tint wins over the kind tint).
  ///
  /// Shares `PlayerKindColor` with the table seats, so the standings and the
  /// felt always agree on what a colour means.
  static Color? _tint(StandingRow r) =>
      (r.isHuman ? StandingKind.human : r.kind).tint(generated: r.generated);
}
