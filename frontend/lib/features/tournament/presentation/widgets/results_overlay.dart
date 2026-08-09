import 'package:flutter/material.dart';
import 'package:monte/core/util/format.dart';
import 'package:monte/features/tournament/domain/tournament_snapshot.dart';

/// The end-of-tournament results, shown over the table when it finishes: where
/// the human landed, and the full list of players who cashed.
class ResultsOverlay extends StatelessWidget {
  const ResultsOverlay({super.key, required this.tour});
  final TournamentSnapshot tour;

  @override
  Widget build(BuildContext context) {
    final results = tour.finalResults ?? const <FinishRow>[];
    final you = results.where((r) => r.isHuman).toList();
    final paid = results.where((r) => r.prize > 0).toList();

    return Container(
      color: Colors.black.withValues(alpha: 0.85),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Card(
            margin: const EdgeInsets.all(24),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Tournament complete',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  if (you.isNotEmpty)
                    Text(
                      'You finished ${ordinal(you.first.place)} of ${tour.entrants}'
                      '${you.first.prize > 0 ? ' for \$${you.first.prize}' : ''}.',
                      style: const TextStyle(color: Colors.amber),
                    ),
                  const SizedBox(height: 12),
                  Flexible(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 360),
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemExtent: 44,
                        itemCount: paid.length,
                        itemBuilder: (context, i) {
                          final r = paid[i];
                          return ListTile(
                            dense: true,
                            tileColor: r.isHuman
                                ? Colors.amber.withValues(alpha: 0.18)
                                : null,
                            leading: Text(ordinal(r.place)),
                            title: Text(
                              displayName(
                                r.name,
                                isHuman: r.isHuman,
                                suffix: '  (you)',
                              ),
                            ),
                            trailing: Text('\$${r.prize}'),
                          );
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Back to lobby'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
