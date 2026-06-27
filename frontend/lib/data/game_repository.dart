import 'package:flutter/foundation.dart';

import '../engine/actions.dart';
import '../history/hand_history.dart';
import 'table_snapshot.dart';

/// The boundary between the UI and "where the game lives".
///
/// Today the only implementation is [LocalGameRepository], which runs the whole
/// game on-device. When the Ktor backend comes online, a `RemoteGameRepository`
/// will implement this same interface by talking to the server over WebSockets
/// — and the UI won't need to change. That's the entire point of this seam.
abstract class GameRepository extends ChangeNotifier {
  /// The current immutable view of the table.
  TableSnapshot get snapshot;

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
}
