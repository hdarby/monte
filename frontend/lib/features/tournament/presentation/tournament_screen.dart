import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:monte/core/domain/ai/player_profile.dart';
import 'package:monte/core/presentation/money_format.dart';
import 'package:monte/core/presentation/widgets/table_loading_view.dart';
import 'package:monte/core/theme/app_theme.dart';
import 'package:monte/features/table/presentation/table_screen.dart';
import 'package:monte/features/tournament/domain/tournament_structure.dart';
import 'package:monte/features/tournament/presentation/tournament_view_model.dart';
import 'package:monte/features/tournament/presentation/widgets/chrome_button.dart';
import 'package:monte/features/tournament/presentation/widgets/color_up_dialog.dart';
import 'package:monte/features/tournament/presentation/widgets/recap_dialog.dart';
import 'package:monte/features/tournament/presentation/widgets/resolving_field_banner.dart';
import 'package:monte/features/tournament/presentation/widgets/results_overlay.dart';
import 'package:monte/features/tournament/presentation/widgets/shuffle_up_banner.dart';
import 'package:monte/features/tournament/presentation/widgets/sim_pause_button.dart';
import 'package:monte/core/di/game_providers.dart';
import 'package:monte/features/tournament/data/tournament_controller.dart';
import 'package:monte/features/tournament/domain/tournament_save.dart';
import 'package:monte/features/tournament/presentation/widgets/saved_tournaments_dialog.dart';
import 'package:monte/features/tournament/presentation/widgets/previous_hand_dialog.dart';
import 'package:monte/features/tournament/presentation/widgets/standings_panel.dart';
import 'package:monte/features/tournament/presentation/widgets/tournament_hud.dart';
import 'package:monte/features/eval_history/domain/eval_hand.dart';
import 'package:monte/features/eval_history/domain/session_markdown.dart';
import 'package:monte/features/eval_history/domain/session_report.dart';
import 'package:monte/features/tournament/domain/tournament_result.dart';
import 'package:monte/features/eval_history/presentation/eval_history_provider.dart';
import 'package:monte/features/eval_history/presentation/session_review_screen.dart';

