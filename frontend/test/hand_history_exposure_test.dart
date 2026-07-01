import 'package:flutter_test/flutter_test.dart';
import 'package:monte/core/domain/ai/decider_factory.dart';
import 'package:monte/core/domain/engine/actions.dart';
import 'package:monte/core/domain/engine/card.dart';
import 'package:monte/core/domain/engine/deck.dart';
import 'package:monte/features/table/data/local_game_repository.dart';

import '_helpers.dart';

// Heads-up deal placing both holes and a board where the engine deals them.
List<Card> _deal({
  required List<Card> human,
  required List<Card> bot,
  required List<Card> board,
}) {
  final placed = <int, Card>{
    0: human[0], 2: human[1],
    1: bot[0], 3: bot[1],
    5: board[0], 6: board[1], 7: board[2], 9: board[3], 11: board[4],
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

LocalGameRepository _repo(List<Card> deal) => LocalGameRepository(
      config: TableConfig(
        playerCount: 2,
        startingStack: 1000,
        botType: BotType.heuristic,
        botThinkTime: Duration.zero,
        deckBuilder: () => Deck.stacked(deal),
      ),
    );

void main() {
  group('hand-history exposure', () {
    test('a folded bot is masked; the human always sees their own cards', () async {
      // Human shoves AA; the bot folds 7-2 offsuit preflop -> no showdown.
      final repo = _repo(_deal(
        human: cards('As Ah'),
        bot: cards('7c 2d'),
        board: cards('Kd Qs 9h 4c 3s'),
      ));
      addTearDown(repo.dispose);
      await repo.newGame();
      expect(repo.snapshot.isHumanTurn, isTrue);
      await repo.submitAction(const GameAction.allIn());
      expect(repo.snapshot.isHandOver, isTrue);

      final hand = repo.history.last;
      final human = hand.players.firstWhere((p) => p.id == 'human');
      final bot = hand.players.firstWhere((p) => p.id == 'bot_0');

      expect(human.revealed, isTrue);
      expect(human.holeCards, ['As', 'Ah']);
      expect(bot.revealed, isFalse, reason: 'folded bot never exposed');
      expect(bot.holeCards, isEmpty);
    });

    test('showdown reveals both contenders', () async {
      // Human shoves 2-7; the bot calls with AA -> both reach showdown.
      final repo = _repo(_deal(
        human: cards('2c 7d'),
        bot: cards('As Ah'),
        board: cards('Kd Qs 9h 4c 3s'),
      ));
      addTearDown(repo.dispose);
      await repo.newGame();
      await repo.submitAction(const GameAction.allIn());
      expect(repo.snapshot.isHandOver, isTrue);

      final hand = repo.history.last;
      final human = hand.players.firstWhere((p) => p.id == 'human');
      final bot = hand.players.firstWhere((p) => p.id == 'bot_0');

      expect(human.revealed, isTrue);
      expect(human.holeCards, ['2c', '7d']);
      expect(bot.revealed, isTrue, reason: 'reached showdown');
      expect(bot.holeCards, ['As', 'Ah']);
    });
  });
}
