import 'package:flutter/material.dart';
import 'package:monte/core/theme/app_theme.dart';
import 'package:monte/core/util/format.dart';
import 'package:monte/features/tournament/domain/tournament_snapshot.dart';

/// Shown in place of the table while the rest of the field plays out headless
/// after the human busts (see `TournamentController._finishHeadless`).
/// Deliberately no spinner — [playersLeft] itself is the progress indicator,
/// counting down as real hands actually eliminate people, so a wheel that
/// spins without reference to that would be a worse signal, not a better one.
/// A slow, non-spinning pulse on the count is the only motion, so the screen
/// still reads as "working" between the (possibly seconds-apart) updates a
/// huge field's rounds arrive at.
class ResolvingFieldBanner extends StatefulWidget {
  const ResolvingFieldBanner({
    super.key,
    required this.playersLeft,
    required this.topChipLeaders,
  });

  final int playersLeft;
  final List<StandingRow> topChipLeaders;

  @override
  State<ResolvingFieldBanner> createState() => _ResolvingFieldBannerState();
}

class _ResolvingFieldBannerState extends State<ResolvingFieldBanner>
    with SingleTickerProviderStateMixin {
  late final _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surface,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Running out the event…',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 16),
            FadeTransition(
              opacity: _pulse.drive(Tween(begin: 0.55, end: 1.0)),
              child: Text(
                '${widget.playersLeft} players remain',
                style: const TextStyle(
                  color: AppTheme.gold,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              "You've busted — the rest of the field is being played out.",
              style: TextStyle(color: Colors.white54, fontSize: 13),
            ),
            if (widget.topChipLeaders.isNotEmpty) ...[
              const SizedBox(height: 28),
              _ChipLeaderboard(rows: widget.topChipLeaders),
            ],
          ],
        ),
      ),
    );
  }
}

/// The current top 10 by chip count, shown on [ResolvingFieldBanner] — the
/// human's own name never appears here (they're the reason this screen is up
/// at all), but it's still worth seeing who's actually left with the chips
/// while the rest of the field plays out.
class _ChipLeaderboard extends StatelessWidget {
  const _ChipLeaderboard({required this.rows});

  final List<StandingRow> rows;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 320,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.black26,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'CHIP LEADERS',
            style: TextStyle(
              color: Colors.white38,
              fontSize: 11,
              letterSpacing: 1.4,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 10),
          for (final r in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  SizedBox(
                    width: 22,
                    child: Text(
                      '${r.place}',
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      r.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                    ),
                  ),
                  Text(
                    formatChips(r.chips),
                    style: const TextStyle(
                      color: AppTheme.gold,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
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