/// The player's choice from [_TournamentScreenState._confirmLeave]'s dialog.
enum _LeaveChoice { save, abandon }

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
  /// Whether the player has dismissed the "Shuffle Up and Deal!" banner
  /// shown at the start of a fresh tournament. Irrelevant (and never shown)
  /// for a restored save — see the banner's placement in [build].
  bool _started = false;

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
            resultStore: ref.read(tournamentResultStoreProvider),
            yieldToFrame: () => SchedulerBinding.instance.endOfFrame,
          ),
  );

  /// Saves the tournament as it stands, prompting for a name.
  Future<void> _save() async {
    final controller = ref.read(_vm.notifier).controller;
    final name = await promptForSaveName(
      context,
      initial:
          '${widget.structure.name} · level '
          '${controller.state.levelIndex + 1}',
    );
    if (name == null || name.isEmpty || !mounted) return;
    final save = controller.saveAs(name);
    await ref.read(tournamentSaveStoreProvider).save(save);
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Saved "\${save.name}"')));
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
          content: Text(
            'That save uses an unknown blind structure '
            '("${chosen.structureName}") and cannot be loaded.',
          ),
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

  /// Asks whether to save the in-progress tournament, abandon it, or stay —
  /// the only way out of a running tournament, since there's no other back
  /// navigation once it's started.
  Future<void> _confirmLeave() async {
    final nav = Navigator.of(context);
    final choice = await showDialog<_LeaveChoice>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Text('Leave this tournament?'),
        content: const Text(
          "Save your spot to resume later, or abandon it — abandoning stops "
          "the tournament now, and this event won't be recorded in your "
          'career results.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Stay'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, _LeaveChoice.abandon),
            child: const Text('Abandon'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.gold,
              foregroundColor: Colors.black,
            ),
            onPressed: () => Navigator.pop(ctx, _LeaveChoice.save),
            child: const Text('Save & Exit'),
          ),
        ],
      ),
    );
    if (choice == null || !mounted) return;
    if (choice == _LeaveChoice.save) {
      await _save();
      if (!mounted) return;
    }
    nav.pop();
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
            (best, h) =>
                best == null || (h.timestampMs ?? 0) > (best.timestampMs ?? 0)
                ? h
                : best,
          );
      final mine = hands
          .where((h) => h.sessionId == latest?.sessionId)
          .toList();
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
              if (d.playerId == seat) (d, h),
        ]..sort((a, b) => b.$1.evLost.compareTo(a.$1.evLost));
        // Page two: the career, across every event ever finished — including
        // the stretches played out headless after the human busted.
        final career = CareerRow.from(
          await ref.read(tournamentResultStoreProvider).loadAll(),
        );
        // This event's own finish — separate from the career aggregate above,
        // and previously shown nowhere but the results overlay the player
        // taps past to reach this screen.
        final tour = ref.read(_vm).tour;
        final you = tour?.finalResults?.where((f) => f.isHuman).firstOrNull;
        final md = SessionMarkdown.of(
          report,
          worst: worst.take(5).toList(),
          bands: SessionReport.byTableSize(mine, seat),
          career: career,
          place: you?.place,
          entrants: tour?.entrants,
        );
        if (mounted) {
          await nav.push(
            MaterialPageRoute<void>(
              builder: (_) => SessionReviewScreen(markdown: md),
            ),
          );
        }
      }
    } catch (_) {
      // A review must never trap the player in a finished tournament.
    }
    nav.pop();
  }

  void _announce(TournamentUiState state) {
    // Once the human is out, the field plays out headless (see
    // `_ResolvingFieldBanner`) — none of these mid-tournament interruptions
    // (color-ups, table breaks, level recaps) are yours to see anymore, and
    // popping a dialog on top of that banner for someone else's chip race
    // would just be confusing. The only thing left to show is the final
    // standings once it's done.
    if (state.tour?.resolvingRestOfField ?? false) return;
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
    //
    // Arrivals (someone else joining your table) no longer get a banner at
    // all — the arriving seat turns white for its first hand instead (see
    // `SeatView.isNewToTable`/`PlayerSeat`), which says the same thing without
    // interrupting play. Only your *own* table breaking (you move somewhere
    // else) is still worth a banner, since that's something you need to
    // orient to, not just notice.
    final brk = state.tour?.tableBreak;
    if (brk != null && !identical(brk, _lastTableBreak)) {
      _lastTableBreak = brk;
      if (brk.broke) {
        final you = brk.moves.where((m) => m.isHuman).firstOrNull;
        final others = brk.moves.where((m) => !m.isHuman).toList();
        final title =
            'Your table has broken. '
            '${you == null ? '' : 'You move to table ${you.toTable}, '
                      'seat ${you.toSeat + 1}.'}';
        final detail = others.isEmpty
            ? null
            : others
                      .take(9)
                      .map((m) => '${m.name} → T${m.toTable}')
                      .join('   ') +
                  (others.length > 9 ? '   +${others.length - 9} more' : '');
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(
            SnackBar(
              duration: const Duration(seconds: 6),
              content: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  if (detail != null)
                    Text(detail, style: const TextStyle(fontSize: 11)),
                ],
              ),
            ),
          );
      }
    }
    final recap = state.tour?.recap;
    if (recap != null && !identical(recap, _lastRecap)) {
      _lastRecap = recap;
      final controller = ref.read(_vm.notifier).controller;
      controller.pauseForRecap();
      showDialog<void>(
        context: context,
        builder: (_) => RecapDialog(recap: recap),
      ).then((_) => controller.resumeAfterRecap());
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(_vm, (_, next) => _announce(next));

    final state = ref.watch(_vm);
    final table = state.table;
    final tour = state.tour;
    if (table == null || tour == null) {
      return const TableLoadingView();
    }
    // The human is out and the rest of the field is being played out for
    // real (see `TournamentController._finishHeadless`) — no live table to
    // show, so a dedicated banner takes over instead of the generic loading
    // animation. `tour` keeps arriving fresh every round, so the remaining
    // count genuinely counts down rather than sitting on one stale number.
    if (tour.resolvingRestOfField) {
      return ResolvingFieldBanner(
        playersLeft: tour.playersLeft,
        topChipLeaders: tour.topChipLeaders,
      );
    }
    final controller = ref.read(_vm.notifier);

    // Tournament stacks are chips; the seat's BB readout needs the *current
    // level's* big blind, not the cash-settings default.
    return MoneyScope(
      format: MoneyFormat(showBigBlinds: false, bigBlind: tour.bigBlind),
      // A real Column, not an overlay: the top bar's height is whatever it
      // actually renders at, and the felt below gets the rest via Expanded.
      // The previous version anchored the top bar and the felt to the same
      // Stack (both `Positioned(top: 0, ...)`), guessing the bar's height to
      // avoid the felt drawing underneath it — a Positioned.fill(right:...)
      // on the final-table banner and a hand-tuned `top: 44` on the
      // clock/pause row were both fallout from that guess. Real layout means
      // there's no guess left to get wrong.
      child: Column(
        children: [
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Leave — the only way out of an in-progress tournament,
                  // since the cash table's own back arrow is hidden here
                  // (`showHeader: false`) and the HUD has none of its own.
                  if (!tour.finished)
                    ChromeButton(
                      icon: Icons.arrow_back,
                      tooltip: 'Leave tournament',
                      onPressed: _confirmLeave,
                    ),
                  Expanded(
                    child: TournamentHud(
                      tour: tour,
                      standings: controller.standings,
                      humanName: widget.humanName,
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ChromeButton(
                            icon: Icons.save_outlined,
                            tooltip: 'Save this tournament',
                            onPressed: tour.finished ? null : _save,
                          ),
                          const SizedBox(width: 4),
                          ChromeButton(
                            icon: Icons.folder_open_outlined,
                            tooltip: 'Saved tournaments',
                            onPressed: _openSaves,
                          ),
                        ],
                      ),
                      if (!tour.finished) ...[
                        const SizedBox(height: 4),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            LevelClockBadge(tour: tour, paused: state.simPaused),
                            const SizedBox(width: 8),
                            SimPauseButton(
                              isPaused: state.simPaused,
                              onPauseToggle: controller.toggleSimulationPause,
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: Stack(
              children: [
                TableScreen(
                  snapshot: table,
                  isAllBots: false,
                  humanName: widget.humanName,
                  // The nominated feature table gets the same treatment as
                  // the final table — it's the one with "the cameras on it".
                  isFinalTable: tour.atFinalTable || tour.atFeatureTable,
                  // Tournament tables use a fixed 9-seat layout so
                  // consolidation doesn't redraw. Empty seats appear as
                  // players are eliminated.
                  playerCount: 9,
                  sidePanel: StandingsPanel(
                    rows: state.standings,
                    total: tour.entrants,
                  ),
                  readForSeat: controller.readForSeat,
                  onAction: controller.submitLiveAction,
                  onShowPreviousHand: () =>
                      _showPreviousHand(context, controller.controller),
                  // Hands auto-advance in a tournament, and the table's own
                  // chrome is replaced by the tournament HUD above.
                  onNewGame: _noop,
                  onNextHand: _noop,
                  onOpenSettings: _noop,
                  onOpenHistory: _noop,
                  showHeader: false,
                ),
                // Final table and hand-for-hand are independent conditions
                // (hand-for-hand starts near the bubble, often across
                // several *still-separate* tables, well before the field
                // consolidates to one) — gating this whole badge on
                // `atFinalTable` alone made the "HAND FOR HAND" branch below
                // unreachable: it only ever ran once already inside
                // `if (tour.atFinalTable)`, at which point the ternary had
                // already committed to "FINAL TABLE" instead. That's why the
                // label disappeared exactly when it mattered most — nearing
                // the bubble, before the final table.
                if (tour.atFinalTable || tour.handForHand)
                  // Anchored near the top of the felt, not the bottom — the
                  // bottom edge is where the action bar's call/raise/fold
                  // buttons live. Excludes the standings panel's width on the
                  // right so it centers over the felt itself, not the whole
                  // row (panel + felt).
                  Positioned.fill(
                    right: StandingsPanel.width,
                    child: IgnorePointer(
                      child: Align(
                        alignment: const Alignment(0, -0.88),
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color:
                                  (tour.atFinalTable
                                          ? const Color(0xFFFFC107)
                                          : const Color(0xFFFF8A50))
                                      .withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 4,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    tour.atFinalTable
                                        ? Icons.emoji_events
                                        : Icons.timer_outlined,
                                    size: 15,
                                    color: tour.atFinalTable
                                        ? const Color(0xFFFFC107)
                                        : const Color(0xFFFF8A50),
                                  ),
                                  const SizedBox(width: 7),
                                  Text(
                                    tour.atFinalTable
                                        ? 'FINAL TABLE'
                                        : 'HAND FOR HAND — '
                                              '${tour.playersLeft - tour.paidPlaces} '
                                              'from the money',
                                    style: TextStyle(
                                      color: tour.atFinalTable
                                          ? const Color(0xFFFFC107)
                                          : const Color(0xFFFF8A50),
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 1.4,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                if (tour.finished)
                  ResultsOverlay(tour: tour, onBackToLobby: _reviewThenLeave),
                // A fresh tournament (never shown for a restored save — the
                // field has already been dealt in for however many levels)
                // waits here until the player confirms they're ready. The
                // first hand is already dealt underneath and awaiting the
                // human's action same as any other hand; this just keeps it
                // out of view until dismissed.
                if (widget.restore == null && !_started)
                  Positioned.fill(
                    child: ShuffleUpBanner(
                      onOk: () => setState(() => _started = true),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static void _noop() {}

  void _showPreviousHand(BuildContext context, TournamentController controller) {
    showDialog<void>(
      context: context,
      builder: (_) => PreviousHandDialog(
        hand: controller.lastHandReplay,
        bigBlind: controller.lastHandBigBlind,
        fallbackSummary: controller.lastHandFallbackSummary,
      ),
    );
  }

}
