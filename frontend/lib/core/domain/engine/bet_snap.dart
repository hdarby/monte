/// Rounds a bot's bet/raise to a human-style amount for the stake being played.
///
/// People don't bet 37 or 43 — they bet in round denominations that grow with the
/// pot: at 5/10 that's 25/30/50/75/100; at 25/50 it's 125/150/250. This snaps a
/// total "to" amount to the nearest such denomination. It's pure denomination
/// math — callers still clamp the result to `[minRaiseTo, maxRaiseTo]`, so a snap
/// can never produce an illegal amount.
int snapBet(int toAmount, {required int smallBlind, required int bigBlind}) {
  if (toAmount <= bigBlind || bigBlind <= 0) return toAmount;

  final unit = smallBlind > 0 ? smallBlind : bigBlind;
  // Denominations a human reaches for, coarsening as the bet grows.
  final steps = <int>[
    unit,
    bigBlind,
    2 * bigBlind,
    5 * bigBlind,
    10 * bigBlind,
    25 * bigBlind,
    50 * bigBlind,
    100 * bigBlind,
  ];

  // Pick the coarsest step that still leaves ~8+ increments in the bet, so small
  // bets snap finely and big bets snap in big round chunks.
  var step = unit;
  for (final s in steps) {
    if (s <= toAmount / 8) {
      step = s;
    } else {
      break;
    }
  }

  final snapped = (toAmount / step).round() * step;
  return snapped < unit ? unit : snapped;
}
