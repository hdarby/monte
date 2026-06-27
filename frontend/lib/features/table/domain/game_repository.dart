import 'package:poker_client/core/domain/engine/actions.dart';
import 'package:poker_client/core/domain/hand_history.dart';
import 'package:poker_client/features/table/domain/table_snapshot.dart';

/// The boundary between the app and "where the game lives".
///
/// Framework-free (plain Dart, no Flutter/Riverpod): exposes the current
/// [snapshot], a [watch] stream of snapshots, and command methods. Today the
/// only implementation is `LocalGameRepository` (on-device engine + bots); a
/// future `RemoteGameRepository` will satisfy the same contract by streaming
/// table state from the Ktor `/ws/game` socket — so the swap is a stream-source
/// change, not a UI change.
abstract class GameRepository {
  /// The latest table view.
  TableSnapshot get snapshot;

  /// Emits a new [TableSnapshot] whenever table state changes.
  Stream<TableSnapshot> watch();

  /// Whether this is an all-bots evaluation game (no human seat).
  bool get isAllBots;

  /// Recorded hand histories accumulated this session, oldest first.
  List<HandHistory> get history;

  /// Starts a brand-new game (fresh stacks), then deals the first hand.
  Future<void> newGame();

  /// Deals the next hand at the existing table.
  Future<void> startNextHand();

  /// Submits the local human's action for the current hand.
  Future<void> submitAction(GameAction action);

  /// Plays [hands] hands to completion as fast as possible (no animation),
  /// recording each into [history]. Intended for all-bots evaluation runs.
  Future<void> simulate(int hands);

  /// Clears the recorded hand history.
  void clearHistory();

  /// Releases resources (closes the snapshot stream).
  void dispose();
}
