import 'package:monte/core/domain/engine/actions.dart';
import 'package:monte/core/domain/engine/card.dart';
import 'package:monte/core/domain/engine/deck.dart';
import 'package:monte/core/domain/engine/hand_evaluator.dart';
import 'package:monte/core/domain/engine/player.dart';

/// The streets of a Texas Hold'em hand.
enum BettingRound {
  preflop('Pre-Flop'),
  flop('Flop'),
  turn('Turn'),
  river('River'),
  showdown('Showdown'),
  handComplete('Hand Complete');

  const BettingRound(this.label);
  final String label;
}

/// The outcome for one player at showdown / hand end.
class HandResult {
  HandResult({required this.player, required this.amountWon, this.handValue});

  final Player player;
  final int amountWon;

  /// Null when the player won uncontested (everyone else folded).
  final HandValue? handValue;
}

/// A self-contained No-Limit Texas Hold'em hand engine.
///
/// The engine is *pure* and synchronous: callers drive it by inspecting
/// [currentPlayer] and calling [applyAction]. It knows nothing about UI,
/// networking, or bots — which is what lets the same engine run client-side
/// today and (re-validated) server-side later.
class PokerGame {
  PokerGame({
    required this.players,
    this.smallBlind = 5,
    this.bigBlind = 10,
    Deck? deck,
  }) : _deck = deck ?? Deck();

  final List<Player> players;
  final int smallBlind;
  final int bigBlind;
  final Deck _deck;

  /// Community cards (0, 3, 4, or 5).
  final List<Card> board = [];

  /// Human-readable event feed for the UI.
  final List<String> log = [];

  /// Index of the dealer button.
  int buttonIndex = 0;

  BettingRound round = BettingRound.preflop;

  /// Highest per-round contribution any player has made this street.
  int currentBet = 0;

  /// Minimum legal raise *increment* for the current street.
  int minRaise = 0;

  int _actorIndex = 0;
  bool _handOver = false;
  List<HandResult> results = [];

  // ---- Public query surface -------------------------------------------------

  bool get isHandOver => _handOver;

  /// Total chips in the pot across all contributions this hand.
  int get pot => players.fold(0, (sum, p) => sum + p.totalContributed);

  /// The player whose turn it is, or null when no action is pending.
  Player? get currentPlayer {
    if (_handOver || round == BettingRound.showdown) return null;
    final p = players[_actorIndex];
    return p.canAct ? p : null;
  }

  /// Chips the current player must add to call.
  int callAmount(Player p) => (currentBet - p.currentBet).clamp(0, p.stack);

  /// Whether the current player may check (nothing to call).
  bool canCheck(Player p) => callAmount(p) == 0;

  /// Smallest total "to" amount for a legal raise (capped by the stack).
  int minRaiseTo(Player p) {
    final target = currentBet + (minRaise == 0 ? bigBlind : minRaise);
    return target.clamp(0, p.currentBet + p.stack);
  }

  /// Largest total "to" amount the player can put out (their entire stack).
  int maxRaiseTo(Player p) => p.currentBet + p.stack;

  /// Replaces the undealt cards (the future board) with [dealOrder], dealt
  /// front-to-back. Used by the search determinizer to inject a sampled future
  /// onto a cloned game.
  void loadRemainingDeck(List<Card> dealOrder) =>
      _deck.loadRemaining(dealOrder);

  /// A deep copy of the entire game state, including a position-preserving copy
  /// of the deck, so the clone can be played forward without affecting this
  /// game. This is the forward model the search relies on.
  PokerGame clone() {
    final clonedPlayers = [for (final p in players) p.clone()];
    final g =
        PokerGame(
            players: clonedPlayers,
            smallBlind: smallBlind,
            bigBlind: bigBlind,
            deck: _deck.copy(),
          )
          ..board.addAll(board)
          ..log.addAll(log)
          ..buttonIndex = buttonIndex
          ..round = round
          ..currentBet = currentBet
          ..minRaise = minRaise
          .._actorIndex = _actorIndex
          .._handOver = _handOver;
    g.results = [
      for (final r in results)
        HandResult(
          player: clonedPlayers[players.indexOf(r.player)],
          amountWon: r.amountWon,
          handValue: r.handValue,
        ),
    ];
    return g;
  }

  // ---- Hand lifecycle -------------------------------------------------------

  /// Deals a new hand: rotates the button, posts blinds, deals hole cards.
  void startHand() {
    for (final p in players) {
      p.resetForHand();
    }
    board.clear();
    results = [];
    _handOver = false;
    round = BettingRound.preflop;
    log.clear();

    _deck
      ..reset()
      ..shuffle();

    final active = players.where((p) => p.stack > 0).toList();
    if (active.length < 2) {
      _handOver = true;
      log.add('Not enough funded players to start a hand.');
      return;
    }

    // Deal two hole cards to everyone with chips.
    for (var i = 0; i < 2; i++) {
      for (final p in active) {
        p.hole.add(_deck.deal());
      }
    }

    _postBlinds(active);
    log.add('${BettingRound.preflop.label}: blinds posted.');
  }

