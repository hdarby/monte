import 'package:monte/core/domain/ai/decider_factory.dart';
import 'package:monte/core/domain/ai/personality.dart';

/// User-configurable, persisted game settings.
class GameSettings {
  const GameSettings({
    this.playerCount = 4,
    this.showBigBlinds = false,
    this.allBots = false,
    this.botType = BotType.heuristic,
    this.botPersonality = PersonalityArchetype.balanced,
  });

  /// Supported table-size bounds (2 = heads-up … 10 = full ring).
  static const int minPlayers = 2;
  static const int maxPlayers = 10;

  /// Total seats including the human (2 = heads-up … 10 = full table).
  final int playerCount;

  /// When true, chip amounts are shown in big blinds (e.g. "100 BB"); when
  /// false, in actual dollars (e.g. "$1000").
  final bool showBigBlinds;

  /// Evaluation mode: every seat is a bot, hands play out automatically. Useful
  /// for quickly generating hand histories to validate engine/bot changes.
  final bool allBots;

  /// Which brain the bots use (heuristic, personality, or MCTS search).
  final BotType botType;

  /// The personality archetype shaping the bots' play (applies to personality
  /// and MCTS bots).
  final PersonalityArchetype botPersonality;

  GameSettings copyWith({
    int? playerCount,
    bool? showBigBlinds,
    bool? allBots,
    BotType? botType,
    PersonalityArchetype? botPersonality,
  }) => GameSettings(
    playerCount: playerCount ?? this.playerCount,
    showBigBlinds: showBigBlinds ?? this.showBigBlinds,
    allBots: allBots ?? this.allBots,
    botType: botType ?? this.botType,
    botPersonality: botPersonality ?? this.botPersonality,
  );
}
