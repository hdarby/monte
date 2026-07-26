import 'package:meta/meta.dart';

/// The tournament situation for one decision, injected into bots so they can play
/// ICM/bubble-aware poker without knowing anything about the tournament plumbing.
/// A plain value object (no dependency on the tournament feature) — the
/// controller computes it and hands it in.
@immutable
class TournamentContext {
  const TournamentContext({
    required this.stackInBb,
    required this.bubbleFactor,
    required this.playersLeft,
    required this.paidPlaces,
    required this.inMoney,
  });

  /// The acting player's stack in big blinds (drives short-stack push/fold).
  final double stackInBb;

  /// ICM risk premium: 1.0 = chip-neutral, > 1 = losing costs more than winning
  /// gains, so tighten (see `Icm.bubbleFactor`).
  final double bubbleFactor;

  final int playersLeft;
  final int paidPlaces;
  final bool inMoney;

  /// Not yet in the money and within ~2× the paid places — the pressure zone.
  bool get nearBubble => !inMoney && playersLeft <= paidPlaces * 2;

  /// A neutral cash-game context (no ICM pressure) — the sentinel a non-tournament
  /// caller can pass so the wrapper is a no-op.
  static const cash = TournamentContext(
    stackInBb: 100,
    bubbleFactor: 1,
    playersLeft: 0,
    paidPlaces: 0,
    inMoney: true,
  );
}
