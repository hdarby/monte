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
import 'package:monte/core/di/game_providers.dart';
import 'package:monte/features/tournament/data/tournament_controller.dart';
import 'package:monte/features/tournament/domain/tournament_save.dart';
import 'package:monte/features/tournament/presentation/widgets/saved_tournaments_dialog.dart';
import 'package:monte/features/tournament/presentation/widgets/standings_panel.dart';
import 'package:monte/features/tournament/presentation/widgets/tournament_hud.dart';
import 'package:monte/features/eval_history/domain/eval_hand.dart';
import 'package:monte/features/eval_history/domain/session_markdown.dart';
import 'package:monte/features/eval_history/domain/session_report.dart';
import 'package:monte/features/eval_history/presentation/eval_history_provider.dart';
import 'package:monte/features/eval_history/presentation/session_review_screen.dart';

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
    this.restore,
  });

  final TournamentStructure structure;

  /// The bot field (one profile per non-human seat), each playing its own
  /// personality. The human takes the remaining seat.
  final List<PlayerProfile> field;
  final int buyIn;
  final int tableSize;
  final String humanName;

  /// When set, the tournament resumes from this save instead of starting fresh.
  final TournamentSave? restore;

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
    createController: widget.restore == null
        ? null
        : () => TournamentController.restore(
              widget.restore!,
              statsService: ref.read(opponentStatsServiceProvider),
              onEvalHandRecorded: ref.read(evalHistoryStoreProvider).record,
            ),
  );

  /// Saves the tournament as it stands, prompting for a name.
  Future<void> _save() async {
    final controller = ref.read(_vm.notifier).controller;
    final name = await promptForSaveName(
      context,
      initial: '${widget.structure.name} · level '
          '${controller.state.levelIndex + 1}',
    );
    if (name == null || name.isEmpty || !mounted) return;
    final save = controller.saveAs(name);
    await ref.read(tournamentSaveStoreProvider).save(save);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Saved "\${save.name}"')),
    );
  }

  /// Opens the browser, and replaces this screen with the chosen tournament.
  Future<void> _openSaves() async {
    final chosen = await SavedTournamentsDialog.show(
      context,
      ref.read(tournamentSaveStoreProvider),
    );
    if (chosen == null || !mounted) return;
    final structure = chosen.structure;
    if (structure == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('That save uses an unknown blind structure '
              '("${chosen.structureName}") and cannot be loaded.'),
        ),
      );
      return;
    }
    // Replace rather than stack: the controller owns timers and streams, and
    // two live tournaments running behind one another is not a state worth
    // supporting.
    await Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => TournamentScreen(
          structure: structure,
          field: const [],
          buyIn: chosen.buyIn,
          tableSize: chosen.tableSize,
          humanName: chosen.humanName,
          restore: chosen,
        ),
      ),
    );
  }

  /// Guards against re-showing a dialog for an event we've already announced —
  /// the snapshot stream rebuilds on every tick, but each event fires once.
  Object? _lastColorUp;
  Object? _lastRecap;
  Object? _lastTableBreak;

  /// Shows the session review, then returns to the lobby.
  ///
  /// On the way out rather than on demand: the moment a tournament ends is the
  /// only one where the player is certain to look, and a review nobody opens is
  /// a review that does not exist.
  Future<void> _reviewThenLeave() async {
    final nav = Navigator.of(context);
    try {
      final hands = await ref.read(evalHistoryStoreProvider).loadAll();
      // The sitting that just finished: the newest session id in the store.
      final latest = hands
          .where((h) => h.sessionId != null)
          .fold<EvalHand?>(
              null,
              (best, h) => best == null ||
                      (h.timestampMs ?? 0) > (best.timestampMs ?? 0)
                  ? h
                  : best);
      final mine =
          hands.where((h) => h.sessionId == latest?.sessionId).toList();
      final seat = mine
          .expand((h) => h.players)
          .where((p) => p.modelId == 'human')
          .firstOrNull
          ?.id;
      if (mine.isNotEmpty && seat != null) {
        final report = SessionReport.of(mine, seat);
        final worst = [
          for (final h in mine)
            for (final d in h.decisions)
              if (d.playerId == seat) (d, h)
        ]..sort((a, b) => b.$1.evLost.compareTo(a.$1.evLost));
        final md = SessionMarkdown.of(report, worst: worst.take(5).toList());
        if (mounted) {
          await nav.push(MaterialPageRoute<void>(
            builder: (_) => SessionReviewScreen(markdown: md),
          ));
        }
      }
    } catch (_) {
      // A review must never trap the player in a finished tournament.
    }
    nav.pop();
  }

  void _announce(TournamentUiState state) {
    final colorUp = state.tour?.colorUp;
    if (colorUp != null && !identical(colorUp, _lastColorUp)) {
      _lastColorUp = colorUp;
      showDialog<void>(
        context: context,
        builder: (_) => ColorUpDialog(colorUp: colorUp),
      );
    }
    // A break is a banner rather than a dialog: it is orienting information, not
    // something to stop the game and read. A dialog every time the field
    // consolidates would be intolerable in a large event.
    final brk = state.tour?.tableBreak;
    if (brk != null && !identical(brk, _lastTableBreak)) {
      _lastTableBreak = brk;
      final you = brk.moves.where((m) => m.isHuman).firstOrNull;
      final others = brk.moves.where((m) => !m.isHuman).toList();
      final where = you != null
          ? 'You move to table ${you.toTable}, seat ${you.toSeat + 1}.'
          : '${brk.moves.length} players reseated.';
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(
          duration: const Duration(seconds: 6),
          content: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Table ${brk.tableNumber} has broken. $where',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              if (others.isNotEmpty)
                Text(
                  others
                      .take(9)
                      .map((m) => '${m.name} → T${m.toTable}')
                      .join('   ') +
                      (others.length > 9 ? '   +${others.length - 9} more' : ''),
                  style: const TextStyle(fontSize: 11),
                ),
            ],
          ),
        ));
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
          // Save / load, top-right, clear of the HUD.
          Positioned(
            top: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.only(right: 8, top: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _chromeButton(
                      icon: Icons.save_outlined,
                      tooltip: 'Save this tournament',
                      onPressed: tour.finished ? null : _save,
                    ),
                    const SizedBox(width: 4),
                    _chromeButton(
                      icon: Icons.folder_open_outlined,
                      tooltip: 'Saved tournaments',
                      onPressed: _openSaves,
                    ),
                  ],
                ),
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
          if (tour.finished)
            ResultsOverlay(tour: tour, onBackToLobby: _reviewThenLeave),
        ],
      ),
    );
  }

  static void _noop() {}

  /// A small, unobtrusive round button for the tournament's own chrome.
  Widget _chromeButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback? onPressed,
  }) =>
      Tooltip(
        message: tooltip,
        child: Material(
          color: Colors.black54,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onPressed,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Icon(
                icon,
                size: 18,
                color: onPressed == null ? Colors.white24 : Colors.white70,
              ),
            ),
          ),
        ),
      );
}
