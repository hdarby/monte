import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:monte/features/settings/data/shared_prefs_settings_repository.dart';
import 'package:monte/features/settings/domain/game_settings.dart';
import 'package:monte/features/settings/domain/settings_repository.dart';

/// DI seam for the settings repository — override in tests with a fake.
final settingsRepositoryProvider = Provider<SettingsRepository>(
  (ref) => SharedPrefsSettingsRepository(),
);

/// Owns the persisted [GameSettings]. Loads on build; [update] writes through
/// to the repository and publishes the new state.
class SettingsController extends AsyncNotifier<GameSettings> {
  @override
  Future<GameSettings> build() => ref.read(settingsRepositoryProvider).load();

  /// Publishes [settings] immediately and persists them through the repository.
  Future<void> save(GameSettings settings) async {
    state = AsyncData(settings);
    await ref.read(settingsRepositoryProvider).save(settings);
  }
}

final settingsControllerProvider =
    AsyncNotifierProvider<SettingsController, GameSettings>(
      SettingsController.new,
    );
