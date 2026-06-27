/// User-configurable, persisted game settings.
class GameSettings {
  const GameSettings({
    this.playerCount = 4,
    this.showBigBlinds = false,
    this.allBots = false,
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

  GameSettings copyWith({
    int? playerCount,
    bool? showBigBlinds,
    bool? allBots,
  }) => GameSettings(
    playerCount: playerCount ?? this.playerCount,
    showBigBlinds: showBigBlinds ?? this.showBigBlinds,
    allBots: allBots ?? this.allBots,
  );
}
