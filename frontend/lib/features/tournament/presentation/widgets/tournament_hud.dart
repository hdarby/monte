import 'package:flutter/material.dart';
import 'package:monte/core/util/format.dart';
import 'package:monte/features/tournament/domain/tournament_snapshot.dart';
import 'package:monte/features/tournament/domain/tournament_structure.dart';
import 'package:monte/features/tournament/presentation/widgets/hud_detail_dialogs.dart';

/// A compact banner showing the tournament state. Every stat is tappable and
/// opens a popup with more detail (see `hud_detail_dialogs.dart`) — e.g. the
/// level chip shows the full blind ladder with the active level highlighted.
class TournamentHud extends StatelessWidget {
  const TournamentHud({
    super.key,
    required this.tour,
    required this.standings,
    required this.humanName,
  });

  final TournamentSnapshot tour;
  final String humanName;

  /// Builds the full live standings on demand — the field can be thousands of
  /// players, so the HUD only materialises them when a popup is opened.
  final List<StandingRow> Function() standings;

  @override
  Widget build(BuildContext context) {
    final clock = tour.clockMode == LevelClockMode.hands
        ? 'hand ${tour.handsThisLevel + 1}/${tour.handsPerLevel}'
        : 'L${tour.level}';
    final ante = tour.ante > 0 ? '+${tour.ante}' : '';
    // Before the money, "Nth = bubble" only restated the place already shown
    // beside it. What a player actually needs to know is how far off a cash is
    // and what it is worth, so name the last paid place and its prize.
    final minCash = tour.payouts.isEmpty ? 0 : tour.payouts.last;
    final nextPay = tour.nextPayoutAmount > 0
        ? '${ordinal(tour.nextPayoutPlace)} \$${tour.nextPayoutAmount}'
        : 'none until ${ordinal(tour.paidPlaces)} (\$$minCash)';

    return Material(
      color: Colors.black.withValues(alpha: 0.72),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: DefaultTextStyle(
          style: const TextStyle(color: Colors.white, fontSize: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _HudChip(
                label: 'L${tour.level}',
                value: '${tour.smallBlind}/${tour.bigBlind}$ante',
                detail: () => BlindStructureDialog(tour: tour),
              ),
              _HudChip(
                label: 'Left',
                value: '${tour.playersLeft}/${tour.entrants}',
                detail: () => FieldDialog(tour: tour),
              ),
              _HudChip(
                label: 'Avg',
                value: '${tour.averageStack}',
                detail: () => StacksDialog(tour: tour),
              ),
              _HudChip(
                label: humanName,
                value: '${tour.yourChips} · ${ordinal(tour.yourPlace)}'
                    '${tour.yourTable > 0 ? " · T${tour.yourTable}" : ""}',
                detail: () =>
                    YourStandingDialog(tour: tour, standings: standings()),
              ),
              _HudChip(
                label: 'Pool',
                value: '\$${tour.prizePool}',
                detail: () => PayoutsDialog(tour: tour),
              ),
              _HudChip(
                label: tour.inMoney ? 'ITM' : 'Next',
                value: nextPay,
                detail: () => PayoutsDialog(tour: tour),
              ),
              Text(clock, style: const TextStyle(color: Colors.white54)),
            ],
          ),
        ),
      ),
    );
  }
}

/// One tappable label/value stat in the HUD, opening [detail] when pressed.
class _HudChip extends StatelessWidget {
  const _HudChip({
    required this.label,
    required this.value,
    required this.detail,
  });

  final String label;
  final String value;
  final Widget Function() detail;

  @override
  Widget build(BuildContext context) => InkWell(
    borderRadius: BorderRadius.circular(6),
    onTap: () => showDialog<void>(context: context, builder: (_) => detail()),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(color: Colors.white54, fontSize: 10),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(width: 2),
              const Icon(Icons.info_outline, size: 10, color: Colors.white38),
            ],
          ),
        ],
      ),
    ),
  );
}