  void _postBlinds(List<Player> active) {
    // Heads-up: button posts the small blind. Otherwise SB is left of button.
    final sbOffset = active.length == 2 ? 0 : 1;
    final sbIndex = _nextOccupied(buttonIndex, sbOffset);
    final bbIndex = _nextOccupied(sbIndex, 1);

    players[sbIndex].commit(smallBlind);
    players[bbIndex].commit(bigBlind);
    currentBet = bigBlind;
    minRaise = bigBlind;

    // Blinds are forced, not voluntary acts — the big blind keeps the option.
    players[sbIndex].hasActedThisRound = false;
    players[bbIndex].hasActedThisRound = false;

    // First voluntary action is left of the big blind (heads-up: the button/SB).
    _actorIndex = _nextActorFrom(_advance(bbIndex));
  }

  /// Applies [action] for the [currentPlayer] and advances game state.
  void applyAction(GameAction action) {
    final p = currentPlayer;
    if (p == null) {
      throw StateError('No player is on action');
    }

    switch (action.type) {
      case ActionType.fold:
        p.hasFolded = true;
        p.hasActedThisRound = true;
        log.add('${p.name} folds.');
      case ActionType.check:
        if (!canCheck(p)) throw StateError('${p.name} cannot check');
        p.hasActedThisRound = true;
        log.add('${p.name} checks.');
      case ActionType.call:
        final paid = p.commit(callAmount(p));
        p.hasActedThisRound = true;
        log.add('${p.name} calls $paid.');
      case ActionType.bet:
        _applyRaiseTo(p, action.amount, isBet: true);
      case ActionType.raise:
        _applyRaiseTo(p, action.amount, isBet: false);
      case ActionType.allIn:
        _applyAllIn(p);
    }

    _afterAction();
  }

  void _applyRaiseTo(Player p, int to, {required bool isBet}) {
    final target = to.clamp(minRaiseTo(p), maxRaiseTo(p));
    final increment = target - currentBet;
    p.commit(target - p.currentBet);
    if (increment >= minRaise) minRaise = increment;
    currentBet = target;
    p.hasActedThisRound = true;
    log.add('${p.name} ${isBet ? 'bets' : 'raises to'} $target.');
  }

  void _applyAllIn(Player p) {
    final before = p.currentBet;
    p.commit(p.stack);
    final increment = p.currentBet - currentBet;
    if (p.currentBet > currentBet) {
      // An aggressive all-in; treat as a raise if it clears the bar.
      if (increment >= minRaise) minRaise = increment;
      currentBet = p.currentBet;
      log.add('${p.name} is all-in for ${p.currentBet}.');
    } else {
      log.add('${p.name} is all-in for ${p.currentBet - before} (call).');
    }
    p.hasActedThisRound = true;
  }

  void _afterAction() {
    // Everyone but one folded -> hand ends now.
    final live = players.where((p) => p.inHand).toList();
    if (live.length == 1) {
      _awardUncontested(live.first);
      return;
    }

    final next = _findNextActor();
    if (next != null) {
      _actorIndex = next;
      return;
    }
    _advanceStreet();
  }

  // ---- Street progression ---------------------------------------------------

  void _advanceStreet() {
    // If at most one player can still act, no more betting is possible: run it
    // out to the river and go to showdown.
    final canStillAct = players.where((p) => p.canAct).length;

    switch (round) {
      case BettingRound.preflop:
        _dealFlop();
        round = BettingRound.flop;
      case BettingRound.flop:
        _dealCard();
        round = BettingRound.turn;
      case BettingRound.turn:
        _dealCard();
        round = BettingRound.river;
      case BettingRound.river:
        _showdown();
        return;
      case BettingRound.showdown:
      case BettingRound.handComplete:
        return;
    }

    log.add('${round.label}: ${board.map((c) => c.code).join(' ')}');
    _startBettingRound();

    // No one can voluntarily act this street -> keep running it out.
    if (canStillAct < 2 || _findNextActor() == null) {
      _advanceStreet();
    }
  }

  void _startBettingRound() {
    for (final p in players) {
      p.resetForRound();
    }
    currentBet = 0;
    minRaise = bigBlind;
    final first = _findNextActor(from: _advance(buttonIndex), inclusive: true);
    if (first != null) _actorIndex = first;
  }

