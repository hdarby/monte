part of 'tournament_controller.dart';

extension TournamentControllerLive on TournamentController {
  // ---- Live play (M5): the human plays their table; others sim between hands --

  /// Begins interactive play. The human's table runs live (pausing on their
  /// turn); every other table simulates one hand between the human's hands.
  Future<void> startLive({
    Duration botDelay = const Duration(milliseconds: 300),
    Duration nextHandDelay = const Duration(seconds: 2),
  }) async {
    _botDelay = botDelay;
    _nextHandDelay = nextHandDelay;
    _loadWinDecorations();
    await _bgSimulator.initialize();
    _levelStartedAt = DateTime.now();
    _recorder.beginLevel(
      state.activePlayers,
    ); // snapshot level 1's starting stacks
    _publishTournament();
    _startRealtimeTicker();
    return _beginHumanHand();
  }

  /// Whether the live loop is paused waiting for the human to act.
  bool get awaitingHuman => _awaitingHuman;

  /// The human's live table game, or null when no hand is in progress.
  PokerGame? get liveGame => _liveGame;

  /// Applies the human's chosen action and continues the hand.
  Future<void> submitLiveAction(GameAction action) async {
    if (!_awaitingHuman || _liveGame == null) return;
    // Acting is an unambiguous "I'm back" signal — resume the user's own
    // manual pause rather than leave every other table frozen behind them
    // until they separately remember to hit the pause button again. Only
    // the manual flag: a recap/hand-for-hand/away pause is structural and
    // isn't dismissed just because a bet went in.
    if (_bgSimulator.isManuallyPaused) {
      resumeSimulation();
      _publishTournament();
    }
    // Every other `applyAction` caller (`_runLiveBots`, `_playHand`,
    // `BackgroundTableSimulator`) re-checks `currentPlayer` directly right
    // before calling it; this one trusted `_awaitingHuman` alone, with
    // nothing re-validating that the engine's actor is still who it was when
    // that flag was set. If it ever *is* stale — a UI double-submit, or a
    // still-unproven edge case around a table move — this turns a crash
    // (`StateError: No player is on action`) into a silently ignored stale
    // action instead.
    final cur = _liveGame!.currentPlayer;
    if (cur == null || cur.id != (humanId ?? 'e0')) return;
    _awaitingHuman = false;
    if (onEvalHandRecorded != null) {
      _gradeHumanDecision(_liveGame!, action);
    }
    _applyLive(_liveGame!, humanId ?? 'e0', action);
    _publishTable();
    await _runLiveBots();
  }

  /// The id of the table the human is currently seated at, or null.
  int? get _humanTableId {
    for (final t in state.tables) {
      if (t.playerIds.contains(humanId)) return t.id;
    }
    return null;
  }

  Future<void> _beginHumanHand() async {
    final id = humanId;
    if (id == null) return;
    // Human out or tournament decided → finish it off headless and publish.
    if (state.status == TournamentStatus.finished ||
        !(state.players[id]?.isActive ?? false)) {
      await _finishHeadless();
      _publishTournament();
      return;
    }
    // A background round finished mid-hand last time and deferred its
    // rebalance (see `_endHumanHand`) — this is the next safe point to run
    // it, before `_humanTableId` is even read below (a rebalance can move
    // the human to a different table).
    if (_rebalancePending) {
      _rebalancePending = false;
      _noteTableBreak(
        seatManager.rebalance(state, tableSize, protect: _featureTables()),
      );
      _reconcileChipDrift();
      _publishTournament();
    }
    _humanHandStartedAt = DateTime.now();
    final tableId = _humanTableId;
    if (tableId == null) return;
    final table = state.tables.firstWhere(
      (t) => t.id == tableId,
      orElse: () => state.tables.first,
    );
    // Marks anyone rebalanced onto the human's own table as "new" for this
    // hand — the only place this highlight is ever actually seen; see
    // _updateNewToTableTracking's doc for why the background-only version of
    // this call used to make the whole feature invisible.
    _updateNewToTableTracking(table);
    final level = state.currentLevel;
    final enginePlayers = [for (final pid in table.playerIds) _synced(pid)];
    // Marks the window rebalancing must stay out of — see _humanHandActive's
    // doc for why `_liveGame == null` doesn't actually detect this.
    _humanHandActive = true;
    _liveGame = PokerGame(
      players: enginePlayers,
      smallBlind: level.smallBlind,
      bigBlind: level.bigBlind,
      ante: level.ante,
      chipUnit: _chipUnitFor(level),
      deck: Deck(
        random: Random(seed * 131071 + tableId * 8191 + ++_handCounter),
      ),
    )..buttonIndex = (_button[tableId] ?? 0) % enginePlayers.length;
    _preChipsLive = {for (final p in enginePlayers) p.id: p.stack};
    _facedHuman.addAll(enginePlayers.map((p) => p.id));
    _liveGame!.startHand();
    // Snapshot the seats/blinds for the hand's stats record (masked cards — the
    // read model only needs actions + positions, never hole cards).
    if (statsService != null || onEvalHandRecorded != null) {
      final btn = _liveGame!.buttonIndex;
      _liveHandNumber = _handCounter;
      _livePlayers = [
        for (var i = 0; i < enginePlayers.length; i++)
          HandPlayer(
            id: enginePlayers[i].id,
            name: enginePlayers[i].name,
            startingStack: _preChipsLive[enginePlayers[i].id] ?? 0,
            holeCards: const [],
            isButton: i == btn,
            revealed: false,
          ),
      ];
      _liveActions = [];
    }
    _publishTable();
    await _runLiveBots();
  }

