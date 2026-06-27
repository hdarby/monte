import 'package:shared_preferences/shared_preferences.dart';

import 'package:poker_client/features/settings/domain/game_settings.dart';
import 'package:poker_client/features/settings/domain/settings_repository.dart';

/// Persists [GameSettings] across runs via [SharedPreferences].
class SharedPrefsSettingsRepository implements SettingsRepository {
  static const _kPlayerCount = 'player_count';
  static const _kShowBigBlinds = 'show_big_blinds';
  static const _kAllBots = 'all_bots';

  @override
  Future<GameSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    final count = (prefs.getInt(_kPlayerCount) ?? 4).clamp(
      GameSettings.minPlayers,
      GameSettings.maxPlayers,
    );
    return GameSettings(
      playerCount: count,
      showBigBlinds: prefs.getBool(_kShowBigBlinds) ?? false,
      allBots: prefs.getBool(_kAllBots) ?? false,
    );
  }

  @override
  Future<void> save(GameSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kPlayerCount, settings.playerCount);
    await prefs.setBool(_kShowBigBlinds, settings.showBigBlinds);
    await prefs.setBool(_kAllBots, settings.allBots);
  }
}
