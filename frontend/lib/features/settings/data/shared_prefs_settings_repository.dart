import 'package:shared_preferences/shared_preferences.dart';

import 'package:monte/core/domain/ai/bot_spec.dart';
import 'package:monte/core/domain/ai/decider_factory.dart';
import 'package:monte/core/domain/ai/personality.dart';
import 'package:monte/features/settings/domain/game_settings.dart';
import 'package:monte/features/settings/domain/settings_repository.dart';

/// Persists [GameSettings] across runs via [SharedPreferences].
class SharedPrefsSettingsRepository implements SettingsRepository {
  static const _kPlayerCount = 'player_count';
  static const _kShowBigBlinds = 'show_big_blinds';
  static const _kShowBehavior = 'show_behavior';
  static const _kAllBots = 'all_bots';
  static const _kBotType = 'bot_type';
  static const _kBotPersonality = 'bot_personality';
  static const _kSmallBlind = 'small_blind';
  static const _kBigBlind = 'big_blind';
  static const _kStartingStack = 'starting_stack';
  static const _kSeatBots = 'seat_bots';

  @override
  Future<GameSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    final count = (prefs.getInt(_kPlayerCount) ?? 4).clamp(
      GameSettings.minPlayers,
      GameSettings.maxPlayers,
    );
    final stake = GameSettings.sanitizeStake(
      prefs.getInt(_kSmallBlind) ?? 1,
      prefs.getInt(_kBigBlind) ?? 3,
      prefs.getInt(_kStartingStack) ?? 300,
    );
    return GameSettings(
      playerCount: count,
      showBigBlinds: prefs.getBool(_kShowBigBlinds) ?? false,
      showBehavior: prefs.getBool(_kShowBehavior) ?? false,
      allBots: prefs.getBool(_kAllBots) ?? false,
      botType: _enumByName(
        BotType.values,
        prefs.getString(_kBotType),
        BotType.personality,
      ),
      botPersonality: _enumByName(
        PersonalityArchetype.values,
        prefs.getString(_kBotPersonality),
        PersonalityArchetype.balanced,
      ),
      smallBlind: stake.smallBlind,
      bigBlind: stake.bigBlind,
      startingStack: stake.startingStack,
      seatBots: [
        for (final s in prefs.getStringList(_kSeatBots) ?? const [])
          BotSpec.decode(s),
      ],
    );
  }

  @override
  Future<void> save(GameSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kPlayerCount, settings.playerCount);
    await prefs.setBool(_kShowBigBlinds, settings.showBigBlinds);
    await prefs.setBool(_kShowBehavior, settings.showBehavior);
    await prefs.setBool(_kAllBots, settings.allBots);
    await prefs.setString(_kBotType, settings.botType.name);
    await prefs.setString(_kBotPersonality, settings.botPersonality.name);
    await prefs.setInt(_kSmallBlind, settings.smallBlind);
    await prefs.setInt(_kBigBlind, settings.bigBlind);
    await prefs.setInt(_kStartingStack, settings.startingStack);
    await prefs.setStringList(
      _kSeatBots,
      [for (final b in settings.seatBots) b.encode()],
    );
  }

  /// Resolves a stored enum name back to its value, falling back to [fallback]
  /// for missing or unrecognized values (e.g. older installs).
  static T _enumByName<T extends Enum>(
    List<T> values,
    String? name,
    T fallback,
  ) {
    for (final v in values) {
      if (v.name == name) return v;
    }
    return fallback;
  }
}