  /// Folds the just-finished human-table hand into the persistent opponent-stats
  /// model, keyed by each seat's stable identity. Your-table-only (per config).
  void _recordLiveHand(PokerGame game) {
    for (final p in game.players) {
      final before = _preChipsLive[p.id];
      if (before != null) _noteSwing(p.id, p.stack - before);
    }
    if (_livePlayers.isEmpty) return;
    // Full-information record first, off the unmasked engine state.
    if (onEvalHandRecorded != null) {
      onEvalHandRecorded!(_buildLiveEvalHand(game));
    }
    final svc = statsService;
    if (svc == null) {
      _livePlayers = [];
      _liveActions = [];
      _liveDecisions = [];
      return;
    }
    final level = state.currentLevel;
    final hand = HandHistory(
      handNumber: _liveHandNumber,
      smallBlind: level.smallBlind,
      bigBlind: level.bigBlind,
      players: _livePlayers,
      actions: _liveActions,
      board: [for (final c in game.board) c.code],
      results: [
        for (final r in game.results)
          HandResultRecord(playerId: r.player.id, amountWon: r.amountWon),
      ],
      finalStacks: {for (final p in game.players) p.id: p.stack},
    );
    svc.record(hand, _identityOf);
    _livePlayers = [];
    _liveActions = [];
    _liveDecisions = [];
  }

