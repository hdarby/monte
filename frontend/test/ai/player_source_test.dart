import 'package:flutter_test/flutter_test.dart';
import 'package:monte/core/domain/ai/player_factory.dart';
import 'package:monte/core/domain/ai/player_profile.dart';
import 'package:monte/core/domain/ai/player_source.dart';

void main() {
  group('dartLiteral', () {
    test('renders primitives, lists, and maps', () {
      expect(dartLiteral(null), 'null');
      expect(dartLiteral(true), 'true');
      expect(dartLiteral(0.5), '0.5');
      expect(dartLiteral([1, 2]), '[1, 2]');
      expect(dartLiteral({'a': 1}), "{'a': 1}");
    });

    test('escapes quotes, dollars, backslashes, and newlines', () {
      expect(dartLiteral("a'b"), r"'a\'b'");
      expect(dartLiteral(r'$x'), r"'\$x'");
      expect(dartLiteral('a\nb'), r"'a\nb'");
      expect(dartLiteral(r'c\d'), r"'c\\d'");
    });
  });

  group('customPlayersDartFile', () {
    test('emits both lists and one fromJson per profile', () {
      final rec = PlayerFactory.recreational(
        id: 'H500',
        name: "O'Fish",
        strength: 4,
        description: 'line one\nline two',
      );
      final pro = PlayerFactory.pro(
        id: 'P500',
        name: 'Pro One',
        vpip: 0.24,
        pfr: 0.2,
        threeBet: 0.09,
        characteristics: const [
          PlayerCharacteristic(id: 'GTO_Adherence', proficiency: 0.9),
        ],
      );
      final src = customPlayersDartFile(recs: [rec], pros: [pro]);

      expect(src, contains('final List<PlayerProfile> customRecreationalPlayers'));
      expect(src, contains('final List<PlayerProfile> customPros'));
      expect(
        "import 'package:monte/core/domain/ai/player_profile.dart';",
        predicate<String>((imp) => src.contains(imp)),
      );
      // One fromJson per profile.
      expect('PlayerProfile.fromJson('.allMatches(src).length, 2);
      // Ids and the escaped apostrophe survive.
      expect(src, contains("'id': 'H500'"));
      expect(src, contains("'id': 'P500'"));
      expect(src, contains(r"O\'Fish"));
      // Newlines in the description are escaped, not literal.
      expect(src, contains(r'line one\nline two'));
    });
  });
}
