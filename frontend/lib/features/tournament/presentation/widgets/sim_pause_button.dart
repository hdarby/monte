import 'dart:async';

import 'package:flutter/material.dart';
import 'package:monte/features/tournament/domain/tournament_snapshot.dart';
import 'package:monte/features/tournament/domain/tournament_structure.dart';

/// The level clock, standalone — always visible next to [SimPauseButton]
/// rather than buried in the scrollable HUD row alongside six other stats,
/// which was too easy to miss entirely. Highlights red under a minute left.
///
/// Ticks down every second on its own, rather than only redrawing whenever a
/// new [TournamentSnapshot] happens to arrive (every few seconds at best,
/// only on hand/level events) — a clock that jumps in multi-second steps
/// doesn't read as a countdown. [tour.clockElapsed] is a snapshot of real
/// elapsed time as of whenever it was published; between publishes, this
/// widget extrapolates forward from its own arrival time.
class LevelClockBadge extends StatefulWidget {
  const LevelClockBadge({super.key, required this.tour});
  final TournamentSnapshot tour;

  @override
  State<LevelClockBadge> createState() => _LevelClockBadgeState();
}

class _LevelClockBadgeState extends State<LevelClockBadge> {
  Timer? _ticker;
  DateTime _receivedAt = DateTime.now();

  @override
  void initState() {
    super.initState();
    _startTicker();
  }

  @override
  void didUpdateWidget(covariant LevelClockBadge old) {
    super.didUpdateWidget(old);
    // A new snapshot arrived — its clockElapsed is only accurate as of right
    // now, so restart extrapolating from this moment.
    _receivedAt = DateTime.now();
  }

  void _startTicker() {
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {}); // just redraws with the extrapolated time
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tour = widget.tour;
    final asOfPublish = tour.timeRemainingInLevel;
    final liveRemaining = asOfPublish == null
        ? null
        : asOfPublish - DateTime.now().difference(_receivedAt);
    final remaining = liveRemaining == null
        ? null
        : (liveRemaining.isNegative ? Duration.zero : liveRemaining);
    final lowTime = remaining != null && remaining.inSeconds < 60;
    final text = tour.clockMode == LevelClockMode.hands
        ? 'hand ${tour.handsThisLevel + 1}/${tour.handsPerLevel}'
        : remaining != null
            ? '${remaining.inMinutes.toString().padLeft(2, '0')}:'
                '${(remaining.inSeconds % 60).toString().padLeft(2, '0')}'
            : 'L${tour.level}';

    return Material(
      color: lowTime
          ? Colors.red.shade900.withValues(alpha: 0.75)
          : Colors.black.withValues(alpha: 0.7),
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Text(
          text,
          style: TextStyle(
            color: lowTime ? Colors.red.shade100 : Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w700,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ),
    );
  }
}

/// A small, always-visible pause/resume control for background table
/// simulation. Deliberately static — no "table N of M" text, spinner, or
/// progress bar: the player already knows other tables are simming between
/// their hands, and a constantly appearing/disappearing/updating banner was
/// distracting rather than informative.
class SimPauseButton extends StatelessWidget {
  const SimPauseButton({
    super.key,
    required this.onPauseToggle,
    this.isPaused = false,
  });

  final VoidCallback onPauseToggle;
  final bool isPaused;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.black.withValues(alpha: 0.7),
    borderRadius: BorderRadius.circular(20),
    child: InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onPauseToggle,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isPaused ? Icons.play_arrow : Icons.pause,
              size: 16,
              color: isPaused ? Colors.green.shade300 : Colors.orange.shade300,
            ),
            const SizedBox(width: 6),
            Text(
              isPaused ? 'Resume' : 'Pause',
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
          ],
        ),
      ),
    ),
  );
}
