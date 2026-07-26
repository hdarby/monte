import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:monte/core/domain/engine/actions.dart';
import 'package:monte/core/presentation/money_format.dart';
import 'package:monte/core/theme/app_theme.dart';
import 'package:monte/features/table/domain/table_snapshot.dart';
import 'package:monte/features/table/presentation/widgets/action_bar.dart';
import 'package:monte/features/table/presentation/widgets/community_board.dart';
import 'package:monte/features/table/presentation/widgets/player_seat.dart';

/// The main game screen: felt table, seats, board, event log and controls.
///
/// A presentational View — it renders a [TableSnapshot] and reports intents via
/// callbacks. The [TableViewModel] supplies the snapshot and handles the
/// callbacks; this widget never touches a repository or provider.
class TableScreen extends StatelessWidget {
  const TableScreen({
    super.key,
    required this.snapshot,
    required this.isAllBots,
    required this.playerCount,
    required this.onAction,
    required this.onNewGame,
    required this.onNextHand,
    required this.onOpenSettings,
    required this.onOpenAnalytics,
    required this.onOpenHistory,
    this.showBehavior = false,
    this.autoDeal = false,
    this.onToggleAutoDeal,
    this.onCoach,
    this.onOpenTournament,
  });

  final TableSnapshot snapshot;
  final bool isAllBots;
  final int playerCount;

  /// Whether to show each bot's behavior model (brain + style) on its seat.
  final bool showBehavior;
  final ValueChanged<GameAction> onAction;
  final VoidCallback onNewGame;
  final VoidCallback onNextHand;
  final VoidCallback onOpenSettings;
  final VoidCallback onOpenAnalytics;
  final VoidCallback onOpenHistory;

  /// All-bots only: whether hands deal continuously until toggled off.
  final bool autoDeal;
  final ValueChanged<bool>? onToggleAutoDeal;

  /// Opens the in-hand coach for the human seat. Null hides the coach icon.
  final VoidCallback? onCoach;

  /// Opens the tournament lobby. Null hides the trophy button (e.g. when the
  /// table is itself inside a tournament).
  final VoidCallback? onOpenTournament;

