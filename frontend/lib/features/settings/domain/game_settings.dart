import 'package:monte/core/domain/ai/bot_spec.dart';
import 'package:monte/core/domain/ai/decider_factory.dart';
import 'package:monte/core/domain/ai/personality.dart';

/// User-configurable, persisted game settings.
class GameSettings {
  const GameSettings({
    this.playerCount = 4,
    this.showBigBlinds = false,
    this.showBehavior = false,
    this.allBots = false,
    this.botType = BotType.personality,
    this.botPersonality = PersonalityArchetype.balanced,
    this.smallBlind = 1,
    this.bigBlind = 3,
    this.startingStack = 300,
    this.seatBots = const [],
  });

  /// Supported table-size bounds (2 = heads-up … 10 = full ring).
  static const int minPlayers = 2;
  static const int maxPlayers = 10;

  /// Floors for the stake fields (kept ≥ 1 chip; buy-in ≥ one big blind).
  static const int minBlind = 1;
  static const int minStack = 1;

  /// Clamps a raw (blind, blind, stack) triple into a coherent stake:
  /// big blind ≥ 1, small blind in `[1, bigBlind]`, buy-in ≥ big blind.
  static ({int smallBlind, int bigBlind, int startingStack}) sanitizeStake(
    int smallBlind,
    int bigBlind,
    int startingStack,
  ) {
    final bb = bigBlind < minBlind ? minBlind : bigBlind;
    final sb = smallBlind.clamp(minBlind, bb);
    final stack = startingStack < bb ? bb : startingStack;
    return (smallBlind: sb, bigBlind: bb, startingStack: stack);
  }

  /// Total seats including the human (2 = heads-up … 10 = full table).
  final int playerCount;

  /// When true, chip amounts are shown in big blinds (e.g. "100 BB"); when
  /// false, in actual dollars (e.g. "$1000").
  final bool showBigBlinds;

  /// When true, each bot seat shows its behavior model (brain + playing style)
  /// as a small badge — handy for telling personalities apart at a glance.
  final bool showBehavior;

  /// Evaluation mode: every seat is a bot, hands play out automatically. Useful
  /// for quickly generating hand histories to validate engine/bot changes.
  final bool allBots;

  /// Which brain the bots use (heuristic, personality, or MCTS search).
  final BotType botType;

  /// The personality archetype shaping the bots' play (applies to personality
  /// and MCTS bots).
  final PersonalityArchetype botPersonality;

  /// The stake: small blind, big blind, and the buy-in (each seat's starting
  /// stack). Changing any of these starts a fresh game at the new stake.
  final int smallBlind;
  final int bigBlind;
  final int startingStack;

  /// Per-bot-seat behavior model (brain + style, or a named pro), in seat order
  /// (human excluded). Empty means every bot uses the defaults. Length tracks the
  /// table via [seatBotsFor].
  final List<BotSpec> seatBots;

  /// How many seats are bots (the human takes one unless [allBots]).
  int get botSeatCount => allBots ? playerCount : playerCount - 1;

  /// [seatBots] padded (with a usable Personality default) or truncated to
  /// [count], so the per-seat list always matches the current bot count.
  List<BotSpec> seatBotsFor(int count) => [
    for (var i = 0; i < count; i++)
      i < seatBots.length
          ? seatBots[i]
          : const BotSpec(brain: BotType.personality),
  ];

  GameSettings copyWith({
    int? playerCount,
    bool? showBigBlinds,
    bool? showBehavior,
    bool? allBots,
    BotType? botType,
    PersonalityArchetype? botPersonality,
    int? smallBlind,
    int? bigBlind,
    int? startingStack,
    List<BotSpec>? seatBots,
  }) => GameSettings(
    playerCount: playerCount ?? this.playerCount,
    showBigBlinds: showBigBlinds ?? this.showBigBlinds,
    showBehavior: showBehavior ?? this.showBehavior,
    allBots: allBots ?? this.allBots,
    botType: botType ?? this.botType,
    botPersonality: botPersonality ?? this.botPersonality,
    smallBlind: smallBlind ?? this.smallBlind,
    bigBlind: bigBlind ?? this.bigBlind,
    startingStack: startingStack ?? this.startingStack,
    seatBots: seatBots ?? this.seatBots,
  );
}
