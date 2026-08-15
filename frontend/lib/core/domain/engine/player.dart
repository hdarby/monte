import 'package:monte/core/domain/engine/card.dart';

/// A player seated at the table. Mutable: the engine updates these fields as a
/// hand progresses.
class Player {
  Player({
    required this.id,
    required this.name,
    required this.stack,
    this.isHuman = false,
  });

  final String id;

  /// Display name. Mutable so a busted bot can be replaced by a new persona
  /// without disturbing seat [id]s.
  String name;

  /// True for the local human; false for bots (later: remote players).
  final bool isHuman;

  /// Chips the player currently has behind.
  int stack;

  /// The player's two hole cards for the current hand.
  final List<Card> hole = [];

  /// Chips committed *this betting round*.
  int currentBet = 0;

  /// Total chips committed *this hand* (across all rounds); drives side pots.
  int totalContributed = 0;

  bool hasFolded = false;
  bool isAllIn = false;

  /// Whether the player has acted at least once in the current betting round.
  bool hasActedThisRound = false;

  /// The raise level of this player's most recent chip action this betting
  /// round: 0 = none (checked / posted a blind / limped), 1 = a bet/open,
  /// 2 = a 3-bet, 3+ = a 4-bet or higher. A call takes on the level it matched.
  /// Reset each round; used by the UI to escalate the bet-indicator colour.
  int betLevel = 0;

  /// Whether the chips in [currentBet] came from *calling* (vs betting/raising).
  /// Reset each round; drives the "CALL" vs "BET" label on the seat indicator.
  bool wagerIsCall = false;

  // ---- This-hand action summary (persists across rounds; reset per hand) -----
  // Used to condition an opponent's likely hand range on how they've played.

  /// Voluntarily put chips in preflop (called or raised — not just a posted
  /// blind or a free BB check). The classic VPIP signal.
  bool vpip = false;

  /// Made a voluntary bet/raise preflop (as opposed to limping/calling). Its
  /// absence is what makes super-premium holdings unlikely.
  bool raisedPreflop = false;

  /// The escalation of this player's preflop raise: 0 = none (limp/call/blind),
  /// 1 = open, 2 = 3-bet, 3+ = 4-bet or higher. A 3-bet+ collapses the range to
  /// premiums (and makes super-premiums likely rather than unlikely).
  int preflopRaiseLevel = 0;

  /// Made a bet or raise on any postflop street (aggression that polarises the
  /// range toward value + bluffs).
  bool raisedPostflop = false;

  /// Called a bet on the flop (as opposed to checking behind or raising).
  ///
  /// A float is built on exactly this: call the flop with little or nothing,
  /// then take the pot away when the aggressor gives up on the turn. Deliberately
  /// flop-specific rather than a general "last street called" — `BettingRound`
  /// lives in `game.dart`, which imports this file, and one bool is not worth an
  /// import cycle. Generalise if another street ever needs it.
  bool calledBetOnFlop = false;

  /// Eligible to act: still in the hand and has chips behind.
  bool get canAct => !hasFolded && !isAllIn && stack > 0;

  /// Still contesting the pot (not folded).
  bool get inHand => !hasFolded;

  /// A deep copy of this player's current state, used by the search forward
  /// model. Cards are immutable, so the hole list is copied by value.
  Player clone() {
    final p = Player(id: id, name: name, stack: stack, isHuman: isHuman)
      ..currentBet = currentBet
      ..totalContributed = totalContributed
      ..hasFolded = hasFolded
      ..isAllIn = isAllIn
      ..hasActedThisRound = hasActedThisRound
      ..betLevel = betLevel
      ..wagerIsCall = wagerIsCall
      ..vpip = vpip
      ..raisedPreflop = raisedPreflop
      ..preflopRaiseLevel = preflopRaiseLevel
      ..raisedPostflop = raisedPostflop
      ..calledBetOnFlop = calledBetOnFlop;
    p.hole.addAll(hole);
    return p;
  }

  /// Resets per-hand state (called when a new hand is dealt).
  void resetForHand() {
    hole.clear();
    currentBet = 0;
    totalContributed = 0;
    hasFolded = false;
    isAllIn = false;
    hasActedThisRound = false;
    betLevel = 0;
    wagerIsCall = false;
    vpip = false;
    raisedPreflop = false;
    preflopRaiseLevel = 0;
    raisedPostflop = false;
    calledBetOnFlop = false;
  }

  /// Resets per-round state (called at the start of flop/turn/river).
  void resetForRound() {
    currentBet = 0;
    hasActedThisRound = false;
    betLevel = 0;
    wagerIsCall = false;
  }

  /// Moves [amount] chips from the stack into the pot, capping at the stack
  /// (an all-in). Returns the amount actually committed.
  int commit(int amount) {
    final paid = amount.clamp(0, stack);
    stack -= paid;
    currentBet += paid;
    totalContributed += paid;
    if (stack == 0) isAllIn = true;
    return paid;
  }

  /// Posts **dead money** (e.g. a big-blind ante): chips leave the stack but do
  /// NOT join the live bet ([currentBet]) or this player's [totalContributed], so
  /// the side-pot layering treats them as dead (funding the main pot, contested
  /// by everyone) rather than a solo over-bet returned to the poster. Returns the
  /// chips actually paid (clamped to the stack).
  int postDead(int amount) {
    final paid = amount.clamp(0, stack);
    stack -= paid;
    if (stack == 0) isAllIn = true;
    return paid;
  }
}
