import 'package:flutter_test/flutter_test.dart';
import 'package:monte/core/domain/ai/decider_factory.dart';
import 'package:monte/core/domain/ai/personality.dart';
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
      expect(settings.botType, BotType.heuristic);
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
      expect(settings.botType, BotType.heuristic);
    });

    test('load clamps an out-of-range player count', () async {
      SharedPreferences.setMockInitialValues({'player_count': 99});
      final settings = await SharedPrefsSettingsRepository().load();
      expect(settings.playerCount, GameSettings.maxPlayers);
    });
  });
}
