import 'package:flutter_test/flutter_test.dart';
import 'package:monte/core/domain/engine/actions.dart';
import 'package:monte/core/domain/engine/game.dart';
import 'package:monte/core/domain/engine/player.dart';

PokerGame _heads({required int chipUnit}) {
  final g = PokerGame(
    players: [
      Player(id: 'a', name: 'A', stack: 100000),
      Player(id: 'b', name: 'B', stack: 100000),
    ],
    smallBlind: 500,
    bigBlind: 1000,
    chipUnit: chipUnit,
    rotateButton: false,
  );
  g.startHand();
  return g;
}

void main() {
  test('a raise is snapped down to a multiple of the chip unit', () {
    final g = _heads(chipUnit: 500);
    // Request an off-denomination raise to 3,777 -> snaps to 3,500.
    g.applyAction(GameAction(ActionType.raise, amount: 3777));
    expect(g.currentBet, 3500);
  });

  test('chipUnit == 1 leaves the amount exactly as requested', () {
    final g = _heads(chipUnit: 1);
    g.applyAction(GameAction(ActionType.raise, amount: 3777));
    expect(g.currentBet, 3777);
  });

  test('a snap below the minimum raise is clamped up to a legal raise', () {
    final g = _heads(chipUnit: 500);
    // minRaiseTo here is 2000 (currentBet 1000 + bigBlind 1000). Request 1200,
    // which snaps to 1000 then clamps up to the legal minimum, 2000.
    g.applyAction(GameAction(ActionType.raise, amount: 1200));
    expect(g.currentBet, 2000);
    expect(g.currentBet % 500, 0);
  });

  test('chipUnit round-trips through clone()', () {
    final g = _heads(chipUnit: 500);
    expect(g.clone().chipUnit, 500);
  });
}
