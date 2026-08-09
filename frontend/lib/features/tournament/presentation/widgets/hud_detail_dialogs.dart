import 'package:flutter/material.dart';
import 'package:monte/core/util/format.dart';
import 'package:monte/features/tournament/domain/tournament_snapshot.dart';
import 'package:monte/features/tournament/domain/tournament_structure.dart';
import 'package:monte/features/tournament/presentation/widgets/detail_dialog.dart';
import 'package:monte/features/tournament/presentation/widgets/standings_panel.dart';

/// The popups behind each tappable stat in the [TournamentHud]. Each is a
/// read-only projection of [TournamentSnapshot] — no state, no callbacks.

/// The full blind ladder, with the active level highlighted.
class BlindStructureDialog extends StatelessWidget {
  const BlindStructureDialog({super.key, required this.tour});
  final TournamentSnapshot tour;

  @override
  Widget build(BuildContext context) => DetailDialog(
    title: 'Blind structure',
    body: SizedBox(
      width: 320,
      height: 360,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              'Smallest chip in play: ${formatChips(tour.smallestChip)}',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: tour.schedule.length,
              itemBuilder: (context, i) {
                final l = tour.schedule[i];
                final active = i == tour.levelIndex;
                final ante = l.ante > 0 ? '  + ${l.ante} ante' : '';
                return Container(
                  color: active ? Colors.amber.withValues(alpha: 0.22) : null,
                  child: ListTile(
                    dense: true,
                    leading: Text(
                      'L${l.level}',
                      style: TextStyle(
                        fontWeight: active
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                    title: Text('${l.smallBlind} / ${l.bigBlind}$ante'),
                    trailing: active
                        ? Text(
                            tour.clockMode == LevelClockMode.hands
                                ? 'hand ${tour.handsThisLevel + 1}/${tour.handsPerLevel}'
                                : 'now',
                            style: const TextStyle(color: Colors.amber),
                          )
                        : null,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    ),
  );
}

/// Field size, tables remaining, and distance to the money.
class FieldDialog extends StatelessWidget {
  const FieldDialog({super.key, required this.tour});
  final TournamentSnapshot tour;

  @override
  Widget build(BuildContext context) => DetailDialog(
    title: 'Field',
    body: DetailRows([
      ('Players left', '${tour.playersLeft} of ${tour.entrants}'),
      ('Busted', '${tour.entrants - tour.playersLeft}'),
      ('Tables', '${tour.tableCount}'),
      ('Places paid', '${tour.paidPlaces}'),
      (
        'To the money',
        tour.inMoney ? 'in the money' : '${tour.playersToTheMoney} to bust',
      ),
    ]),
  );
}

/// Average stack, your stack, and how the two compare.
class StacksDialog extends StatelessWidget {
  const StacksDialog({super.key, required this.tour});
  final TournamentSnapshot tour;

  @override
  Widget build(BuildContext context) => DetailDialog(
    title: 'Stacks',
    body: DetailRows([
      (
        'Average stack',
        '${tour.averageStack}  (${tour.averageStackBb.toStringAsFixed(1)} BB)',
      ),
      (
        'Your stack',
        '${tour.yourChips}  (${tour.yourStackBb.toStringAsFixed(1)} BB)',
      ),
      ('vs average', '${tour.yourStackVsAveragePercent}%'),
      ('Total chips', '${tour.totalChips}'),
      ('Starting stack', '${tour.startingStack}'),
    ]),
  );
}

/// Your chips, place, and what busting right now would pay — over the full
/// live standings.
class YourStandingDialog extends StatelessWidget {
  const YourStandingDialog({
    super.key,
    required this.tour,
    required this.standings,
  });
  final TournamentSnapshot tour;
  final List<StandingRow> standings;

  @override
  Widget build(BuildContext context) => DetailDialog(
    title: 'Your standing',
    body: SizedBox(
      width: 320,
      height: 420,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DetailRows([
            (
              'Chips',
              '${tour.yourChips}  (${tour.yourStackBb.toStringAsFixed(1)} BB)',
            ),
            ('Place', '${ordinal(tour.yourPlace)} of ${tour.entrants}'),
            (
              'If you bust now',
              tour.nextPayoutAmount > 0
                  ? '${ordinal(tour.nextPayoutPlace)} — \$${tour.nextPayoutAmount}'
                  : '${ordinal(tour.nextPayoutPlace)} — no cash (bubble)',
            ),
          ]),
          const Divider(),
          Expanded(child: StandingsList(rows: standings)),
        ],
      ),
    ),
  );
}

/// The prize pool and the full payout ladder.
class PayoutsDialog extends StatelessWidget {
  const PayoutsDialog({super.key, required this.tour});
  final TournamentSnapshot tour;

  @override
  Widget build(BuildContext context) => DetailDialog(
    title: 'Payouts',
    body: SizedBox(
      width: 300,
      height: 420,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DetailRows([
            ('Prize pool', '\$${tour.prizePool}'),
            ('Buy-in', '\$${tour.buyIn} x ${tour.entrants}'),
            ('Places paid', '${tour.paidPlaces}'),
          ]),
          const Divider(),
          Expanded(
            child: ListView.builder(
              itemExtent: 32,
              itemCount: tour.payouts.length,
              itemBuilder: (context, i) {
                final active = i + 1 == tour.nextPayoutPlace;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        ordinal(i + 1),
                        style: TextStyle(
                          fontWeight: active
                              ? FontWeight.bold
                              : FontWeight.normal,
                          color: active ? Colors.amber : null,
                        ),
                      ),
                      Text('\$${tour.payouts[i]}'),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    ),
  );
}
