import 'package:flutter_test/flutter_test.dart';
import 'package:monte/core/domain/ai/bot_spec.dart';
import 'package:monte/core/domain/ai/home_game_profiles.dart';
import 'package:monte/core/domain/ai/player_kind.dart';
import 'package:monte/core/domain/ai/player_profiles.dart';
import 'package:monte/features/table/data/local_game_repository.dart';

/// The pro/rec colour coding is only useful if the seat snapshot actually
/// carries the classification through from the configured personalities.
void main() {
  test('seats carry the pro/rec classification through to the snapshot', () async {
    final pro = builtInProfiles.first;
    final rec = homeGameProfiles.first;

    final repo = LocalGameRepository(
      config: TableConfig(
        playerCount: 3,
        botThinkTime: Duration.zero,
        seatBots: [
          BotSpec(profile: pro),
          BotSpec(profile: rec),
        ],
      ),
    );
    addTearDown(repo.dispose);
    await repo.newGame();

    final seats = repo.snapshot.seats;
    expect(seats, hasLength(3));

    final human = seats.firstWhere((s) => s.isHuman);
    expect(human.kind, PlayerKind.human);

    final proSeat = seats.firstWhere((s) => s.name == pro.name);
    expect(proSeat.kind, PlayerKind.pro);

    final recSeat = seats.firstWhere((s) => s.name == rec.name);
    expect(recSeat.kind, PlayerKind.amateur);
  });

  test('a bot with no personality is classified rather than left null', () async {
    final repo = LocalGameRepository(
      config: const TableConfig(playerCount: 2, botThinkTime: Duration.zero),
    );
    addTearDown(repo.dispose);
    await repo.newGame();

    for (final seat in repo.snapshot.seats) {
      expect(seat.kind, isNotNull, reason: '${seat.name} had no kind');
    }
    expect(
      repo.snapshot.seats.firstWhere((s) => !s.isHuman).kind,
      PlayerKind.pro,
    );
  });
}
