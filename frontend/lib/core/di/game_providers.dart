import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:monte/core/domain/ai/bot_spec.dart';
import 'package:monte/core/domain/ai/decider_factory.dart';
import 'package:monte/features/eval_history/presentation/eval_history_provider.dart';
import 'package:monte/features/settings/domain/game_settings.dart';
import 'package:monte/features/settings/presentation/settings_controller.dart';
import 'package:monte/features/reads/data/player_stats_store.dart';
import 'package:monte/features/table/data/local_game_repository.dart';
import 'package:monte/features/table/domain/game_repository.dart';

/// The persistent per-opponent reads model, or null (no accumulation) in tests
/// and headless runs. `main` overrides it with a file-backed, loaded service.
final opponentStatsServiceProvider =
    Provider<OpponentStatsService?>((ref) => null);

/// Composition root for the game.
///
/// Binds [GameRepository] to a concrete implementation, built from the current
/// settings. Rebuilds (disposing the old repository) only when the player count
/// or all-bots mode changes — display-unit changes don't restart the game.
///
/// This is the single place that picks the implementation: to move to
/// client/server, swap [LocalGameRepository] for a `RemoteGameRepository` here
/// and nothing else in the app changes.
final gameRepositoryProvider = Provider<GameRepository>((ref) {
  // Select only the fields that define the game itself, so a display-unit
  // toggle (dollars vs BB) doesn't restart the game — but a stake change does.
  final (
    playerCount,
    allBots,
    botType,
    botPersonality,
    smallBlind,
    bigBlind,
    startingStack,
    seatBotsKey,
    playPace,
  ) = ref.watch(
    settingsControllerProvider.select((s) {
      final v = s.value ?? const GameSettings();
      return (
        v.playerCount,
        v.allBots,
        v.botType,
        v.botPersonality,
        v.smallBlind,
        v.bigBlind,
        v.startingStack,
        // Content-based key so a per-seat lineup change triggers a rebuild.
        v.seatBots.map((b) => b.encode()).join(';'),
        v.playPace,
      );
    }),
  );
  // Each bot seat plays its own configured spec (brain + style, or a named pro),
  // padded with a usable Personality default when shorter than the table.
  final lineup = seatBotsKey.isEmpty
      ? const <BotSpec>[]
      : [for (final s in seatBotsKey.split(';')) BotSpec.decode(s)];
  final botCount = allBots ? playerCount : playerCount - 1;
  final seatBots = [
    for (var i = 0; i < botCount; i++)
      i < lineup.length
          ? lineup[i]
          : const BotSpec(brain: BotType.personality),
  ];
  final repo = LocalGameRepository(
    statsService: ref.watch(opponentStatsServiceProvider),
    config: TableConfig(
      playerCount: playerCount,
      allBots: allBots,
      botType: botType,
      personality: botPersonality.profile,
      defaultStyle: botPersonality,
      seatBots: seatBots,
      smallBlind: smallBlind,
      bigBlind: bigBlind,
      startingStack: startingStack,
      // All-bots evaluation keeps its own fast cadence; interactive play uses
      // the player's chosen pace (slower = deeper MCTS search, not idling).
      botThinkTime:
          allBots ? const Duration(milliseconds: 250) : playPace.budget,
      // Log each interactive hand to the run console (prefixed for grepping) so
      // played hands can be read back for diagnosis.
      onHandRecorded: (hand) {
        for (final line in hand.toReadable().trimRight().split('\n')) {
          // ignore: avoid_print
          print('HHLOG $line');
        }
      },
      // Every finished hand (live + simulated) is appended to the permanent
      // full-information tuning history. This record is never read by a bot.
      onEvalHandRecorded: ref.read(evalHistoryStoreProvider).record,
      // Swap in any tuned preflop baselines from the offline auto-tuner. Watched
      // so a tune rebuilds the table with the new personality parameters.
      overrideProfile: ref.watch(profileOverridesProvider).apply,
    ),
  );
  ref.onDispose(repo.dispose);
  return repo;
});
