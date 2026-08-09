import 'package:monte/features/tournament/domain/tournament_structure.dart';

/// The blind structures offered in the lobby.
///
/// Replaces the loose `'turbo'`/`'wsop'` strings the lobby used to switch on:
/// the label and the structure now travel with the value, so adding a preset is
/// one enum case rather than edits in three places.
enum TournamentPreset {
  turbo('Turbo'),
  standard('Standard'),
  deep('Deep'),
  circuit('WSOP Circuit'),
  wsopMain('WSOP Main');

  const TournamentPreset(this.label);

  /// Human-readable name for the lobby chip.
  final String label;

  /// The blind ladder this preset plays. Hand-based clocks throughout, so a
  /// level advances by hands dealt rather than wall-clock time.
  TournamentStructure get structure => switch (this) {
    TournamentPreset.turbo => TournamentStructure.turbo(
      clockMode: LevelClockMode.hands,
    ),
    TournamentPreset.standard => TournamentStructure.standard(
      clockMode: LevelClockMode.hands,
    ),
    TournamentPreset.deep => TournamentStructure.deep(
      clockMode: LevelClockMode.hands,
    ),
    TournamentPreset.circuit => TournamentStructure.wsopCircuit(
      clockMode: LevelClockMode.hands,
    ),
    TournamentPreset.wsopMain => TournamentStructure.wsopMainEvent(
      clockMode: LevelClockMode.hands,
    ),
  };
}
