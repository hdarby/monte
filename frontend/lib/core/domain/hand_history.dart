import 'package:monte/core/domain/engine/actions.dart';
import 'package:monte/core/domain/engine/game.dart';

/// A single recorded action within a hand.
class ActionRecord {
  const ActionRecord({
    required this.playerId,
    required this.street,
    required this.type,
    required this.amount,
    required this.potAfter,
  });

  final String playerId;
  final BettingRound street;
  final ActionType type;

  /// For bet/raise: the total "to" amount. For call: chips paid. Else 0.
  final int amount;
  final int potAfter;

  Map<String, dynamic> toJson() => {
    'playerId': playerId,
    'street': street.name,
    'type': type.name,
    'amount': amount,
    'potAfter': potAfter,
  };
}

/// A player as they were dealt into a hand.
class HandPlayer {
  const HandPlayer({
    required this.id,
    required this.name,
    required this.startingStack,
    required this.holeCards,
    required this.isButton,
  });

  final String id;
  final String name;
  final int startingStack;
  final List<String> holeCards;
  final bool isButton;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'startingStack': startingStack,
    'holeCards': holeCards,
    'isButton': isButton,
  };
}

/// The outcome for one player who won chips.
class HandResultRecord {
  const HandResultRecord({
    required this.playerId,
    required this.amountWon,
    this.handRank,
  });

  final String playerId;
  final int amountWon;
  final String? handRank;

  Map<String, dynamic> toJson() => {
    'playerId': playerId,
    'amountWon': amountWon,
    if (handRank != null) 'handRank': handRank,
  };
}

/// A complete, parsable record of one played hand.
class HandHistory {
  const HandHistory({
    required this.handNumber,
    required this.smallBlind,
    required this.bigBlind,
    required this.players,
    required this.actions,
    required this.board,
    required this.results,
    required this.finalStacks,
  });

  final int handNumber;
  final int smallBlind;
  final int bigBlind;
  final List<HandPlayer> players;
  final List<ActionRecord> actions;
  final List<String> board;
  final List<HandResultRecord> results;

  /// Stack behind each dealt player at the end of the hand.
  final Map<String, int> finalStacks;

  /// Net chips for a player this hand (end - start), or 0 if not dealt in.
  int netFor(String playerId) {
    final player = players
        .where((p) => p.id == playerId)
        .cast<HandPlayer?>()
        .firstOrNull;
    if (player == null) return 0;
    return (finalStacks[playerId] ?? player.startingStack) -
        player.startingStack;
  }

  Map<String, dynamic> toJson() => {
    'handNumber': handNumber,
    'smallBlind': smallBlind,
    'bigBlind': bigBlind,
    'players': players.map((p) => p.toJson()).toList(),
    'actions': actions.map((a) => a.toJson()).toList(),
    'board': board,
    'results': results.map((r) => r.toJson()).toList(),
    'finalStacks': finalStacks,
  };

  /// A human-readable transcript (hole cards, action sequence per street, board,
  /// and result) — for eyeballing what actually happened in a hand.
  String toReadable() {
    final names = {for (final p in players) p.id: p.name};
    final sb = StringBuffer()
      ..writeln('Hand #$handNumber  (blinds $smallBlind/$bigBlind)');
    for (final p in players) {
      final btn = p.isButton ? ' [BTN]' : '';
      sb.writeln(
        '  ${p.name}$btn  ${p.holeCards.join(' ')}  (stack ${p.startingStack})',
      );
    }
    BettingRound? street;
    for (final a in actions) {
      if (a.street != street) {
        street = a.street;
        final b = _boardUpTo(street);
        sb.writeln('  -- ${street.label}${b.isEmpty ? '' : ' [$b]'} --');
      }
      sb.writeln('     ${names[a.playerId] ?? a.playerId} ${_describe(a)}'
          '  (pot ${a.potAfter})');
    }
    for (final r in results) {
      final rank = r.handRank != null ? ' (${r.handRank})' : '';
      sb.writeln('  => ${names[r.playerId] ?? r.playerId} '
          'wins ${r.amountWon}$rank');
    }
    return sb.toString();
  }

  String _boardUpTo(BettingRound street) => switch (street) {
    BettingRound.flop => board.take(3).join(' '),
    BettingRound.turn => board.take(4).join(' '),
    BettingRound.river => board.take(5).join(' '),
    _ => '',
  };

  static String _describe(ActionRecord a) => switch (a.type) {
    ActionType.fold => 'folds',
    ActionType.check => 'checks',
    ActionType.call => 'calls ${a.amount}',
    ActionType.bet => 'bets ${a.amount}',
    ActionType.raise => 'raises to ${a.amount}',
    ActionType.allIn => 'all-in ${a.amount}',
  };
}

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull => isEmpty ? null : first;
}
