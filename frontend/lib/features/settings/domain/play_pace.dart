/// How long each computer opponent is given to act.
///
/// The budget is a *target* per decision, not a fixed wait: on [instant] there
/// is zero artificial delay (bots take only the real engine time), and on the
/// slower steps the MCTS search spends the extra time going deeper rather than
/// idling on a timer (non-search brains simply pace to match). See
/// `LocalGameRepository._runBots`.
enum PlayPace {
  instant('Instant', Duration.zero),
  fast('Fast', Duration(milliseconds: 400)),
  normal('Normal', Duration(milliseconds: 700)),
  slow('Slow', Duration(seconds: 3)),
  study('Study', Duration(seconds: 10));

  const PlayPace(this.label, this.budget);

  /// Human-readable label for the settings control.
  final String label;

  /// Target time each bot decision should take at this pace.
  final Duration budget;
}
