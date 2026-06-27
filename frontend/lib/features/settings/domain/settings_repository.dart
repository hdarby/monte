import 'package:poker_client/features/settings/domain/game_settings.dart';

/// Loads and persists [GameSettings]. Framework-free domain contract; the
/// implementation lives in the data layer.
abstract class SettingsRepository {
  Future<GameSettings> load();
  Future<void> save(GameSettings settings);
}