  /// The human table's hand as a full-information [EvalHand] — every seat's real
  /// cards, its personality, the level's ante and the size of the field still
  /// alive, plus the human's graded decisions.
  EvalHand _buildLiveEvalHand(PokerGame game) {
    final level = state.currentLevel;
    final n = game.players.length;
    final starting = _preChipsLive;
    final players = <EvalHandPlayer>[];
    for (final live in game.players) {
      final offset = (game.players.indexOf(live) - game.buttonIndex + n) % n;
      final profile = _profileBySeat[live.id];
      String? foldStreet;
      for (final a in _liveActions) {
        if (a.playerId == live.id && a.type == ActionType.fold) {
          foldStreet = a.street.name;
          break;
        }
      }
      players.add(
        EvalHandPlayer(
          id: live.id,
          name: live.name,
          modelId: profile?.id ?? (live.id == humanId ? 'human' : 'unknown'),
          modelLabel: profile?.name ?? live.name,
          position: positionLabel(offset, n),
          seatsFromButton: offset,
          holeCards: [for (final c in live.hole) c.code],
          startingStack: starting[live.id] ?? live.stack,
          finalStack: live.stack,
          folded: live.hasFolded,
          foldStreet: foldStreet,
          madeHand: game.board.length >= 3 && live.hole.length == 2
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
      handNumber: _liveHandNumber,
      smallBlind: level.smallBlind,
      bigBlind: level.bigBlind,
      players: players,
      actions: List.of(_liveActions),
      board: [for (final c in game.board) c.code],
      results: [
        for (final r in game.results)
          HandResultRecord(
            playerId: r.player.id,
            amountWon: r.amountWon,
            handRank: r.handValue?.rank.label,
          ),
      ],
      sessionId: _sessionId,
      timestampMs: DateTime.now().millisecondsSinceEpoch,
      ante: level.ante,
      playersRemaining: state.players.values.where((p) => p.isActive).length,
      decisions: List.of(_liveDecisions),
    );
  }

  /// Runs the coach on the spot the human faces and stores what [action] cost
  /// against the coach's own pick. Never allowed to break a hand.
  void _gradeHumanDecision(PokerGame game, GameAction action) {
    final p = game.currentPlayer;
    if (p == null || p.hole.length != 2) return;
    final live = game.players.where((x) => x.inHand && !identical(x, p));
    final eff = live.isEmpty
        ? p.stack
        : math.min(p.stack, live.map((x) => x.stack).reduce(math.max));
    try {
      final r = HandCoach.analyze(
        HandCoachInput(
          hole: p.hole,
          board: game.board,
          pot: game.pot,
          toCall: game.callAmount(p),
          heroCurrentBet: p.currentBet,
          currentBet: game.currentBet,
          effectiveStack: eff,
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
      if (r.actions.isEmpty) return;
      final best = r.actions[r.recommendedIndex.clamp(0, r.actions.length - 1)];
      final chosen = _matchCoachAction(r.actions, action) ?? best;
      final bb = game.bigBlind <= 0 ? 1 : game.bigBlind;
      _liveDecisions.add(
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
    } catch (_) {
      // Coaching telemetry must never cost the player a hand.
    }
  }

  ActionEv? _matchCoachAction(List<ActionEv> options, GameAction action) {
    switch (action.type) {
      case ActionType.fold:
        return options.where((o) => o.kind == CoachAction.fold).firstOrNull;
      case ActionType.check:
        return options.where((o) => o.kind == CoachAction.check).firstOrNull;
      case ActionType.call:
        return options.where((o) => o.kind == CoachAction.call).firstOrNull;
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

  /// Applies [action] for [actorId] at the human table, recording it for the
  /// opponent-stats replay (street captured before the engine advances it).
  void _applyLive(PokerGame game, String actorId, GameAction action) {
    final street = game.round;
    game.applyAction(action);
    if (statsService != null || onEvalHandRecorded != null) {
      _liveActions.add(
        ActionRecord(
          playerId: actorId,
          street: street,
          type: action.type,
          amount: action.amount,
          potAfter: game.pot,
        ),
      );
    }
  }

  Future<void> _runLiveBots() async {
    final game = _liveGame!;
    while (!game.isHandOver) {
      final cur = game.currentPlayer;
      if (cur == null) break;
      if (cur.id == humanId) {
        _awaitingHuman = true;
        _publishTable();
        return; // wait for submitLiveAction
      }
      // A dialog (recap, color-up) shares the same pause flag background
      // simulation already respects — without this, the human's own table
      // kept dealing and playing hands visibly behind the modal, which read
      // as broken rather than paused.
      await _waitWhilePaused();
      if (_tableCtrl.isClosed) return;
      await Future<void>.delayed(_botDelay);
      if (_tableCtrl.isClosed) return;
      // Re-validate against the live game rather than the `cur` captured
      // above: the two awaits just passed (pause wait, bot pacing delay)
      // give other async work a chance to run, and `currentPlayer` can have
      // moved on (or the hand ended) by the time we get back here — applying
      // against a stale reference is exactly what threw "No player is on
      // action" from this loop.
      final freshCur = game.currentPlayer;
      if (freshCur == null || freshCur.id != cur.id) continue;
      final decider = _deciders[cur.id]!;
      final action = decider.decide(game, cur);
      _applyLive(game, cur.id, action);
      _publishTable();
    }
    await _endHumanHand();
  }

  Future<void> _endHumanHand() async {
    final game = _liveGame!;
    final humanTableId = _humanTableId ?? 0;
    _button[humanTableId] = game.buttonIndex;
    // Snapshot the action list before _recordLiveHand clears it, for the replay.
    final liveActions = List<ActionRecord>.of(_liveActions);
    _recordLiveHand(game); // fold this table's hand into the opponent reads
    // Sync chips + record this table's bustouts.
    final busts = <String, int>{};
    for (final p in game.players) {
      state.players[p.id]!.chips = p.stack;
      if (p.stack == 0 && state.players[p.id]!.isActive) {
        busts[p.id] = _preChipsLive[p.id] ?? 0;
      }
    }
    final replay = _recorder.recordHand(
      game,
      pre: _preChipsLive,
      tableId: humanTableId,
      busted: busts.keys.toSet(),
      levelIndex: state.levelIndex,
      averageStack: state.averageStack,
      humanTable: true,
      actions: liveActions,
      firedTriggers: _triggerLog.drain(),
      notables: _notablesAt(game),
    );
    // Cached for the "previous hand" button — the player asked to see the
    // hand they just missed, not necessarily the level's single narrated
    // feature hand (which may be a different table, or never gets picked at
    // all). Un-narrated: narration enumerates outs street by street and is
    // only worth paying for if the button is actually pressed.
    _lastHandReplay = replay;
    _lastHandBigBlind = game.bigBlind;
    _lastHandFallbackSummary =
        replay == null ? _summarizeUnreplayedHand(game, liveActions) : null;
    // Drop busts from the human's table seats locally (avoids the O(tables) scan).
    if (busts.isNotEmpty) {
      final ht = state.tables.firstWhere(
        (t) => t.id == humanTableId,
        orElse: () => state.tables.first,
      );
      ht.playerIds.removeWhere(busts.containsKey);
    }
    _recordBusts(busts, removeFromTables: false);
    // This hand's results are fully settled — rebalancing is safe again from
    // here until the next _beginHumanHand deals a new one.
    _humanHandActive = false;
    // Every human hand can introduce drift on its own, not only the ones that
    // also finish the tournament or trigger a rebalance — reconciling only on
    // those left a window where a poll right after this hand (before the next
    // rebalance/finish checkpoint) could still observe an off total.
    _reconcileChipDrift();
    if (_maybeFinish()) {
      _publishTournament();
      _publishTable();
      return;
    }
    // The level clock (and therefore when blinds go up) is driven purely by
    // the *player's own* hand count in hands-mode, or real elapsed time in
    // minutes-mode — never by how many background tables have finished.
    _tickLevelRealtime(countHand: true);
    _publishTournament();

    // Start background table simulation without waiting — player table
    // continues immediately. Guarded against overlap: if the previous round
    // is still running, skip starting a new one rather than have two rounds
    // mutate `state.tables`/`state.players` concurrently — it simply catches
    // up on the next hand once the in-flight round finishes.
    //
    // Deliberately bounded to exactly one round per human hand — an earlier
    // version of this ran background simulation on a fully independent,
    // continuously-looping timer (so the field would keep moving even while
    // the player was slow to act) but that let background rounds run
    // effectively unbounded relative to the player's own pace, and a large
    // field's rebalance/bust bookkeeping did not hold up under that many
    // back-to-back rounds — chip conservation failed catastrophically (a
    // 120-runner field lost over 95% of its chips in testing). Tying it back
    // to one round per human hand is what keeps background hands playing at
    // a pace near the player's own table: it can never get more than one
    // hand ahead. The tradeoff is that a player who steps away mid-hand
    // doesn't get extra background progress in the meantime — handled
    // instead by the lightweight real-time-only timer below, which only
    // ticks the level clock and the away-pause, never touches `state.tables`.
    if (!_bgSimRunning) {
      _bgSimRunning = true;
      _bgSimFuture = _simulateBackgroundTables(humanTableId);
      _bgSimFuture!.then((finished) {
        _bgSimRunning = false;
        if (finished || _tableCtrl.isClosed) return;
        // Every round can introduce drift, not just the rounds that happen to
        // also rebalance — reconciling only on a rebalance/finish left a gap
        // where a `check('during')`-style read could observe a still-off
        // total in between. Reconcile after every round instead.
        _reconcileChipDrift();
        // Rebalance now that this round's busts are known. Guarded on
        // `_humanHandActive` (no hand in progress at all) rather than
        // `!_awaitingHuman`, since the latter is also false while bots are
        // still acting mid-hand — letting a rebalance run then was a real
        // source of chip drift. `_liveGame == null` was tried first and was
        // wrong in the other direction: it's only ever null once the human
        // has busted, so it silently blocked rebalancing (and therefore
        // table breaking) for the rest of the tournament after hand one.
        //
        // In a large field this round can take longer than the human's own
        // hand, so `_humanHandActive` is frequently already true again by the
        // time it finishes — deferred to `_rebalancePending` rather than
        // dropped; `_beginHumanHand` applies it at the next safe point
        // (before the next hand starts) instead of it just never happening.
        if (state.status == TournamentStatus.finished) return;
        if (_humanHandActive) {
          _rebalancePending = true;
          return;
        }
        _noteTableBreak(
          seatManager.rebalance(state, tableSize, protect: _featureTables()),
        );
        _reconcileChipDrift();
        _publishTournament();
      });
    }

    // Let the player see the showdown before the next hand deals in. This is
    // deliberately a separate configurable delay from _botDelay (300ms,
    // meant for pacing individual bot actions within a hand) — reusing that
    // one here meant the "pause before next hand" was over before the player
    // had even finished reading the result. Configurable (not hardcoded) so
    // tests can zero it out the same way they already zero out botDelay.
    await Future<void>.delayed(_nextHandDelay);
    if (_tableCtrl.isClosed) return;
    // Don't deal the next hand out from under a dialog (recap, color-up) —
    // same shared pause flag `_runLiveBots` now waits on for the same reason.
    await _waitWhilePaused();
    if (_tableCtrl.isClosed) return;
    await _beginHumanHand();
  }

  /// Starts the lightweight real-time timer (from [startLive]): ticks the
  /// minutes-mode level clock and the away-pause check every few seconds,
  /// independent of the human's own hand cadence, so a distracted player
  /// doesn't silently freeze the level clock — but *never* touches
  /// `state.tables`/`state.players`, unlike background simulation (which
  /// stays strictly one round per human hand; see `_endHumanHand`).
  void _startRealtimeTicker() {
    _realtimeTicker?.cancel();
    const interval = Duration(seconds: 3);
    _realtimeTicker = Timer.periodic(interval, (_) {
      if (_tableCtrl.isClosed) {
        _realtimeTicker?.cancel();
        return;
      }
      _checkAwayPause();
      // Pausing (manual, recap, hand-for-hand, or away) must stop the level
      // clock too — a real tournament director's clock stops when they call
      // pause, not just the background tables. `_tickLevelRealtime` computes
      // elapsed as `now - _levelStartedAt` fresh each call rather than
      // accumulating, so simply skipping the tick isn't enough: the very
      // next un-paused tick would jump forward by the entire paused
      // duration. Instead, push `_levelStartedAt` forward by this tick's
      // interval while paused, so elapsed real time excludes the pause.
      if (_bgSimulator.isPaused) {
        _levelStartedAt = _levelStartedAt?.add(interval);
        return;
      }
      if (state.status != TournamentStatus.finished) {
        _tickLevelRealtime(countHand: false);
      }
    });
  }

  /// How long the player's current hand can sit awaiting their action before
  /// the field auto-pauses, on the assumption they've stepped away.
  static const _awayTimeout = Duration(minutes: 5);

  /// Sets/clears the away-pause based on how long the player's current hand
  /// has been waiting on them — re-run on every poll tick inside
  /// [_waitWhilePaused] so it clears itself the moment they act, not only the
  /// next time the outer loop happens to check.
  void _checkAwayPause() {
    final startedAt = _humanHandStartedAt;
    final away =
        _awaitingHuman &&
        startedAt != null &&
        DateTime.now().difference(startedAt) > _awayTimeout;
    if (away) {
      _bgSimulator.pauseForAway();
    } else {
      _bgSimulator.resumeFromAway();
    }
  }

  /// Whether the level clock is currently frozen — manual pause, the recap
  /// dialog, hand-for-hand, or an away-timeout. This is the single source of
  /// truth `_startRealtimeTicker` itself checks before advancing the clock;
  /// surfaced so the UI's own client-side countdown extrapolation
  /// (`LevelClockBadge`) can freeze in step with it instead of ticking down
  /// on wall-clock time regardless of pause state.
  bool get isPaused => _bgSimulator.isPaused;

  /// Pause background simulation of other tables.
  void pauseSimulation() {
    _bgSimulator.pause();
  }

  /// Resume background simulation of other tables.
  void resumeSimulation() {
    _bgSimulator.resume();
  }

  /// Auto-pause while the level recap dialog is on screen — the player is
  /// reading it, so a background table shouldn't be racing through hands
  /// unseen underneath. Separate from [pauseSimulation] (the user's manual
  /// pause button) so the two don't fight over one flag.
  void pauseForRecap() {
    _bgSimulator.pauseForRecap();
  }

  /// Resume background simulation once the recap dialog closes.
  void resumeAfterRecap() {
    _bgSimulator.resumeAfterRecap();
  }
}