  void _dealFlop() {
    _deck.burn();
    board.addAll(_deck.dealMany(3));
  }

  void _dealCard() {
    _deck.burn();
    board.add(_deck.deal());
  }

  // ---- Resolution -----------------------------------------------------------

  void _awardUncontested(Player winner) {
    final amount = pot;
    winner.stack += amount;
    results = [HandResult(player: winner, amountWon: amount)];
    log.add('${winner.name} wins $amount uncontested.');
    _finishHand();
  }

  void _showdown() {
    round = BettingRound.showdown;

    final contenders = players.where((p) => p.inHand).toList();
    final values = <Player, HandValue>{
      for (final p in contenders)
        p: HandEvaluator.evaluate([...p.hole, ...board]),
    };

    for (final p in contenders) {
      log.add(
        '${p.name} shows ${p.hole.map((c) => c.code).join(' ')} '
        '— ${values[p]!.rank.label}',
      );
    }

    final winnings = _distributeSidePots(contenders, values);
    results = [
      for (final entry in winnings.entries)
        if (entry.value > 0)
          HandResult(
            player: entry.key,
            amountWon: entry.value,
            handValue: values[entry.key],
          ),
    ]..sort((a, b) => b.amountWon - a.amountWon);

    for (final r in results) {
      r.player.stack += r.amountWon;
      log.add(
        '${r.player.name} wins ${r.amountWon} '
        'with ${r.handValue!.rank.label}.',
      );
    }
    _finishHand();
  }

  /// Splits the pot into side pots by contribution level and awards each to the
  /// best eligible (non-folded) hand. Returns chips won per player.
  Map<Player, int> _distributeSidePots(
    List<Player> contenders,
    Map<Player, HandValue> values,
  ) {
    final winnings = {for (final p in players) p: 0};

    // Distinct contribution levels across *all* players (folded chips count
    // toward pot size but folded players can't win).
    final levels =
        players
            .map((p) => p.totalContributed)
            .where((c) => c > 0)
            .toSet()
            .toList()
          ..sort();

    var previous = 0;
    for (final level in levels) {
      final layer = level - previous;
      // Chips in this layer: one `layer` slice from every player who reached it.
      final contributors = players.where((p) => p.totalContributed >= level);
      var potChunk = layer * contributors.length;

      // Eligible winners: still in the hand and reached this level.
      final eligible = contenders
          .where((p) => p.totalContributed >= level)
          .toList();
      if (eligible.isNotEmpty) {
        HandValue best = eligible
            .map((p) => values[p]!)
            .reduce((a, b) => a > b ? a : b);
        final winners = eligible
            .where((p) => values[p]!.compareTo(best) == 0)
            .toList();

        final share = potChunk ~/ winners.length;
        var remainder = potChunk - share * winners.length;
        // Award even share, then remainder chips by seat order left of button.
        final ordered = _orderFromButton(winners);
        for (final w in ordered) {
          winnings[w] = winnings[w]! + share + (remainder-- > 0 ? 1 : 0);
        }
      }
      previous = level;
    }
    return winnings;
  }

  void _finishHand() {
    _handOver = true;
    round = BettingRound.handComplete;
    buttonIndex = _advance(buttonIndex);
  }

  // ---- Seat-order helpers ---------------------------------------------------

  int _advance(int index) => (index + 1) % players.length;

  /// The index [steps] occupied seats clockwise from [from] (skipping busted
  /// players). [from] itself is seat 0 of the count.
  int _nextOccupied(int from, int steps) {
    var idx = from;
    var moved = 0;
    while (moved < steps) {
      idx = _advance(idx);
      if (players[idx].stack > 0 || players[idx].totalContributed > 0) moved++;
    }
    return idx;
  }

  /// Finds the next index needing to act, searching clockwise.
  int? _findNextActor({int? from, bool inclusive = false}) {
    final start = from ?? _advance(_actorIndex);
    for (var i = 0; i < players.length; i++) {
      final idx = (start + i) % players.length;
      if (i == 0 && !inclusive && idx == _actorIndex) continue;
      if (_needsToAct(players[idx])) return idx;
    }
    return null;
  }

  int _nextActorFrom(int index) {
    if (_needsToAct(players[index])) return index;
    return _findNextActor(from: _advance(index), inclusive: true) ?? index;
  }

  bool _needsToAct(Player p) =>
      p.canAct && (!p.hasActedThisRound || p.currentBet < currentBet);

  /// Orders [subset] starting from the first seat left of the button.
  List<Player> _orderFromButton(List<Player> subset) {
    final result = <Player>[];
    for (var i = 1; i <= players.length; i++) {
      final p = players[(buttonIndex + i) % players.length];
      if (subset.contains(p)) result.add(p);
    }
    return result;
  }
}
