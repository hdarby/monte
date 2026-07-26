import 'package:meta/meta.dart';

/// How a tournament's blind levels advance.
enum LevelClockMode {
  /// Each level lasts a fixed number of real minutes (a visible countdown).
  minutes,

  /// Each level lasts a fixed number of hands dealt (deterministic, pace-free).
  hands,
}

/// One rung of the blind schedule. Antes are modelled as a single **big-blind
/// ante** (the modern MTT standard: the big blind posts one ante for the table),
/// so `ante` is the whole-table amount, not per player.
@immutable
class BlindLevel {
  const BlindLevel({
    required this.level,
    required this.smallBlind,
    required this.bigBlind,
    this.ante = 0,
    this.durationMinutes,
    this.durationHands,
    this.isBreak = false,
  })  : assert(level >= 1),
        assert(smallBlind >= 0 && bigBlind >= smallBlind),
        assert(ante >= 0);

  /// 1-indexed level number (breaks share the number of the level they follow).
  final int level;
  final int smallBlind;
  final int bigBlind;

  /// Big-blind ante for the table (0 = no ante). Posted by the big blind.
  final int ante;

  /// Length in minutes ([LevelClockMode.minutes]); null in hands mode.
  final int? durationMinutes;

  /// Length in hands ([LevelClockMode.hands]); null in minutes mode.
  final int? durationHands;

  /// A break (no hands dealt) rather than a playing level.
  final bool isBreak;

  BlindLevel copyWith({
    int? level,
    int? smallBlind,
    int? bigBlind,
    int? ante,
    int? durationMinutes,
    int? durationHands,
    bool? isBreak,
  }) =>
      BlindLevel(
        level: level ?? this.level,
        smallBlind: smallBlind ?? this.smallBlind,
        bigBlind: bigBlind ?? this.bigBlind,
        ante: ante ?? this.ante,
        durationMinutes: durationMinutes ?? this.durationMinutes,
        durationHands: durationHands ?? this.durationHands,
        isBreak: isBreak ?? this.isBreak,
      );
}

/// A tournament's full configuration: the blind schedule, how levels advance,
/// the starting stack, and the re-entry / rebuy policy. Pure data — the live
/// tournament state lives in `TournamentState` and the clock is driven by the
/// controller.
@immutable
class TournamentStructure {
  const TournamentStructure({
    required this.name,
    required this.levels,
    required this.clockMode,
    required this.startingStack,
    this.maxRebuys = 0,
    this.reentryLevelCutoff = 0,
  }) : assert(levels.length > 0);

  final String name;
  final List<BlindLevel> levels;
  final LevelClockMode clockMode;
  final int startingStack;

  /// How many rebuys/re-entries a single entrant may take (0 = freezeout).
  final int maxRebuys;

  /// Rebuys/re-entries are only allowed while the current level number is `<=`
  /// this cutoff (0 = no rebuy period). Ignored when [maxRebuys] is 0.
  final int reentryLevelCutoff;

  bool get allowsRebuys => maxRebuys > 0 && reentryLevelCutoff > 0;

  /// The level at [index] (0-based). Past the last defined level the blinds are
  /// **capped** at the final level (its number keeps climbing so the UI can show
  /// it, but the stakes stop rising).
  BlindLevel levelAt(int index) {
    if (index < levels.length) return levels[index];
    final last = levels.last;
    return last.copyWith(level: last.level + (index - (levels.length - 1)));
  }

  /// The playing duration of the level at [index] under the active clock mode,
  /// falling back to a sane default if a level omits it.
  int durationOf(int index) {
    final l = levelAt(index);
    return switch (clockMode) {
      LevelClockMode.minutes => l.durationMinutes ?? _defaultMinutes,
      LevelClockMode.hands => l.durationHands ?? _defaultHands,
    };
  }

  static const _defaultMinutes = 10;
  static const _defaultHands = 12;

  // ---- Presets -------------------------------------------------------------

  /// A geometric-ish blind ramp shared by the presets: SB doubles-ish each level
  /// with a matching BB, antes kicking in from level 3. [minutes]/[hands] set
  /// the per-level duration for the two clock modes.
  static List<BlindLevel> _ramp({required int minutes, required int hands}) {
    // (sb, bb, ante) rungs — a conventional MTT ladder.
    const rungs = <List<int>>[
      [25, 50, 0],
      [50, 100, 0],
      [75, 150, 150],
      [100, 200, 200],
      [150, 300, 300],
      [200, 400, 400],
      [300, 600, 600],
      [400, 800, 800],
      [600, 1200, 1200],
      [800, 1600, 1600],
      [1000, 2000, 2000],
      [1500, 3000, 3000],
      [2000, 4000, 4000],
      [3000, 6000, 6000],
      [4000, 8000, 8000],
    ];
    return [
      for (var i = 0; i < rungs.length; i++)
        BlindLevel(
          level: i + 1,
          smallBlind: rungs[i][0],
          bigBlind: rungs[i][1],
          ante: rungs[i][2],
          durationMinutes: minutes,
          durationHands: hands,
        ),
    ];
  }

  /// Fast structure: short levels, steep enough to end quickly.
  factory TournamentStructure.turbo({
    LevelClockMode clockMode = LevelClockMode.hands,
    int startingStack = 5000,
  }) =>
      TournamentStructure(
        name: 'Turbo',
        levels: _ramp(minutes: 5, hands: 6),
        clockMode: clockMode,
        startingStack: startingStack,
      );

  /// Balanced structure.
  factory TournamentStructure.standard({
    LevelClockMode clockMode = LevelClockMode.hands,
    int startingStack = 10000,
  }) =>
      TournamentStructure(
        name: 'Standard',
        levels: _ramp(minutes: 12, hands: 12),
        clockMode: clockMode,
        startingStack: startingStack,
      );

  /// Deep-stack structure: long levels, lots of play.
  factory TournamentStructure.deep({
    LevelClockMode clockMode = LevelClockMode.hands,
    int startingStack = 20000,
  }) =>
      TournamentStructure(
        name: 'Deep',
        levels: _ramp(minutes: 20, hands: 20),
        clockMode: clockMode,
        startingStack: startingStack,
      );

  /// The built-in presets by id (lowercase name).
  static TournamentStructure? presetByName(String name) => switch (name) {
        'turbo' => TournamentStructure.turbo(),
        'standard' => TournamentStructure.standard(),
        'deep' => TournamentStructure.deep(),
        _ => null,
      };
}
