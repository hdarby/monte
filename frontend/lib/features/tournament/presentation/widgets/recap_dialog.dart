import 'package:flutter/material.dart';
import 'package:monte/core/util/format.dart';
import 'package:monte/features/tournament/domain/tournament_chronicle.dart';
import 'package:monte/features/tournament/presentation/widgets/feature_hand_view.dart';

/// The between-levels recap card: chip leaders, the level's biggest pot(s) with
/// what was shown down, notable players, and the human's own story. Every line
/// is generated from real results (see [TournamentChronicle]) — this widget only
/// lays out the prose the domain produced.
class RecapDialog extends StatelessWidget {
  const RecapDialog({super.key, required this.recap});
  final LevelRecap recap;

  @override
  Widget build(BuildContext context) {
    final gold = Theme.of(context).colorScheme.primary;
    return AlertDialog(
      title: Text('Level ${recap.levelJustFinished} in the books'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380, maxHeight: 460),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                recap.intro,
                style: const TextStyle(fontSize: 13, height: 1.3),
              ),
              Text(
                'avg stack ${formatChips(recap.averageStack)}',
                style: const TextStyle(color: Colors.white60, fontSize: 11),
              ),
              if (recap.bubbleLine != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    recap.bubbleLine!,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.3,
                      color: gold,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              if (recap.leaderFollowUp != null) ...[
                _RecapHeading('LAST LEVEL\'S LEADER', color: gold),
                _RecapLine(recap.leaderFollowUp!),
              ],
              if (recap.bountyLine != null) ...[
                _RecapHeading('BOUNTIES', color: gold),
                _RecapLine(recap.bountyLine!),
              ],
              if (recap.chipLeaders.isNotEmpty) ...[
                _RecapHeading('CHIP LEADERS', color: gold),
                for (var i = 0; i < recap.chipLeaders.length; i++)
                  _LeaderRow(
                    rank: i + 1,
                    leader: recap.chipLeaders[i],
                    bigBlind: recap.bigBlind,
                  ),
              ],
              if (recap.biggestPots.isNotEmpty) ...[
                _RecapHeading('BIGGEST POT', color: gold),
                for (final p in recap.biggestPots.take(2))
                  _RecapLine(p.describe(recap.bigBlind)),
              ],
              if (recap.featureHand != null) ...[
                _RecapHeading(
                  recap.featureTable == null
                      ? 'HAND OF THE LEVEL'
                      : recap.featureTable!.humanSeated
                          // Sitting at the feature table is the thing a player
                          // tells people about afterwards. Say so.
                          ? 'FEATURE TABLE — YOU ARE ON IT'
                          : 'HAND OF THE LEVEL — FEATURE TABLE',
                  color: gold,
                ),
                if (recap.featureTable != null)
                  _RecapLine(
                    'Table ${recap.featureTable!.number} · '
                    '${recap.featureTable!.names.join(', ')}'
                    '${recap.featureTable!.humanSeated ? ' — and you.' : ''}',
                  ),
                FeatureHandView(
                  hand: recap.featureHand!,
                  bigBlind: recap.bigBlind,
                ),
              ],
              if (recap.risers.isNotEmpty) ...[
                _RecapHeading('RUNNING DEEP', color: gold),
                for (final r in recap.risers) _RecapLine(r),
              ],
              if (recap.eliminations.isNotEmpty) ...[
                _RecapHeading('HIT THE RAIL', color: gold),
                for (final e in recap.eliminations) _RecapLine(e),
              ],
              if (recap.fallers.isNotEmpty) ...[
                _RecapHeading('IN TROUBLE', color: gold),
                for (final f in recap.fallers) _RecapLine(f),
              ],
              if (recap.notables.isNotEmpty) ...[
                _RecapHeading('STORYLINES', color: gold),
                for (final n in recap.notables) _RecapLine('• $n'),
              ],
              if (recap.yourStory != null) ...[
                _RecapHeading('YOUR LEVEL', color: gold),
                Text(
                  recap.yourStory!,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.3,
                    color: gold,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Back to the felt'),
        ),
      ],
    );
  }
}

/// A section heading in the recap ("CHIP LEADERS", "HIT THE RAIL", …).
class _RecapHeading extends StatelessWidget {
  const _RecapHeading(this.text, {required this.color});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 14, bottom: 4),
    child: Text(
      text,
      style: TextStyle(
        color: color,
        fontSize: 10,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.2,
      ),
    ),
  );
}

/// One line of recap prose.
class _RecapLine extends StatelessWidget {
  const _RecapLine(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Text(text, style: const TextStyle(fontSize: 13, height: 1.3)),
  );
}

/// One ranked chip-leader line, with the level's chip swing.
class _LeaderRow extends StatelessWidget {
  const _LeaderRow({
    required this.rank,
    required this.leader,
    required this.bigBlind,
  });

  final int rank;
  final ChipLeaderLine leader;
  final int bigBlind;

  @override
  Widget build(BuildContext context) {
    final l = leader;
    final delta = l.delta == 0
        ? ''
        : ' (${l.delta > 0 ? '+' : ''}${formatChips(l.delta)})';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        children: [
          SizedBox(
            width: 18,
            child: Text(
              '$rank',
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ),
          Expanded(
            child: Text(
              displayName(l.name, isHuman: l.isHuman),
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                fontWeight: l.isHuman ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
          Text(
            '${formatChipsWithBb(l.chips, bigBlind)}$delta',
            style: TextStyle(
              fontSize: 12,
              color: l.delta >= 0 ? Colors.greenAccent : Colors.redAccent,
            ),
          ),
        ],
      ),
    );
  }
}
