import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monte/core/di/game_providers.dart';
import 'package:monte/core/domain/ai/bot_spec.dart';
import 'package:monte/core/domain/ai/decider_factory.dart';
import 'package:monte/core/domain/ai/personality.dart';
import 'package:monte/features/analytics/domain/analytics.dart';
import 'package:monte/features/settings/domain/game_settings.dart';
import 'package:monte/features/settings/domain/settings_repository.dart';
import 'package:monte/features/settings/presentation/settings_controller.dart';
import 'package:monte/features/table/data/local_game_repository.dart';

class _FakeSettingsRepo implements SettingsRepository {
  _FakeSettingsRepo(this.settings);
  final GameSettings settings;
  @override
  Future<GameSettings> load() async => settings;
  @override
  Future<void> save(GameSettings s) async {}
}

void main() {
  test('per-seat personalities from settings reach the deciders', () async {
    const settings = GameSettings(
      allBots: true,
      playerCount: 3,
      seatBots: [
        BotSpec(brain: BotType.personality, style: PersonalityArchetype.nit),
        BotSpec(brain: BotType.personality, style: PersonalityArchetype.maniac),
        BotSpec(brain: BotType.personality, style: PersonalityArchetype.balanced),
      ],
    );
    final container = ProviderContainer(
      overrides: [
        settingsRepositoryProvider.overrideWithValue(
          _FakeSettingsRepo(settings),
        ),
      ],
    );
    addTearDown(container.dispose);

    // Let the async settings controller resolve, then build the repo from them.
    await container.read(settingsControllerProvider.future);
    final repo = container.read(gameRepositoryProvider) as LocalGameRepository;

    await repo.simulate(500);
    final stats = PokerAnalytics.compute(repo.history);
    final nit = stats.firstWhere((s) => s.id == 'bot_0');
    final maniac = stats.firstWhere((s) => s.id == 'bot_1');

    // Seat 0 (nit) plays far tighter than seat 1 (maniac) — proving each seat
    // got its own personality rather than one global setting.
    expect(maniac.vpip, greaterThan(nit.vpip + 30));
  });
}
