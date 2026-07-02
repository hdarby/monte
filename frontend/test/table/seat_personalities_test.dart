import 'package:flutter_test/flutter_test.dart';
import 'package:monte/core/domain/ai/bot_spec.dart';
import 'package:monte/core/domain/ai/decider_factory.dart';
import 'package:monte/core/domain/ai/personality.dart';
import 'package:monte/core/domain/ai/player_profiles.dart';
import 'package:monte/features/table/data/local_game_repository.dart';
import 'package:monte/features/table/domain/table_snapshot.dart';

LocalGameRepository _repo({
  int playerCount = 4,
  List<BotSpec> seatBots = const [],
}) => LocalGameRepository(
  config: TableConfig(
    playerCount: playerCount,
    botType: BotType.personality,
    botThinkTime: Duration.zero,
    seatBots: seatBots,
  ),
);

List<SeatView> _bots(LocalGameRepository repo) =>
    repo.snapshot.seats.where((s) => !s.isHuman).toList();

void main() {
  group('per-seat bots', () {
    test('config seatBots seat the right number of bots', () async {
      final repo = _repo(
        playerCount: 4,
        seatBots: const [
          BotSpec(brain: BotType.personality, style: PersonalityArchetype.nit),
          BotSpec(brain: BotType.mcts, style: PersonalityArchetype.maniac),
          BotSpec(brain: BotType.heuristic),
        ],
      );
      addTearDown(repo.dispose);
      await repo.newGame();

      // 4 seats = 1 human + 3 bots, all dealt in.
      expect(_bots(repo).length, 3);
      expect(repo.snapshot.seats.where((s) => s.isHuman).length, 1);
    });

    test('each seat reports its behavior model label', () async {
      final repo = _repo(
        playerCount: 3,
        seatBots: const [
          BotSpec(brain: BotType.mcts, style: PersonalityArchetype.maniac),
          BotSpec(brain: BotType.heuristic),
        ],
      );
      addTearDown(repo.dispose);
      await repo.newGame();

      final bots = _bots(repo);
      expect(bots[0].behavior, 'Maniac · MCTS');
      expect(bots[1].behavior, 'Heuristic');
    });

    test('newGameWithBots deals a fresh lineup', () async {
      final repo = _repo(playerCount: 3);
      addTearDown(repo.dispose);
      await repo.newGame();
      expect(_bots(repo).length, 2);

      await repo.newGameWithBots(const [
        BotSpec(brain: BotType.mcts, style: PersonalityArchetype.maniac),
        BotSpec(brain: BotType.personality, style: PersonalityArchetype.station),
      ]);

      // Still a valid, dealt game with the same seat structure.
      expect(_bots(repo).length, 2);
      expect(_bots(repo)[0].behavior, 'Maniac · MCTS');
      expect(repo.snapshot.handInProgress || repo.snapshot.isHandOver, isTrue);
      expect(repo.snapshot.seats, isNotEmpty);
    });

    test('a shorter lineup than the bot count is accepted', () async {
      final repo = _repo(playerCount: 4);
      addTearDown(repo.dispose);

      // Only one spec for three bots — the rest fall back to the defaults.
      await repo.newGameWithBots(const [
        BotSpec(brain: BotType.personality, style: PersonalityArchetype.nit),
      ]);

      expect(_bots(repo).length, 3);
    });
  });

  group('seat names track the persona', () {
    test('a distinctive archetype names the seat after itself', () async {
      final repo = _repo(
        playerCount: 3,
        seatBots: const [
          BotSpec(brain: BotType.personality, style: PersonalityArchetype.nit),
          BotSpec(brain: BotType.mcts, style: PersonalityArchetype.station),
        ],
      );
      addTearDown(repo.dispose);
      await repo.newGame();

      final bots = _bots(repo);
      expect(bots[0].name, 'Nit');
      expect(bots[1].name, 'Calling Station');
    });

    test('a named pro uses the pro\'s real name', () async {
      final pro = builtInProfiles.first;
      final repo = _repo(playerCount: 2, seatBots: [BotSpec(profile: pro)]);
      addTearDown(repo.dispose);
      await repo.newGame();

      expect(_bots(repo).single.name, pro.name);
    });

    test('repeated personas are numbered', () async {
      final repo = _repo(
        playerCount: 3,
        seatBots: const [
          BotSpec(style: PersonalityArchetype.maniac),
          BotSpec(style: PersonalityArchetype.maniac),
        ],
      );
      addTearDown(repo.dispose);
      await repo.newGame();

      final names = _bots(repo).map((s) => s.name).toList();
      expect(names, ['Maniac 1', 'Maniac 2']);
    });

    test('personality-less / balanced seats fall back to generic names',
        () async {
      final repo = _repo(
        playerCount: 3,
        seatBots: const [
          BotSpec(brain: BotType.heuristic),
          BotSpec(style: PersonalityArchetype.balanced),
        ],
      );
      addTearDown(repo.dispose);
      await repo.newGame();

      for (final s in _bots(repo)) {
        expect(TableConfig.botNamePool, contains(s.name));
      }
    });
  });
}
