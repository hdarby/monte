part of 'local_game_repository.dart';

/// Hand-history / eval-hand / coach recording, split out of
/// [LocalGameRepository] because it's the bookkeeping seam: everything here
/// turns live [PokerGame] state into the records other features consume
/// (bot-facing [HandHistory], the full-info [EvalHand] tuning record, and the
/// in-hand coach's [EvalDecision]s), rather than driving the game itself.
extension LocalGameRepositoryRecording on LocalGameRepository {
  /// Deals a fresh hand and starts a new history record. In evaluation mode
  /// stacks are topped back up so every hand is full and independent.
  void _beginHand() {
    final game = _game!;
    if (config.allBots || _evaluating) {
      for (final p in game.players) {
        p.stack = config.startingStack;
      }
    }

    game.startHand();
    _handCounter++;
    _recActions = [];
    _recPlayers = [
      for (final p in game.players)
        if (p.hole.length == 2)
          HandPlayer(
            id: p.id,
            name: p.name,
            startingStack: p.stack + p.totalContributed, // pre-blind stack
            holeCards: p.hole.map((c) => c.code).toList(),
            isButton: game.players.indexOf(p) == game.buttonIndex,
          ),
    ];

    if (game.isHandOver) _finalizeHand(); // e.g. not enough players
  }

  void _applyAndRecord(Player player, GameAction action) {
    final game = _game!;
    final street = game.round;
    final callBefore = game.callAmount(player);

    game.applyAction(action);

    final int amount;
    switch (action.type) {
      case ActionType.bet:
      case ActionType.raise:
        amount = action.amount;
      case ActionType.call:
        amount = callBefore;
      case ActionType.allIn:
        amount = player.currentBet;
      case ActionType.fold:
      case ActionType.check:
        amount = 0;
    }

    _recActions.add(
      ActionRecord(
        playerId: player.id,
        street: street,
        type: action.type,
        amount: amount,
        potAfter: game.pot,
      ),
    );

    if (game.isHandOver) _finalizeHand();
  }

  void _finalizeHand() {
    final game = _game!;
    if (_recPlayers.isEmpty) return;

    // Record only the cards that were actually exposed: the human always knows
    // their own hand, and a live (non-folded) player who reached a showdown shows
    // — mirroring the live table reveal. Everyone else is masked. Safe: no stat
    // or opponent-model logic reads holeCards (only display does).
    final showdownHappened = game.results.any((r) => r.handValue != null);

    // Full-information tuning record — built from the *unmasked* data (all hole
    // cards, positions, model per seat) before masking below. Routed only to the
    // tuning store, never to a bot or the opponent model.
    if (config.onEvalHandRecorded != null) {
      config.onEvalHandRecorded!(_buildEvalHand(game));
    }

    final exposedPlayers = [
      for (final rec in _recPlayers)
        _exposeIfShown(rec, game, showdownHappened: showdownHappened),
    ];

    final hand = HandHistory(
      handNumber: _handCounter,
      smallBlind: game.smallBlind,
      bigBlind: game.bigBlind,
      players: exposedPlayers,
      actions: _recActions,
      board: game.board.map((c) => c.code).toList(),
      results: [
        for (final r in game.results)
          HandResultRecord(
            playerId: r.player.id,
            amountWon: r.amountWon,
            handRank: r.handValue?.rank.label,
          ),
      ],
      finalStacks: {for (final p in _recPlayers) p.id: _stackOf(p.id)},
    );
    _history.add(hand);
    _opponentModel.observe(hand); // legacy in-session model (ISMCTS path)
    // Tilt is part of playing, not of measuring: an evaluation run must not
    // accumulate it, or a profile's calibrated stats drift as the sim wears on.
    if (!_evaluating) {
      _mental.observe(hand, (seatId) => _specByPlayer[seatId]?.profile);
    }
    // Persistent per-opponent reads, keyed by stable identity (profile.id /
    // 'human'), for the exploitative pros — accumulated across sessions.
    if (!_evaluating) statsService?.record(hand, _identityOf);
    // Log interactive hands for diagnosis, but never the batch-sim flood.
    if (!_evaluating) config.onHandRecorded?.call(hand);
    _recPlayers = [];
    _recActions = [];
    _recDecisions = [];
  }

  /// Runs the coach on the spot [p] is facing and stores what [action] cost
  /// against the coach's own pick.
  ///
  /// The comparison is by *label*: `ActionEv` carries the coach's own wording
  /// for each option, and matching on it keeps the chosen line and the
  /// recommended line described in the same vocabulary the in-hand panel uses,
  /// rather than inventing a second one that could drift from it.
  void _recordDecision(PokerGame game, Player p, GameAction action) {
    final live = game.players.where((x) => x.inHand && !identical(x, p));
    final effStack = live.isEmpty
        ? p.stack
        : math.min(p.stack, live.map((x) => x.stack).reduce(math.max));
    final CoachReport r;
    try {
      r = HandCoach.analyze(
        HandCoachInput(
          hole: p.hole,
          board: game.board,
          pot: game.pot,
          toCall: game.callAmount(p),
          heroCurrentBet: p.currentBet,
          currentBet: game.currentBet,
          effectiveStack: effStack,
          bigBlind: game.bigBlind,
          street: game.round,
          raiseCount: game.raiseCountThisRound,
          opponents: live.length,
          opponentLabels: [for (final x in live) x.name],
          canCheck: game.canCheck(p),
          canRaise: p.stack > game.callAmount(p),
          minRaiseTo: game.minRaiseTo(p),
          maxRaiseTo: game.maxRaiseTo(p),
        ),
        analysisAvailable: true,
      );
    } catch (_) {
      return; // never let coaching telemetry break a hand
    }
    if (r.actions.isEmpty) return;
    final best = r.actions[r.recommendedIndex.clamp(0, r.actions.length - 1)];
    final chosen = _matchAction(r.actions, action) ?? best;
    final bb = game.bigBlind <= 0 ? 1 : game.bigBlind;
    _recDecisions.add(
      EvalDecision(
        playerId: p.id,
        street: game.round.name,
        actualType: action.type.name,
        actualAmount: action.amount,
        potBb: game.pot / bb,
        toCallBb: game.callAmount(p) / bb,
        spr: r.spr,
        equity: r.equity,
        potOdds: r.potOdds,
        chosenLabel: chosen.label,
        // HandCoach returns EV in **chips**. EvalDecision is documented in big
        // blinds, and at tournament stacks the difference is not cosmetic: a
        // session came back reporting 352,111bb of EV given up.
        chosenEv: chosen.ev / bb,
        bestLabel: best.label,
        bestEv: best.ev / bb,
      ),
    );
  }

