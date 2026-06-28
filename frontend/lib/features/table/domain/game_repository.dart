import 'package:monte/core/domain/ai/bot_spec.dart';
import 'package:monte/core/domain/ai/personality.dart';
import 'package:monte/core/domain/engine/actions.dart';
import 'package:monte/core/domain/hand_history.dart';
import 'package:monte/features/table/domain/table_snapshot.dart';

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

  /// Starts a brand-new game where each bot seat is given the behavior model
  /// (brain + style) at the matching index in [bots] (seat order, excluding the
  /// human). Seats past the end fall back to the table's defaults.
  Future<void> newGameWithBots(List<BotSpec> bots);

  /// Deals the next hand at the existing table.
  Future<void> startNextHand();

  /// Whether the dealer button currently rotates each hand.
  bool get buttonRotates;

  /// Sets whether the dealer button rotates (normal) or stays pinned to one
  /// seat. Used by evaluation to isolate positional effects.
  void setButtonRotation(bool rotate);

  /// Submits the local human's action for the current hand.
  Future<void> submitAction(GameAction action);

  /// Plays [hands] hands to completion as fast as possible (no animation),
  /// recording each into [history]. Intended for all-bots evaluation runs.
  Future<void> simulate(int hands);

  /// Refills a busted seat's stack to the starting amount, keeping the same
  /// player. Used to rebuy between hands.
  void reloadPlayer(String id);

  /// Replaces a busted bot seat with a fresh opponent of the given
  /// [archetype], full bankroll and a new name.
  void replacePlayer(String id, PersonalityArchetype archetype);

  /// Clears the recorded hand history.
  void clearHistory();

  /// Releases resources (closes the snapshot stream).
  void dispose();
}
