import 'package:flutter/material.dart';
import 'package:monte/features/tournament/domain/tournament_snapshot.dart';

/// A slim bottom banner shown while the other tables simulate their hand, so the
/// wait reads as progress ("table N of M") rather than an opaque spinner.
class SimProgressBar extends StatelessWidget {
  const SimProgressBar({super.key, required this.sim});
  final SimProgress sim;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 10),
                Text(
                  'Simulating other tables — ${sim.done} of ${sim.total}',
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(value: sim.fraction, minHeight: 4),
            ),
          ],
        ),
      ),
    );
  }
}