  /// The coach option corresponding to [action], or null if none lines up.
  /// A bet or raise is matched to the sized option nearest the amount chosen.
  ActionEv? _matchAction(List<ActionEv> options, GameAction action) {
    bool isKind(ActionEv o, CoachAction k) => o.kind == k;
    switch (action.type) {
      case ActionType.fold:
        return options.where((o) => isKind(o, CoachAction.fold)).firstOrNull;
      case ActionType.check:
        return options.where((o) => isKind(o, CoachAction.check)).firstOrNull;
      case ActionType.call:
        return options.where((o) => isKind(o, CoachAction.call)).firstOrNull;
      case ActionType.bet:
      case ActionType.raise:
      case ActionType.allIn:
        final sized = options.where((o) => o.toAmount != null).toList();
        if (sized.isEmpty) return null;
        sized.sort(
          (a, b) => (a.toAmount! - action.amount).abs().compareTo(
            (b.toAmount! - action.amount).abs(),
          ),
        );
        return sized.first;
    }
  }

  int _stackOf(String id) => _game!.players.firstWhere((p) => p.id == id).stack;

  /// Returns [rec] unchanged if its cards were exposed (human, or a non-folded
  /// player at a showdown), otherwise a masked copy (no cards, `revealed: false`).
  HandPlayer _exposeIfShown(
    HandPlayer rec,
    PokerGame game, {
    required bool showdownHappened,
  }) {
    final live = game.players.firstWhere((p) => p.id == rec.id);
    final exposed = live.isHuman || (showdownHappened && live.inHand);
    if (exposed) return rec;
    return HandPlayer(
      id: rec.id,
      name: rec.name,
      startingStack: rec.startingStack,
      holeCards: const [],
      isButton: rec.isButton,
      revealed: false,
    );
  }

  /// Builds the full-information [EvalHand] for the just-finished hand: every
  /// dealt player with their real hole cards, position, model, and (when a board
  /// ran out) made-hand rank. Reads only the live [game] + this hand's records —
  /// it does not touch the masked history or opponent model.
  EvalHand _buildEvalHand(PokerGame game) {
    final n = game.players.length;
    final board = game.board.map((c) => c.code).toList();
    final startingStackOf = {
      for (final r in _recPlayers) r.id: r.startingStack,
    };

    final players = <EvalHandPlayer>[];
    for (final live in game.players) {
      if (!startingStackOf.containsKey(live.id)) continue; // not dealt in
      final offset = (game.players.indexOf(live) - game.buttonIndex + n) % n;
      final spec = _specByPlayer[live.id];
      final profile = spec?.profile;
      String? foldStreet;
      for (final a in _recActions) {
        if (a.playerId == live.id && a.type == ActionType.fold) {
          foldStreet = a.street.name;
          break;
        }
      }
      players.add(
        EvalHandPlayer(
          id: live.id,
          name: live.name,
          modelId:
              profile?.id ??
              (spec != null
                  ? '${spec.brain.name}:${spec.style.name}'
                  : 'human'),
          modelLabel: spec?.label ?? live.name,
          position: positionLabel(offset, n),
          seatsFromButton: offset,
          holeCards: live.hole.map((c) => c.code).toList(),
          startingStack: startingStackOf[live.id]!,
          finalStack: live.stack,
          folded: live.hasFolded,
          foldStreet: foldStreet,
          madeHand: game.board.length >= 3
              ? HandEvaluator.evaluate([...live.hole, ...game.board]).rank.label
              : null,
          skill: profile?.skill,
          vpipTarget: profile?.strategicBaseline.vpipTarget,
          pfrTarget: profile?.strategicBaseline.pfrTarget,
          threeBetTarget: profile?.strategicBaseline.threeBetFrequency,
        ),
      );
    }

    return EvalHand(
      handNumber: _handCounter,
      smallBlind: game.smallBlind,
      bigBlind: game.bigBlind,
      sessionId: _sessionId,
      timestampMs: DateTime.now().millisecondsSinceEpoch,
      ante: game.ante,
      playersRemaining: config.playersRemaining,
      decisions: List.of(_recDecisions),
      players: players,
      actions: List.of(_recActions),
      board: board,
      results: [
        for (final r in game.results)
          HandResultRecord(
            playerId: r.player.id,
            amountWon: r.amountWon,
            handRank: r.handValue?.rank.label,
          ),
      ],
    );
  }
}
