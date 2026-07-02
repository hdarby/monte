import 'package:flutter_test/flutter_test.dart';
import 'package:monte/core/domain/ai/bot_spec.dart';
import 'package:monte/core/domain/ai/decider_factory.dart';
import 'package:monte/core/domain/ai/personality.dart';
import 'package:monte/core/domain/ai/player_profiles.dart';

void main() {
  group('BotSpec.encode/decode', () {
    test('round-trips a custom brain + style', () {
      const spec = BotSpec(
        brain: BotType.mcts,
        style: PersonalityArchetype.maniac,
      );
      expect(BotSpec.decode(spec.encode()), spec);
    });

    test('round-trips a named pro by id', () {
      final spec = BotSpec(profile: builtInProfiles.first);
      final decoded = BotSpec.decode(spec.encode());
      expect(decoded.isProfile, isTrue);
      expect(decoded.profile!.id, builtInProfiles.first.id);
    });

    test('falls back safely on malformed / unknown input', () {
      // Missing fields and bad enum names never throw.
      expect(BotSpec.decode('').brain, BotType.personality);
      final d = BotSpec.decode('bogus:nonsense:ZZZ');
      expect(d.brain, BotType.personality);
      expect(d.style, PersonalityArchetype.balanced);
      expect(d.profile, isNull); // unknown id => custom
    });
  });
}
