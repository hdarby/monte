import 'package:monte/core/domain/ai/bot_spec.dart';
import 'package:monte/core/domain/ai/decider_factory.dart';
import 'package:monte/core/domain/ai/personality.dart';
import 'package:monte/core/domain/ai/player_profile.dart';
import 'package:monte/core/domain/engine/deck.dart';
import 'package:monte/core/domain/engine/decision_policy.dart';
import 'package:monte/core/domain/hand_history.dart';
import 'package:monte/features/eval_history/domain/eval_hand.dart';

/// Static table configuration for a client-only game.
class TableConfig {
  const TableConfig({
    this.humanName = 'You',
    this.playerCount = 4,
    this.startingStack = 1000,
    this.smallBlind = 5,
    this.bigBlind = 10,
    this.allBots = false,
    this.botThinkTime = const Duration(milliseconds: 700),
    this.botType = BotType.heuristic,
    this.personality = const PersonalityProfile.balanced(),
    this.defaultStyle = PersonalityArchetype.balanced,
    this.seatBots = const [],
    this.rotateButton = true,
    this.mctsIterations = 250,
    this.deckBuilder,
    this.deciderBuilder,
    this.onHandRecorded,
    this.onEvalHandRecorded,
    this.playersRemaining,
    this.overrideProfile,
  });

  /// Total seats including the human. 2 = heads-up, up to 10 for a full table.
  final int playerCount;

  /// When true, every seat is a bot (evaluation mode, no human).
  final bool allBots;

  final String humanName;
  final int startingStack;
  final int smallBlind;
  final int bigBlind;

  /// Target time each bot decision should take (the pace-of-play budget). It's
  /// not idle waiting: an MCTS seat spends it searching *deeper* (see
  /// [_runBots] / [IsmctsEngine.decideTimed]); other brains decide instantly and
  /// then pad to this target so pacing feels uniform. [Duration.zero] = no
  /// artificial delay and no deepening (pure engine speed).
  final Duration botThinkTime;

  /// The default brain the bots use, and the personality shaping it. Used for
  /// any bot seat not covered by [seatBots].
  final BotType botType;
  final PersonalityProfile personality;

  /// The archetype matching [personality], used to label fallback bot seats
  /// (those not covered by [seatBots]) accurately on their behavior badge.
  final PersonalityArchetype defaultStyle;

  /// Optional per-bot-seat behavior models (brain + style), in seat order
  /// (excluding the human). Bot seats past the end of this list fall back to
  /// [botType] + [personality]. Empty means every bot uses the defaults.
  final List<BotSpec> seatBots;

  /// Whether the dealer button rotates each hand (normal play) or stays pinned
  /// to one seat — handy in evaluation to isolate positional effects.
  final bool rotateButton;

  /// Search budget per decision for [BotType.mcts].
  final int mctsIterations;

  /// Optional deck source — supply a seeded or [Deck.stacked] deck for
  /// reproducible games and tests. Defaults to a fresh shuffled deck.
  final Deck Function()? deckBuilder;

  /// Optional per-seat decider override (seat index = bot index, human
  /// excluded). Returns null to fall back to the configured brain. Used by
  /// evaluation to drop in arbitrary policies (e.g. a calibrated profile).
  final DecisionPolicy? Function(int seatIndex)? deciderBuilder;

  /// Called for each finished hand of *interactive* play (not batch
  /// [simulate]), e.g. to log a transcript for diagnosis.
  final void Function(HandHistory hand)? onHandRecorded;

  /// Called for **every** finished hand (interactive *and* batch [simulate])
  /// with the full-information tuning record — all hole cards, positions, and
  /// the model each seat played. Feeds the permanent tuning history; must never
  /// be routed to a bot / opponent model (that would leak folded cards).
  final void Function(EvalHand hand)? onEvalHandRecorded;

  /// Runners still alive in the tournament, recorded on each [EvalHand].
  ///
  /// A shove or a fold near a pay jump can only be judged against the size of
  /// the field; without it every hand reads as a cash-game spot and ICM
  /// discipline looks like nitting. Null at a cash table.
  final int? playersRemaining;

  /// Maps a seat's named [PlayerProfile] to the *effective* profile to play —
  /// used to swap in the offline auto-tuner's tuned preflop baseline. Identity
  /// when null. Applied to profile seats only, before the decider is built.
  final PlayerProfile Function(PlayerProfile profile)? overrideProfile;

  /// Smallest and largest supported table sizes.
  static const int minPlayers = 2;
  static const int maxPlayers = 10;

  /// Names assigned to bots, in seat order (enough for a full table).
  static const List<String> botNamePool = [
    'Ada',
    'Boris',
    'Chen',
    'Dora',
    'Eli',
    'Farah',
    'Gus',
    'Hana',
    'Ivan',
    'Jo',
  ];

  int get botCount => allBots ? playerCount : playerCount - 1;
}
