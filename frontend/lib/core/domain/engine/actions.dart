/// The kinds of action a player can take on their turn.
enum ActionType { fold, check, call, bet, raise, allIn }

/// A single betting decision.
///
/// For [ActionType.bet] and [ActionType.raise], [amount] is the *total* chips
/// the player wants their contribution for the round to reach (i.e. a raise
/// "to" amount), which keeps the engine arithmetic unambiguous.
class GameAction {
  const GameAction(this.type, {this.amount = 0});

  const GameAction.fold() : this(ActionType.fold);
  const GameAction.check() : this(ActionType.check);
  const GameAction.call() : this(ActionType.call);
  const GameAction.bet(int amount) : this(ActionType.bet, amount: amount);
  const GameAction.raise(int amount) : this(ActionType.raise, amount: amount);
  const GameAction.allIn() : this(ActionType.allIn);

  final ActionType type;
  final int amount;

  @override
  String toString() => amount > 0 ? '${type.name} to $amount' : type.name;
}
