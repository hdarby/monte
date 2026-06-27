import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monte/features/settings/domain/game_settings.dart';
import 'package:monte/features/settings/domain/settings_repository.dart';
import 'package:monte/features/settings/presentation/settings_controller.dart';

/// In-memory fake to assert the controller talks to the repository correctly.
class _FakeSettingsRepository implements SettingsRepository {
  _FakeSettingsRepository(this.stored);

  GameSettings stored;
  int saveCount = 0;

  @override
  Future<GameSettings> load() async => stored;

  @override
  Future<void> save(GameSettings settings) async {
    stored = settings;
    saveCount++;
  }
}

ProviderContainer _containerWith(SettingsRepository repo) {
  final container = ProviderContainer(
    overrides: [settingsRepositoryProvider.overrideWithValue(repo)],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  group('SettingsController', () {
    test('build loads settings from the repository', () async {
      final fake = _FakeSettingsRepository(const GameSettings(playerCount: 8));
      final container = _containerWith(fake);

      final settings = await container.read(settingsControllerProvider.future);

      expect(settings.playerCount, 8);
    });

    test('update publishes new state and persists it', () async {
      final fake = _FakeSettingsRepository(const GameSettings());
      final container = _containerWith(fake);
      await container.read(settingsControllerProvider.future); // ensure built

      await container
          .read(settingsControllerProvider.notifier)
          .save(const GameSettings(playerCount: 2, allBots: true));

      expect(container.read(settingsControllerProvider).value!.playerCount, 2);
      expect(container.read(settingsControllerProvider).value!.allBots, isTrue);
      expect(fake.stored.playerCount, 2);
      expect(fake.saveCount, 1);
    });
  });
}
