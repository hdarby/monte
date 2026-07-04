import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monte/core/domain/ai/home_game_profiles.dart';
import 'package:monte/core/domain/engine/actions.dart';
import 'package:monte/core/domain/engine/game.dart';
import 'package:monte/core/domain/hand_history.dart';
import 'package:monte/features/eval_history/domain/eval_hand.dart';
import 'package:monte/features/eval_history/presentation/eval_history_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

EvalHand _hand(int n) => EvalHand(
  handNumber: n,
  smallBlind: 1,
  bigBlind: 3,
  board: const [],
  players: [
    EvalHandPlayer(
      id: 'p0',
      name: 'x',
      modelId: frankDouglas.id,
      modelLabel: frankDouglas.name,
      position: 'BB',
      seatsFromButton: 2,
      holeCards: const ['As', 'Ks'],
      startingStack: 300,
      finalStack: 300,
      folded: false,
    ),
  ],
  actions: [
    ActionRecord(
      playerId: 'p0',
      street: BettingRound.preflop,
      type: ActionType.call,
      amount: 0,
      potAfter: 0,
    ),
  ],
  results: const [],
);

void main() {
  test('autoTune persists overrides; reset clears them', () async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final notifier = container.read(profileOverridesProvider.notifier);

    // Enough hands to clear the default threshold; measured looser than target.
    final sample = [for (var i = 0; i < 320; i++) _hand(i)];
    final changed = await notifier.autoTune(sample);

    expect(changed, greaterThan(0));
    expect(container.read(profileOverridesProvider).length, greaterThan(0));

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('profile_overrides'), isNotNull);

    await notifier.reset();
    expect(container.read(profileOverridesProvider).isEmpty, isTrue);
    expect(prefs.getString('profile_overrides'), isNull);
  });
}
