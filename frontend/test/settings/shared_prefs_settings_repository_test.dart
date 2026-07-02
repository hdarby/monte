import 'package:flutter_test/flutter_test.dart';
import 'package:monte/core/domain/ai/bot_spec.dart';
import 'package:monte/core/domain/ai/decider_factory.dart';
import 'package:monte/core/domain/ai/personality.dart';
import 'package:monte/core/domain/ai/player_profiles.dart';
import 'package:monte/features/settings/data/shared_prefs_settings_repository.dart';
import 'package:monte/features/settings/domain/game_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('SharedPrefsSettingsRepository', () {
    test('load returns defaults when nothing is stored', () async {
      SharedPreferences.setMockInitialValues({});
      final settings = await SharedPrefsSettingsRepository().load();

      expect(settings.playerCount, 4);
      expect(settings.showBigBlinds, isFalse);
      expect(settings.allBots, isFalse);
      expect(settings.botType, BotType.personality);
      expect(settings.botPersonality, PersonalityArchetype.balanced);
    });

    test('save then load round-trips all fields', () async {
      SharedPreferences.setMockInitialValues({});
      final repo = SharedPrefsSettingsRepository();

      await repo.save(
        const GameSettings(
          playerCount: 6,
          showBigBlinds: true,
          allBots: true,
          botType: BotType.mcts,
          botPersonality: PersonalityArchetype.lag,
        ),
      );
      final loaded = await repo.load();

      expect(loaded.playerCount, 6);
      expect(loaded.showBigBlinds, isTrue);
      expect(loaded.allBots, isTrue);
      expect(loaded.botType, BotType.mcts);
      expect(loaded.botPersonality, PersonalityArchetype.lag);
    });

    test('load falls back gracefully on an unrecognized stored enum', () async {
      SharedPreferences.setMockInitialValues({'bot_type': 'bogus'});
      final settings = await SharedPrefsSettingsRepository().load();
      expect(settings.botType, BotType.personality);
    });

    test('load clamps an out-of-range player count', () async {
      SharedPreferences.setMockInitialValues({'player_count': 99});
      final settings = await SharedPrefsSettingsRepository().load();
      expect(settings.playerCount, GameSettings.maxPlayers);
    });

    test('defaults the stake to 1/3 with a 300 buy-in', () async {
      SharedPreferences.setMockInitialValues({});
      final s = await SharedPrefsSettingsRepository().load();
      expect(s.smallBlind, 1);
      expect(s.bigBlind, 3);
      expect(s.startingStack, 300);
    });

    test('round-trips a custom stake', () async {
      SharedPreferences.setMockInitialValues({});
      final repo = SharedPrefsSettingsRepository();
      await repo.save(
        const GameSettings(
          smallBlind: 25,
          bigBlind: 50,
          startingStack: 5000,
        ),
      );
      final loaded = await repo.load();
      expect(loaded.smallBlind, 25);
      expect(loaded.bigBlind, 50);
      expect(loaded.startingStack, 5000);
    });

    test('round-trips a per-seat lineup incl. a custom bot and a pro', () async {
      SharedPreferences.setMockInitialValues({});
      final repo = SharedPrefsSettingsRepository();
      final specs = [
        const BotSpec(brain: BotType.personality, style: PersonalityArchetype.nit),
        const BotSpec(brain: BotType.mcts, style: PersonalityArchetype.maniac),
        BotSpec(profile: builtInProfiles.first),
      ];
      await repo.save(GameSettings(seatBots: specs));
      final loaded = await repo.load();
      expect(loaded.seatBots, specs);
      expect(loaded.seatBots[2].isProfile, isTrue);
      expect(loaded.seatBots[2].profile!.id, builtInProfiles.first.id);
    });

    test('defaults the per-seat lineup to empty when unset', () async {
      SharedPreferences.setMockInitialValues({});
      final s = await SharedPrefsSettingsRepository().load();
      expect(s.seatBots, isEmpty);
    });

    test('sanitizes an incoherent stored stake on load', () async {
      // sb > bb, and buy-in below the big blind.
      SharedPreferences.setMockInitialValues({
        'small_blind': 200,
        'big_blind': 50,
        'starting_stack': 10,
      });
      final s = await SharedPrefsSettingsRepository().load();
      expect(s.bigBlind, 50);
      expect(s.smallBlind, 50); // clamped down to the big blind
      expect(s.startingStack, greaterThanOrEqualTo(s.bigBlind));
    });
  });
}
