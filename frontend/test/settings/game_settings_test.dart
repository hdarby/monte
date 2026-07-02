import 'package:flutter_test/flutter_test.dart';
import 'package:monte/core/domain/ai/bot_spec.dart';
import 'package:monte/core/domain/ai/decider_factory.dart';
import 'package:monte/core/domain/ai/personality.dart';
import 'package:monte/features/settings/domain/game_settings.dart';

void main() {
  group('GameSettings per-seat lineup', () {
    test('botSeatCount accounts for the human seat', () {
      expect(const GameSettings(playerCount: 6).botSeatCount, 5);
      expect(const GameSettings(playerCount: 6, allBots: true).botSeatCount, 6);
    });

    test('seatBotsFor pads with a Personality default', () {
      const s = GameSettings(
        seatBots: [BotSpec(brain: BotType.mcts, style: PersonalityArchetype.nit)],
      );
      final out = s.seatBotsFor(3);
      expect(out, hasLength(3));
      expect(out[0], const BotSpec(brain: BotType.mcts, style: PersonalityArchetype.nit));
      expect(out[1].brain, BotType.personality);
      expect(out[2].brain, BotType.personality);
    });

    test('seatBotsFor truncates an over-long lineup', () {
      const s = GameSettings(
        seatBots: [
          BotSpec(style: PersonalityArchetype.nit),
          BotSpec(style: PersonalityArchetype.maniac),
          BotSpec(style: PersonalityArchetype.lag),
        ],
      );
      expect(s.seatBotsFor(2), [
        const BotSpec(style: PersonalityArchetype.nit),
        const BotSpec(style: PersonalityArchetype.maniac),
      ]);
    });
  });
}
