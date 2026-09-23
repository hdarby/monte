part of 'local_game_repository.dart';

/// Snapshot building/publishing, split out of [LocalGameRepository] because
/// it's the one seam that only ever *reads* game/seat state to project a
/// [TableSnapshot] — it never mutates anything.
extension LocalGameRepositorySnapshot on LocalGameRepository {
  void _publish() {
    _snapshot = _buildSnapshot();
    if (!_controller.isClosed) _controller.add(_snapshot);
  }

  TableSnapshot _buildSnapshot() => projectTableSnapshot(
    _game!,
    // In all-bots mode there's no human to protect, so reveal everyone.
    revealAll: config.allBots,
    behaviorLabels: {
      for (final e in _specByPlayer.entries) e.key: e.value.label,
    },
    // Colour each seat pro vs recreational, matching the tournament table.
    seatProfiles: {
      for (final e in _specByPlayer.entries)
        if (e.value.profile != null) e.key: e.value.profile!,
    },
    // Flag busted seats only in human-vs-bots play (all-bots tops up).
    flagBusted: !config.allBots,
  );
}
