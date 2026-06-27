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
      ..hasActedThisRound = hasActedThisRound;
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
  }

  /// Resets per-round state (called at the start of flop/turn/river).
  void resetForRound() {
    currentBet = 0;
    hasActedThisRound = false;
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
}
