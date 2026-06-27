import 'package:shared_preferences/shared_preferences.dart';

import '../data/local_game_repository.dart';
import 'game_settings.dart';

/// Persists [GameSettings] across runs via [SharedPreferences].
class SettingsStore {
  static const _kPlayerCount = 'player_count';
  static const _kShowBigBlinds = 'show_big_blinds';
  static const _kAllBots = 'all_bots';

  Future<GameSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    final count = (prefs.getInt(_kPlayerCount) ?? 4)
        .clamp(TableConfig.minPlayers, TableConfig.maxPlayers);
    return GameSettings(
      playerCount: count,
      showBigBlinds: prefs.getBool(_kShowBigBlinds) ?? false,
      allBots: prefs.getBool(_kAllBots) ?? false,
    );
  }

  Future<void> save(GameSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kPlayerCount, settings.playerCount);
    await prefs.setBool(_kShowBigBlinds, settings.showBigBlinds);
    await prefs.setBool(_kAllBots, settings.allBots);
  }
}
