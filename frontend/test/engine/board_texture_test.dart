import 'package:flutter_test/flutter_test.dart';
import 'package:monte/core/domain/engine/board_texture.dart';
import 'package:monte/core/domain/engine/card.dart';

List<Card> board(String codes) =>
    [for (final c in codes.split(' ')) Card.fromCode(c)];

void main() {
  group('the six textures', () {
    test('a low rainbow disconnected board is dry and static', () {
      final t = BoardTexture.of(board('Kd 7s 2c'));
      expect(t.isDry, isTrue);
      expect(t.isWet, isFalse);
      expect(t.isStatic, isTrue);
      expect(t.isDynamic, isFalse);
      expect(t.suitedness, Suitedness.rainbow);
    });

    test('a connected two-tone board is wet and dynamic', () {
      final t = BoardTexture.of(board('Jh Th 9s'));
      expect(t.isWet, isTrue);
      expect(t.isDry, isFalse);
      expect(t.isDynamic, isTrue);
      expect(t.connectedness, Connectedness.connected);
      expect(t.flushDrawLive, isTrue);
    });

    test('three of a suit is monochrome and a flush is already possible', () {
      final t = BoardTexture.of(board('Qh 8h 3h'));
      expect(t.isMonochrome, isTrue);
      expect(t.flushPossible, isTrue);
      expect(t.suitedness, Suitedness.monotone);
    });

    test('a pair on board is reported as paired', () {
      final t = BoardTexture.of(board('9s 9d 4c'));
      expect(t.isPaired, isTrue);
      expect(t.paired, isTrue);
      expect(t.trips, isFalse);
    });

    test('trips on board is paired but not a single pair', () {
      final t = BoardTexture.of(board('7s 7d 7c'));
      expect(t.trips, isTrue);
      expect(t.paired, isFalse);
      expect(t.isPaired, isTrue);
    });

    test('textures combine — a board is usually several at once', () {
      final t = BoardTexture.of(board('9s 9d 4c'));
      expect(t.kinds, contains(BoardTextureKind.paired));
      expect(t.kinds.length, greaterThan(1));
    });
  });

  group('static vs dynamic is not the same as dry vs wet', () {
    test('a low dry board is still dynamic-leaning: overcards are coming', () {
      final low = BoardTexture.of(board('7c 4d 2s'));
      final high = BoardTexture.of(board('Ac 8d 3s'));
      expect(low.dynamism, greaterThan(high.dynamism));
    });

    test('an ace-high board is the most static — the top card is out', () {
      final t = BoardTexture.of(board('As 9d 4c'));
      expect(t.isStatic, isTrue);
      expect(t.aceHigh, isTrue);
    });

    test('the river is never dynamic — no cards left to change anything', () {
      final t = BoardTexture.of(board('Jh Th 9s 8h 2c'));
      expect(t.dynamism, 0);
      expect(t.isDynamic, isFalse);
      expect(t.isStatic, isTrue);
    });
  });

  group('range advantage', () {
    test('ace-high boards favour the preflop raiser', () {
      expect(BoardTexture.of(board('Ah Kd 4c')).raiserAdvantage, greaterThan(0));
    });

    test('low connected boards favour the caller', () {
      expect(BoardTexture.of(board('7h 6d 5c')).raiserAdvantage, lessThan(0));
    });
  });

  group('connectedness', () {
    test('detects the wheel with the ace playing low', () {
      expect(
        BoardTexture.of(board('Ah 3d 4c')).connectedness,
        Connectedness.connected,
      );
    });

    test('spread-out ranks are disconnected', () {
      expect(
        BoardTexture.of(board('Kh 8d 3c')).connectedness,
        Connectedness.disconnected,
      );
    });
  });

  group('descriptions', () {
    test('names the textures and the high card', () {
      final d = BoardTexture.of(board('Kd 7s 2c')).description;
      expect(d, contains('dry'));
      expect(d, contains('king-high'));
    });

    test('reports the live draws on a wet board', () {
      final t = BoardTexture.of(board('Jh Th 9s'));
      expect(t.drawPhrase, isNotNull);
      expect(t.drawPhrase, contains('flush draw'));
    });

    test('a dry rainbow board has nothing to chase', () {
      expect(BoardTexture.of(board('Kd 7s 2c')).drawPhrase, isNull);
    });
  });

  group('changeFrom describes the new card', () {
    test('spots the flush completing', () {
      final flop = BoardTexture.of(board('Qh 8h 3s'));
      final turn = BoardTexture.of(board('Qh 8h 3s 2h'));
      expect(turn.changeFrom(flop), contains('flush'));
    });

    test('spots the board pairing', () {
      final flop = BoardTexture.of(board('Qh 8d 3s'));
      final turn = BoardTexture.of(board('Qh 8d 3s 8c'));
      expect(turn.changeFrom(flop), contains('pairs'));
    });

    test('spots a scare overcard', () {
      final flop = BoardTexture.of(board('9h 8d 3s'));
      final turn = BoardTexture.of(board('9h 8d 3s Ac'));
      expect(turn.changeFrom(flop), contains('overcard'));
    });
  });

  test('maybeOf returns null before the flop', () {
    expect(BoardTexture.maybeOf(const []), isNull);
    expect(BoardTexture.maybeOf(board('Ah Kd')), isNull);
    expect(BoardTexture.maybeOf(board('Ah Kd 2c')), isNotNull);
  });
}