  @override
  Widget build(BuildContext context) {
    if (snapshot.seats.isEmpty) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _header(),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: _felt(context, snapshot.seats)),
                  _LogPanel(log: snapshot.log),
                ],
              ),
            ),
            ActionBar(
              snapshot: snapshot,
              onAction: onAction,
              onNewGame: onNewGame,
              onNextHand: onNextHand,
            ),
          ],
        ),
      ),
    );
  }

  Widget _header() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
    color: AppTheme.surface,
    child: Row(
      children: [
        const Icon(Icons.style, color: AppTheme.gold),
        const SizedBox(width: 10),
        const Text(
          "Texas Hold'em",
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.black26,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            isAllBots
                ? '$playerCount bots · evaluation'
                : '$playerCount players · client-only',
            style: const TextStyle(fontSize: 12, color: Colors.white60),
          ),
        ),
        if (isAllBots && onToggleAutoDeal != null) ...[
          const SizedBox(width: 12),
          const Text(
            'Auto-deal',
            style: TextStyle(fontSize: 13, color: Colors.white70),
          ),
          Switch(
            value: autoDeal,
            activeThumbColor: AppTheme.gold,
            onChanged: onToggleAutoDeal,
          ),
        ],
        const SizedBox(width: 8),
        if (onOpenTournament != null)
          IconButton(
            tooltip: 'Play a tournament',
            icon: const Icon(Icons.emoji_events, color: Colors.white70),
            onPressed: onOpenTournament,
          ),
        IconButton(
          tooltip: 'Hand history',
          icon: const Icon(Icons.history, color: Colors.white70),
          onPressed: onOpenHistory,
        ),
        IconButton(
          tooltip: 'Analytics',
          icon: const Icon(Icons.bar_chart, color: Colors.white70),
          onPressed: onOpenAnalytics,
        ),
        IconButton(
          tooltip: 'Table settings',
          icon: const Icon(Icons.settings, color: Colors.white70),
          onPressed: onOpenSettings,
        ),
      ],
    ),
  );

  /// A prominent "who won" banner shown above the board once the hand is over,
  /// so the result reads at a glance without scanning seats or the log. Null
  /// mid-hand or when there are no recorded winners.
  Widget? _winnerBanner(BuildContext context) {
    if (!snapshot.isHandOver) return null;
    final winners = snapshot.seats.where((s) => s.wonAmount > 0).toList();
    if (winners.isEmpty) return null;
    final money = MoneyScope.of(context);
    final chop = winners.length > 1 || winners.first.wonIsChop;
    final String text;
    if (winners.length == 1) {
      final w = winners.first;
      text = '${w.name} ${chop ? 'chops' : 'wins'} ${money.format(w.wonAmount)}';
    } else {
      final parts =
          winners.map((w) => '${w.name} ${money.format(w.wonAmount)}').join('  ·  ');
      text = 'Chop — $parts';
    }
    return Align(
      alignment: const Alignment(0, -0.62),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
        decoration: BoxDecoration(
          color: AppTheme.gold,
          borderRadius: BorderRadius.circular(20),
          boxShadow: const [
            BoxShadow(color: Colors.black54, blurRadius: 12, offset: Offset(0, 4)),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.emoji_events, color: Colors.black, size: 18),
            const SizedBox(width: 8),
            Text(
              text,
              style: const TextStyle(
                color: Colors.black,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The felt with the community board centred and seats arranged around an
  /// ellipse — the human at the bottom, opponents filling the rest of the ring.
  Widget _felt(BuildContext context, List<SeatView> seats) {
    final winner = _winnerBanner(context);
    return Container(
      margin: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const RadialGradient(
          colors: [AppTheme.felt, AppTheme.feltDark],
          radius: 0.9,
        ),
        borderRadius: BorderRadius.circular(180),
        border: Border.all(color: AppTheme.feltEdge, width: 10),
        boxShadow: const [
          BoxShadow(
            color: Colors.black54,
            blurRadius: 24,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Stack(
          alignment: Alignment.center,
          children: [
            CommunityBoard(snapshot: snapshot),
            for (var i = 0; i < seats.length; i++)
              Align(
                alignment: _seatAlignment(i, seats.length),
                child: PlayerSeat(
                  seat: seats[i],
                  compact: !seats[i].isHuman,
                  buttonPlacement: _buttonPlacement(i, seats.length),
                  showBehavior: showBehavior,
                  onCoach: seats[i].isHuman ? onCoach : null,
                ),
              ),
            ?winner,
          ],
        ),
      ),
    );
  }

  /// Distributes seats evenly around an ellipse, seat 0 (the human) at the
  /// bottom centre and the rest going clockwise around the table.
  Alignment _seatAlignment(int index, int total) {
    final theta = math.pi / 2 + index * (2 * math.pi / total);
    return Alignment(0.95 * math.cos(theta), 0.96 * math.sin(theta));
  }

  /// Which edge of the button seat's box the dealer button hugs — always the
  /// one facing the centre of the table. Bottom-row seats get it above, top-row
  /// below, and side seats on their inner side, so it clearly fronts one player.
  ButtonPlacement _buttonPlacement(int index, int total) {
    final theta = math.pi / 2 + index * (2 * math.pi / total);
    final dx = math.cos(theta);
    final dy = math.sin(theta);
    if (dy.abs() >= dx.abs()) {
      return dy > 0 ? ButtonPlacement.above : ButtonPlacement.below;
    }
    return dx > 0 ? ButtonPlacement.left : ButtonPlacement.right;
  }
}

class _LogPanel extends StatefulWidget {
  const _LogPanel({required this.log});

  final List<String> log;

  @override
  State<_LogPanel> createState() => _LogPanelState();
}

class _LogPanelState extends State<_LogPanel> {
  final _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Show the whole log (no arbitrary cap that leaves the panel half-empty),
    // and after layout keep it pinned to the newest line at the bottom so the
    // box fills top-to-bottom with the latest action always in view.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_controller.hasClients) {
        _controller.jumpTo(_controller.position.maxScrollExtent);
      }
    });
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
          const Text(
            'HAND LOG',
            style: TextStyle(
              color: Colors.white54,
              fontSize: 12,
              letterSpacing: 2,
              fontWeight: FontWeight.bold,
            ),
          ),
          const Divider(color: Colors.white12),
          Expanded(
            child: ListView(
              controller: _controller,
              children: [
                for (final line in widget.log)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Text(
                      line,
                      style: const TextStyle(
                        fontSize: 13,
                        color: Colors.white70,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
