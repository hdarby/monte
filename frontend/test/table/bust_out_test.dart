import 'package:flutter_test/flutter_test.dart';
import 'package:monte/core/domain/ai/decider_factory.dart';
import 'package:monte/core/domain/ai/personality.dart';
import 'package:monte/core/domain/engine/actions.dart';
import 'package:monte/core/domain/engine/card.dart';
import 'package:monte/core/domain/engine/deck.dart';
import 'package:monte/features/table/data/local_game_repository.dart';
import 'package:monte/features/table/domain/table_snapshot.dart';

import '../_helpers.dart';

/// A heads-up deal where the human (seat 0) is crushed: 2♣7♦ vs A♠A♥ on a
/// blank board. Deal order: p0,p1,p0,p1 holes; burn; flop×3; burn; turn; burn;
/// river.
List<Card> _humanBustsDeal() {
  final placed = <int, Card>{
    0: card('2c'), 2: card('7d'), // human
    1: card('As'), 3: card('Ah'), // bot
    5: card('Kd'), 6: card('Qs'), 7: card('9h'), 9: card('4c'), 11: card('3s'),
  };
  final used = placed.values.toSet();
  final rest = [
    for (final suit in Suit.values)
      for (final rank in Rank.values)
        if (!used.contains(Card(rank, suit))) Card(rank, suit),
  ];
  var r = 0;
  return [for (var i = 0; i < 52; i++) placed[i] ?? rest[r++]];
}

LocalGameRepository _repo({
  bool allBots = false,
  int stack = 1000,
  Deck Function()? deckBuilder,
}) => LocalGameRepository(
  config: TableConfig(
    playerCount: 2,
    startingStack: stack,
    allBots: allBots,
    botType: BotType.heuristic,
    botThinkTime: Duration.zero,
    deckBuilder: deckBuilder,
  ),
);

SeatView _seat(LocalGameRepository repo, String id) =>
    repo.snapshot.seats.firstWhere((s) => s.id == id);

void main() {
  group('bust-out', () {
    test('a busted seat is flagged at hand end (human-vs-bots)', () async {
      final repo = _repo(
        stack: 100,
        deckBuilder: () => Deck.stacked(_humanBustsDeal()),
      );
      addTearDown(repo.dispose);
      await repo.newGame();

      // Human shoves into the bot's aces and loses everything.
      expect(repo.snapshot.isHumanTurn, isTrue);
      await repo.submitAction(const GameAction.allIn());

      expect(repo.snapshot.isHandOver, isTrue);
      expect(_seat(repo, 'human').stack, 0);
      expect(repo.snapshot.bustedPlayerIds, contains('human'));
    });

    test('reloadPlayer refills the bankroll and clears the flag', () async {
      final repo = _repo(
        stack: 100,
        deckBuilder: () => Deck.stacked(_humanBustsDeal()),
      );
      addTearDown(repo.dispose);
      await repo.newGame();
      await repo.submitAction(const GameAction.allIn());
      expect(repo.snapshot.bustedPlayerIds, contains('human'));

      repo.reloadPlayer('human');

      expect(_seat(repo, 'human').stack, 100);
      expect(repo.snapshot.bustedPlayerIds, isNot(contains('human')));
    });

    test(
      'replacePlayer reseats a bot with a full stack and a new name',
      () async {
        final repo = _repo(stack: 500);
        addTearDown(repo.dispose);
        await repo.newGame();

        final originalName = _seat(repo, 'bot_0').name;
        repo.replacePlayer('bot_0', PersonalityArchetype.maniac);

        final seat = _seat(repo, 'bot_0');
        expect(seat.stack, 500);
        expect(seat.name, isNot(originalName));
      },
    );

    test('all-bots evaluation never flags busts (stacks top up each hand)', () {
      final repo = _repo(allBots: true);
      addTearDown(repo.dispose);
      repo.simulate(5);
      expect(repo.snapshot.bustedPlayerIds, isEmpty);
    });
  });
}
