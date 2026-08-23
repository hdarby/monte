import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:monte/core/di/game_providers.dart';
import 'package:monte/core/domain/ai/player_profile.dart';
import 'package:monte/core/domain/ai/player_read.dart';
import 'package:monte/core/domain/engine/actions.dart';
import 'package:monte/features/table/domain/table_snapshot.dart';
import 'package:monte/features/tournament/data/tournament_controller.dart';
import 'package:monte/features/tournament/domain/tournament_snapshot.dart';
import 'package:monte/features/tournament/domain/tournament_structure.dart';
import 'package:monte/features/eval_history/presentation/eval_history_provider.dart';

/// The immutable state a tournament view renders: the human's live table, the
/// tournament-wide snapshot, and background-simulation progress (null when no
/// sim is running).
class TournamentUiState {
  const TournamentUiState({this.table, this.tour, this.sim});

  final TableSnapshot? table;
  final TournamentSnapshot? tour;
  final SimProgress? sim;

  /// True once both streams have produced a value and the table can be drawn.
  bool get isReady => table != null && tour != null;

  TournamentUiState copyWith({
    TableSnapshot? table,
    TournamentSnapshot? tour,
    SimProgress? sim,
    bool clearSim = false,
  }) => TournamentUiState(
    table: table ?? this.table,
    tour: tour ?? this.tour,
    sim: clearSim ? null : (sim ?? this.sim),
  );
}

/// The configuration that defines one tournament run.
class TournamentArgs {
  const TournamentArgs({
    required this.structure,
    required this.field,
    required this.buyIn,
    required this.tableSize,
    required this.humanName,
  });

  final TournamentStructure structure;

  /// One profile per non-human seat. The human takes the remaining seat.
  final List<PlayerProfile> field;
  final int buyIn;
  final int tableSize;
  final String humanName;

  /// Entrants including the human.
  int get entrants => field.length + 1;

  /// Seat names, human first — the order [TournamentController] expects.
  List<String> get names => [humanName, ...field.map((p) => p.name)];
}

/// Owns the [TournamentController] lifecycle and projects its three streams into
/// a single immutable [TournamentUiState].
///
/// This is the seam that keeps the View out of the data layer: widgets never
/// touch the controller directly, they watch this. Swapping the local controller
/// for a remote/WebSocket one is a change here and nowhere else.
class TournamentViewModel extends Notifier<TournamentUiState> {
  TournamentViewModel(this.args, {this.createController});

  final TournamentArgs args;

  /// Injection seam for tests: supply a fake or seeded controller instead of
  /// the live one.
  final TournamentController Function()? createController;

  late final TournamentController _controller;

  /// The live controller, for the few things the View genuinely needs it for —
  /// capturing a save is a snapshot of the whole tournament, not a projection.
  TournamentController get controller => _controller;
  final List<StreamSubscription<void>> _subs = [];

  @override
  TournamentUiState build() {
    _controller = createController?.call() ?? _defaultController();

    _subs.addAll([
      _controller.tableStream.listen((s) => state = state.copyWith(table: s)),
      _controller.tournamentStream.listen(
        (s) => state = state.copyWith(tour: s),
      ),
      _controller.simProgressStream.listen(
        (s) => state = s.isRunning
            ? state.copyWith(sim: s)
            : state.copyWith(clearSim: true),
      ),
    ]);

    ref.onDispose(() {
      for (final sub in _subs) {
        sub.cancel();
      }
      _controller.dispose();
    });

    _controller.startLive();
    return const TournamentUiState();
  }

  TournamentController _defaultController() => TournamentController.create(
    structure: args.structure,
    entrants: args.entrants,
    buyIn: args.buyIn,
    tableSize: args.tableSize,
    seed: DateTime.now().millisecondsSinceEpoch % 1000000,
    humanSeat: true,
    names: args.names,
    botProfiles: args.field,
    statsService: ref.read(opponentStatsServiceProvider),
    // Tournament hands are the ones the player actually cares about, so they
    // are the ones a post-session review needs; until this was wired they were
    // the only hands that produced no record at all.
    onEvalHandRecorded: ref.read(evalHistoryStoreProvider).record,
    resultStore: ref.read(tournamentResultStoreProvider),
  );

  /// The full live standings, built on demand — the field can be thousands of
  /// players, so this is only materialised when something actually shows it.
  List<StandingRow> standings() => _controller.standings();

  /// The two-way read on a seat for the table HUD, or null when untracked.
  SeatRead? readForSeat(String seatId) => _controller.readForSeat(seatId);

  /// Submits the human's action for the hand in progress.
  Future<void> submitLiveAction(GameAction action) =>
      _controller.submitLiveAction(action);
}

/// Builds a provider scoped to a single tournament run. The screen creates one
/// in `initState` and holds it for its lifetime, so the controller is torn down
/// with the screen.
NotifierProvider<TournamentViewModel, TournamentUiState> tournamentViewModelProvider(
  TournamentArgs args, {
  TournamentController Function()? createController,
}) => NotifierProvider<TournamentViewModel, TournamentUiState>(
  () => TournamentViewModel(args, createController: createController),
  isAutoDispose: true,
);
