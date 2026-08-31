import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:monte/core/domain/ai/player_profile.dart';
import 'package:monte/core/presentation/money_format.dart';
import 'package:monte/features/table/presentation/table_screen.dart';
import 'package:monte/features/tournament/domain/tournament_structure.dart';
import 'package:monte/features/tournament/presentation/tournament_view_model.dart';
import 'package:monte/features/tournament/presentation/widgets/color_up_dialog.dart';
import 'package:monte/features/tournament/presentation/widgets/recap_dialog.dart';
import 'package:monte/features/tournament/presentation/widgets/results_overlay.dart';
import 'package:monte/features/tournament/presentation/widgets/sim_pause_button.dart';
import 'package:monte/core/di/game_providers.dart';
import 'package:monte/features/tournament/data/tournament_controller.dart';
import 'package:monte/features/tournament/domain/tournament_save.dart';
import 'package:monte/features/tournament/presentation/widgets/saved_tournaments_dialog.dart';
import 'package:monte/features/tournament/presentation/widgets/standings_panel.dart';
import 'package:monte/features/tournament/presentation/widgets/tournament_hud.dart';
import 'package:monte/features/eval_history/domain/eval_hand.dart';
import 'package:monte/features/eval_history/domain/session_markdown.dart';
import 'package:monte/features/eval_history/domain/session_report.dart';
import 'package:monte/features/tournament/domain/tournament_result.dart';
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
        // Page two: the career, across every event ever finished — including
        // the stretches played out headless after the human busted.
        final career = CareerRow.from(
            await ref.read(tournamentResultStoreProvider).loadAll());
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
      final String title;
      final String? detail;
      if (!brk.broke) {
        title = brk.arrivals.length == 1
            ? '${brk.arrivals.first} has joined your table.'
            : '${brk.arrivals.length} players have joined your table.';
        detail = brk.arrivals.length == 1 ? null : brk.arrivals.join(', ');
      } else {
        title = 'Your table has broken. '
            '${you == null ? '' : 'You move to table ${you.toTable}, '
                'seat ${you.toSeat + 1}.'}';
        detail = others.isEmpty
            ? null
            : others.take(9).map((m) => '${m.name} → T${m.toTable}').join('   ')
                + (others.length > 9 ? '   +${others.length - 9} more' : '');
      }
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(
          duration: const Duration(seconds: 6),
          content: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              if (detail != null)
                Text(detail, style: const TextStyle(fontSize: 11)),
            ],
          ),
        ));
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
            isFinalTable: tour.atFinalTable,
            // Tournament tables use a fixed 9-seat layout so consolidation doesn't
            // redraw. Empty seats appear as players are eliminated.
            playerCount: 9,
            sidePanel: StandingsPanel(
              rows: state.standings,
              total: tour.entrants,
            ),
            readForSeat: controller.readForSeat,
            onAction: controller.submitLiveAction,
            // Hands auto-advance in a tournament, and the table's own chrome is
            // replaced by the tournament HUD.
            onNewGame: _noop,
            onNextHand: _noop,
            onOpenSettings: _noop,
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
          // Final table framing — the thing everybody played for, marked in gold.
          // Dollar signs were another option and read as a slot machine;
          // the tournament is tense, not tacky.
          if (tour.atFinalTable)
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: const Color(0xCCFFC107),
                      width: 3,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFFFC107).withValues(alpha: 0.22),
                        blurRadius: 40,
                        spreadRadius: -8,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          if (tour.atFinalTable)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: IgnorePointer(
                child: SafeArea(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: (tour.atFinalTable
                                  ? const Color(0xFFFFC107)
                                  : const Color(0xFFFF8A50))
                              .withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 4),
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
          if (!tour.finished)
            Positioned(
              right: 12,
              bottom: 12,
              child: SafeArea(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    LevelClockBadge(tour: tour),
                    const SizedBox(width: 8),
                    SimPauseButton(
                      isPaused: state.simPaused,
                      onPauseToggle: controller.toggleSimulationPause,
                    ),
                  ],
                ),
              ),
            ),
          if (tour.finished)
            ResultsOverlay(tour: tour, onBackToLobby: _reviewThenLeave),
          // A fresh tournament (never shown for a restored save — the field
          // has already been dealt in for however many levels) waits here
          // until the player confirms they're ready. The first hand is
          // already dealt underneath and awaiting the human's action same as
          // any other hand; this just keeps it out of view until dismissed.
          if (widget.restore == null && !_started)
            Positioned.fill(
              child: _ShuffleUpBanner(onOk: () => setState(() => _started = true)),
            ),
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

/// A full-screen scrim shown once at the start of a fresh tournament, over
/// an already-dealt-and-waiting first hand, until the player taps through.
/// The banner zooms in with an elastic overshoot, reveals letter by letter,
/// and cycles color continuously while it's on screen.
class _ShuffleUpBanner extends StatefulWidget {
  const _ShuffleUpBanner({required this.onOk});
  final VoidCallback onOk;

  @override
  State<_ShuffleUpBanner> createState() => _ShuffleUpBannerState();
}

class _ShuffleUpBannerState extends State<_ShuffleUpBanner>
    with TickerProviderStateMixin {
  static const _text = 'Shuffle Up and Deal!';

  // One-shot: drives the zoom-in pop and the letter-by-letter reveal.
  late final AnimationController _entrance = AnimationController(
    duration: const Duration(milliseconds: 1400),
    vsync: this,
  )..forward();

  // Repeats for as long as the banner is on screen: continuous color cycling.
  late final AnimationController _colorCycle = AnimationController(
    duration: const Duration(seconds: 3),
    vsync: this,
  )..repeat();

  late final Animation<double> _zoom = CurvedAnimation(
    parent: _entrance,
    curve: const Interval(0.0, 0.55, curve: Curves.elasticOut),
  );

  @override
  void dispose() {
    _entrance.dispose();
    _colorCycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.black.withValues(alpha: 0.88),
    child: Center(
      child: AnimatedBuilder(
        animation: _zoom,
        builder: (context, child) =>
            Transform.scale(scale: 0.4 + 0.6 * _zoom.value, child: child),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedBuilder(
              animation: Listenable.merge([_entrance, _colorCycle]),
              builder: (context, _) => Wrap(
                alignment: WrapAlignment.center,
                children: [
                  for (var i = 0; i < _text.length; i++) _letter(i),
                ],
              ),
            ),
            const SizedBox(height: 28),
            FilledButton(
              onPressed: widget.onOk,
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 24, vertical: 4),
                child: Text('OK'),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  /// One character of the banner: revealed (fade + slight rise) on its own
  /// slice of [_entrance]'s timeline, staggered across all the letters, and
  /// colored from a continuously-rotating hue (offset per letter so the
  /// cycling reads as a wave across the text, not one flat flashing color).
  Widget _letter(int i) {
    final n = _text.length;
    final start = 0.15 + 0.75 * (i / n);
    final end = (start + 0.25).clamp(0.0, 1.0);
    final reveal =
        Interval(start, end, curve: Curves.easeOut).transform(_entrance.value);
    final hue = (_colorCycle.value * 360 + i * 14) % 360;
    final color = HSVColor.fromAHSV(1.0, hue, 0.55, 1.0).toColor();
    final ch = _text[i];
    return Opacity(
      opacity: reveal,
      child: Transform.translate(
        offset: Offset(0, (1 - reveal) * 10),
        child: Text(
          ch == ' ' ? ' ' : ch,
          style: TextStyle(
            color: color,
            fontSize: 28,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}
