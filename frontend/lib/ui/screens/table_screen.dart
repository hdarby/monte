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
  });

  final TableSnapshot snapshot;
  final GameRepository repository;

  @override
  Widget build(BuildContext context) {
    if (snapshot.seats.isEmpty) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final opponents = snapshot.seats.where((s) => !s.isHuman).toList();
    final human = snapshot.seats.firstWhere((s) => s.isHuman);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _header(),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: _table(opponents, human)),
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
            const Text(
              'Texas Hold\'em',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black26,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text('Client-only mode',
                  style: TextStyle(fontSize: 12, color: Colors.white60)),
            ),
          ],
        ),
      );

  Widget _table(List<SeatView> opponents, SeatView human) {
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
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final s in opponents)
                Flexible(child: PlayerSeat(seat: s, compact: true)),
            ],
          ),
          Expanded(child: Center(child: CommunityBoard(snapshot: snapshot))),
          PlayerSeat(seat: human),
        ],
      ),
    );
  }
}

class _LogPanel extends StatelessWidget {
  const _LogPanel({required this.log});

  final List<String> log;

  @override
  Widget build(BuildContext context) {
    final recent = log.length > 14 ? log.sublist(log.length - 14) : log;
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
