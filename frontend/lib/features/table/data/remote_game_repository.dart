import 'package:poker_client/core/domain/engine/actions.dart';
import 'package:poker_client/core/domain/hand_history.dart';
import 'package:poker_client/features/table/domain/game_repository.dart';
import 'package:poker_client/features/table/domain/table_snapshot.dart';

/// PLACEHOLDER for the future client/server mode.
///
/// When the Ktor backend is ready, implement this against its WebSocket
/// protocol (see `backend/` — `/ws/game`): connect, send the local player's
/// [GameAction]s as `ClientMessage`s, and rebuild [TableSnapshot] from the
/// server's `ServerMessage` table-state broadcasts. Because it satisfies the
/// same [GameRepository] interface as [LocalGameRepository], swapping it in is
/// a one-line change in `main.dart` — no UI changes required.
class RemoteGameRepository extends GameRepository {
  RemoteGameRepository({required this.serverUrl});

  /// e.g. `ws://localhost:8080/ws/game`.
  final String serverUrl;

  @override
  TableSnapshot get snapshot => TableSnapshot.empty;

  @override
  Stream<TableSnapshot> watch() => const Stream.empty();

  @override
  bool get isAllBots => false;

  @override
  List<HandHistory> get history => const [];

  @override
  void clearHistory() {}

  @override
  Future<void> newGame() => throw UnimplementedError(
        'RemoteGameRepository is a stub for the upcoming Ktor backend.',
      );

  @override
  Future<void> startNextHand() => throw UnimplementedError();

  @override
  Future<void> submitAction(GameAction action) => throw UnimplementedError();

  @override
  Future<void> simulate(int hands) => throw UnimplementedError();

  @override
  void dispose() {}
}
