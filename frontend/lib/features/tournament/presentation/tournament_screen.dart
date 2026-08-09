import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:monte/core/domain/ai/player_profile.dart';
import 'package:monte/core/presentation/money_format.dart';
import 'package:monte/features/table/presentation/table_screen.dart';
import 'package:monte/features/tournament/domain/tournament_structure.dart';
import 'package:monte/features/tournament/presentation/tournament_view_model.dart';
import 'package:monte/features/tournament/presentation/widgets/color_up_dialog.dart';
import 'package:monte/features/tournament/presentation/widgets/recap_dialog.dart';
import 'package:monte/features/tournament/presentation/widgets/results_overlay.dart';
import 'package:monte/features/tournament/presentation/widgets/sim_progress_bar.dart';
import 'package:monte/features/tournament/presentation/widgets/standings_panel.dart';
import 'package:monte/features/tournament/presentation/widgets/tournament_hud.dart';

/// The interactive tournament: the human plays their table live (via the reused
/// [TableScreen]) with a tournament HUD overlaid; other tables simulate between
/// hands.
///
/// This is a pure View — all state and the controller lifecycle live in
/// [TournamentViewModel]. Its only jobs are laying out the overlays and turning
/// one-shot events (color-up, level recap) into dialogs.
class TournamentScreen extends ConsumerStatefulWidget {
  const TournamentScreen({
    super.key,
    required this.structure,
    required this.field,
    required this.buyIn,
    required this.tableSize,
    required this.humanName,
  });

  final TournamentStructure structure;

  /// The bot field (one profile per non-human seat), each playing its own
  /// personality. The human takes the remaining seat.
  final List<PlayerProfile> field;
  final int buyIn;
  final int tableSize;
  final String humanName;

  @override
  ConsumerState<TournamentScreen> createState() => _TournamentScreenState();
}

class _TournamentScreenState extends ConsumerState<TournamentScreen> {
  /// Scoped to this screen: created once, torn down (with the underlying
  /// controller) when the screen is disposed.
  late final _vm = tournamentViewModelProvider(
    TournamentArgs(
      structure: widget.structure,
      field: widget.field,
      buyIn: widget.buyIn,
      tableSize: widget.tableSize,
      humanName: widget.humanName,
    ),
  );

  /// Guards against re-showing a dialog for an event we've already announced —
  /// the snapshot stream rebuilds on every tick, but each event fires once.
  Object? _lastColorUp;
  Object? _lastRecap;

  void _announce(TournamentUiState state) {
    final colorUp = state.tour?.colorUp;
    if (colorUp != null && !identical(colorUp, _lastColorUp)) {
      _lastColorUp = colorUp;
      showDialog<void>(
        context: context,
        builder: (_) => ColorUpDialog(colorUp: colorUp),
      );
    }
    final recap = state.tour?.recap;
    if (recap != null && !identical(recap, _lastRecap)) {
      _lastRecap = recap;
      showDialog<void>(
        context: context,
        builder: (_) => RecapDialog(recap: recap),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(_vm, (_, next) => _announce(next));

    final state = ref.watch(_vm);
    final table = state.table;
    final tour = state.tour;
    if (table == null || tour == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final controller = ref.read(_vm.notifier);

    // Tournament stacks are chips; the seat's BB readout needs the *current
    // level's* big blind, not the cash-settings default.
    return MoneyScope(
      format: MoneyFormat(showBigBlinds: false, bigBlind: tour.bigBlind),
      child: Stack(
        children: [
          TableScreen(
            snapshot: table,
            isAllBots: false,
            humanName: widget.humanName,
            // The human's current table size drives the felt layout.
            playerCount: table.seats.length,
            sidePanel: StandingsPanel(rows: controller.standings()),
            readForSeat: controller.readForSeat,
            onAction: controller.submitLiveAction,
            // Hands auto-advance in a tournament, and the table's own chrome is
            // replaced by the tournament HUD.
            onNewGame: _noop,
            onNextHand: _noop,
            onOpenSettings: _noop,
            onOpenAnalytics: _noop,
            onOpenHistory: _noop,
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: TournamentHud(
                tour: tour,
                standings: controller.standings,
                humanName: widget.humanName,
              ),
            ),
          ),
          if (state.sim != null && !tour.finished)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: SafeArea(child: SimProgressBar(sim: state.sim!)),
            ),
          if (tour.finished) ResultsOverlay(tour: tour),
        ],
      ),
    );
  }

  static void _noop() {}
}
