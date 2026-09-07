import 'package:flutter/material.dart';
import 'package:monte/core/theme/app_theme.dart';
import 'package:monte/core/util/format.dart';
import 'package:monte/features/tournament/domain/tournament_snapshot.dart';

/// The end-of-tournament results, shown over the table when it finishes: where
/// the human landed, and the full list of players who cashed.
class ResultsOverlay extends StatelessWidget {
  const ResultsOverlay({super.key, required this.tour, this.onBackToLobby});
  final TournamentSnapshot tour;

  /// Runs instead of popping, so the screen can show the session review on the
  /// way out. Falls back to a plain pop when absent.
  final VoidCallback? onBackToLobby;

  @override
  Widget build(BuildContext context) {
    final results = tour.finalResults ?? const <FinishRow>[];
    final you = results.where((r) => r.isHuman).toList();
    final paid = results.where((r) => r.prize > 0).toList();
    final top3 = paid.where((r) => r.place <= 3).toList();
    final rest = paid.where((r) => r.place > 3).toList();

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
                  if (top3.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    _Podium(top3: top3),
                  ],
                  const SizedBox(height: 12),
                  Flexible(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 300),
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemExtent: 44,
                        itemCount: rest.length,
                        itemBuilder: (context, i) {
                          final r = rest[i];
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
                    onPressed:
                        onBackToLobby ?? () => Navigator.of(context).pop(),
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

/// The top 3 finishers as a podium: 1st centered and tallest, 2nd and 3rd
/// flanking it — each place's ordinal lettering in its medal color (gold /
/// silver / bronze), sized down the ranking, larger than any other finisher's
/// text on the screen.
class _Podium extends StatelessWidget {
  const _Podium({required this.top3});

  /// Up to 3 rows, in finishing order (1st first) — a small field may only
  /// have 1 or 2 paid places.
  final List<FinishRow> top3;

  static const _medalColors = {
    1: AppTheme.gold,
    2: Color(0xFFC8CCD1),
    3: Color(0xFFCD7F32),
  };
  static const _blockHeights = {1: 92.0, 2: 68.0, 3: 52.0};
  static const _ordinalFontSizes = {1: 32.0, 2: 24.0, 3: 20.0};

  @override
  Widget build(BuildContext context) {
    final byPlace = {for (final r in top3) r.place: r};
    // Classic podium arrangement — 2nd, 1st, 3rd left to right — skipping any
    // place a small field didn't pay.
    final order = [2, 1, 3].where(byPlace.containsKey).toList();

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (final place in order)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: _PodiumColumn(
                row: byPlace[place]!,
                color: _medalColors[place]!,
                blockHeight: _blockHeights[place]!,
                ordinalFontSize: _ordinalFontSizes[place]!,
              ),
            ),
          ),
      ],
    );
  }
}

class _PodiumColumn extends StatelessWidget {
  const _PodiumColumn({
    required this.row,
    required this.color,
    required this.blockHeight,
    required this.ordinalFontSize,
  });

  final FinishRow row;
  final Color color;
  final double blockHeight;
  final double ordinalFontSize;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          displayName(row.name, isHuman: row.isHuman, suffix: ' (you)'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: row.isHuman ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          '\$${row.prize}',
          style: const TextStyle(color: Colors.white70, fontSize: 11),
        ),
        const SizedBox(height: 6),
        Container(
          height: blockHeight,
          width: double.infinity,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.22),
            border: Border.all(color: color, width: 2),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
          ),
          child: Text(
            ordinal(row.place),
            style: TextStyle(
              color: color,
              fontSize: ordinalFontSize,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }
}
