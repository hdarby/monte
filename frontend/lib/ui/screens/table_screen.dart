import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../data/game_repository.dart';
import '../../data/table_snapshot.dart';
import '../../theme/app_theme.dart';
import '../widgets/action_bar.dart';
import '../widgets/community_board.dart';
import '../widgets/player_seat.dart';

/// The main game screen: felt table, seats, board, event log and controls.
class TableScreen extends StatelessWidget {
  const TableScreen({
    super.key,
    required this.snapshot,
    required this.repository,
    required this.playerCount,
    required this.onOpenSettings,
    required this.onOpenAnalytics,
  });

  final TableSnapshot snapshot;
  final GameRepository repository;
  final int playerCount;
  final VoidCallback onOpenSettings;
  final VoidCallback onOpenAnalytics;

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
                  Expanded(child: _felt(snapshot.seats)),
                  _LogPanel(log: snapshot.log),
                ],
              ),
            ),
            ActionBar(snapshot: snapshot, repository: repository),
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
            const Text("Texas Hold'em",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black26,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                  repository.isAllBots
                      ? '$playerCount bots · evaluation'
                      : '$playerCount players · client-only',
                  style: const TextStyle(fontSize: 12, color: Colors.white60)),
            ),
            const SizedBox(width: 8),
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

  /// The felt with the community board centred and seats arranged around an
  /// ellipse — the human at the bottom, opponents filling the rest of the ring.
  Widget _felt(List<SeatView> seats) {
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
          BoxShadow(color: Colors.black54, blurRadius: 24, offset: Offset(0, 8)),
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
                child: PlayerSeat(seat: seats[i], compact: !seats[i].isHuman),
              ),
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
}

class _LogPanel extends StatelessWidget {
  const _LogPanel({required this.log});

  final List<String> log;

  @override
  Widget build(BuildContext context) {
    final recent = log.length > 16 ? log.sublist(log.length - 16) : log;
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
          const Text('HAND LOG',
              style: TextStyle(
                  color: Colors.white54,
                  fontSize: 12,
                  letterSpacing: 2,
                  fontWeight: FontWeight.bold)),
          const Divider(color: Colors.white12),
          Expanded(
            child: ListView(
              children: [
                for (final line in recent)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Text(line,
                        style: const TextStyle(
                            fontSize: 13, color: Colors.white70)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
