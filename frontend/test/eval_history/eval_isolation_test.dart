import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:monte/core/domain/engine/bot.dart';
import 'package:monte/core/domain/engine/deck.dart';
import 'package:monte/features/eval_history/domain/eval_hand.dart';
import 'package:monte/features/table/data/local_game_repository.dart';

void main() {
  // The full-information tuning capture must NOT change what the bot-facing
  // history exposes: folded/mucked cards stay masked in `repo.history`, while the
  // captured `EvalHand` keeps every player's real cards. This is what preserves
  // the "no free information" invariant.
  test('tuning capture keeps full cards; masked history stays masked', () async {
    final captured = <EvalHand>[];
    final repo = LocalGameRepository(
      config: TableConfig(
        allBots: true,
        playerCount: 3,
        botThinkTime: Duration.zero,
        deckBuilder: () => Deck(random: Random(11)),
        deciderBuilder: (i) => BotStrategy(random: Random(20 + i)),
        onEvalHandRecorded: captured.add,
      ),
    );
    addTearDown(repo.dispose);

    await repo.simulate(40);

    // Every finished hand is captured for tuning.
    expect(captured, hasLength(repo.history.length));

    final maskedByHand = {for (final h in repo.history) h.handNumber: h};

    var foldedSeen = 0;
    for (final eval in captured) {
      final masked = maskedByHand[eval.handNumber]!;
      for (final ep in eval.players) {
        // The tuning record always has the real two cards.
        expect(ep.holeCards, hasLength(2),
            reason: 'eval record should keep full cards for ${ep.id}');

        final mp = masked.players.firstWhere((p) => p.id == ep.id);
        if (ep.folded) {
          foldedSeen++;
          // ...but the bot-facing record masks a folder: no cards, not revealed.
          expect(mp.revealed, isFalse,
              reason: 'masked history leaked a folder (${ep.id})');
          expect(mp.holeCards, isEmpty,
              reason: 'masked history exposed folded cards (${ep.id})');
        }
      }
    }

    // Guard against a vacuous pass — folds must actually have occurred.
    expect(foldedSeen, greaterThan(0));
  });
}
