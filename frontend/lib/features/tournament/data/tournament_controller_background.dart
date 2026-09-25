part of 'tournament_controller.dart';

extension TournamentControllerBackground on TournamentController {
  /// Runs the tournament to a champion (bounded by [maxHands] as a safety net).
  void runToCompletion({int maxHands = 200000}) {
    while (state.status != TournamentStatus.finished &&
        _handCounter < maxHands) {
      step();
    }
  }

  /// One round: play a single hand at every playable table, record bustouts
  /// (together, worst-first, on the bubble so finish places are fair), then
  /// rebalance and advance the level clock.
  void step() {
    final handForHand = seatManager.shouldGoHandForHand(state, tableSize);
    state.status = handForHand
        ? TournamentStatus.handForHand
        : TournamentStatus.running;

    final roundBusts = <String, int>{}; // id -> chips at start of hand
    for (final table in List.of(state.tables)) {
      if (table.size < 2) continue;
      final busts = _playHand(table);
      if (handForHand) {
        roundBusts.addAll(busts);
      } else {
        // _playHand already dropped busts from their table's seats.
        _recordBusts(busts, removeFromTables: false);
        if (_maybeFinish()) {
          _reconcileChipDrift();
          return;
        }
      }
    }
    if (handForHand) {
      _recordBusts(roundBusts, removeFromTables: false);
      if (_maybeFinish()) {
        _reconcileChipDrift();
        return;
      }
    }

    _noteTableBreak(
      seatManager.rebalance(state, tableSize, protect: _featureTables()),
    );
    _reconcileChipDrift();
    _tickLevel();
    onRound?.call();
  }

  /// Marks seats newly arrived at [table] (e.g. from a break/rebalance) as
  /// "new" for exactly one hand — the one about to be dealt — clearing
  /// whoever's "new" flag was set the *previous* time this table was played.
  ///
  /// Shared by [_playHand] (background/headless tables) and
  /// `_beginHumanHand` (the human's own live table): both deal a hand for a
  /// `TournamentTable` and need the same lifecycle, and the human's own table
  /// used to never call this at all — arrivals there were silently never
  /// marked "new" because only the background path did the detection,
  /// which is exactly backwards: nobody watches a background table's seats
  /// highlight, and the human's own table is the one place this is ever
  /// actually seen.
  ///
  /// Done as a clear-then-detect pair rather than clearing the moment a
  /// player acts (the original approach): a hand plays out synchronously in
  /// one call, so clearing mid-hand added and removed the flag before any
  /// snapshot showing it as "new" was ever published — the highlight was
  /// never actually visible for a full hand.
  void _updateNewToTableTracking(TournamentTable table) {
    for (final seatId in table.playerIds) {
      if (_playerTableMap[seatId] == table.id) {
        _newToTablePlayers.remove(seatId);
      }
    }
    for (final seatId in table.playerIds) {
      final oldTable = _playerTableMap[seatId];
      if (oldTable != table.id) {
        _newToTablePlayers.add(seatId);
        _playerTableMap[seatId] = table.id;
      }
    }
  }

  /// Plays one hand at [table] and returns the players who busted (id -> their
  /// chips at the start of the hand, for worst-first place ordering). Does NOT
  /// record them — the caller decides when (immediately, or after the round on
  /// the bubble).
  ///
  /// [isBackground] when true uses faster decision heuristics to speed up
  /// simulation while maintaining personality consistency and skill ordering.
  Map<String, int> _playHand(
    TournamentTable table, {
    bool isBackground = false,
  }) {
    _handCounter++;
    _updateNewToTableTracking(table);

    final level = state.currentLevel;
    final seatIds = List<String>.of(table.playerIds);
    final enginePlayers = [for (final id in seatIds) _synced(id)];
    final game = PokerGame(
      players: enginePlayers,
      smallBlind: level.smallBlind,
      bigBlind: level.bigBlind,
      ante: level.ante,
      chipUnit: _chipUnitFor(level),
      deck: Deck(
        random: Random(seed * 131071 + table.id * 8191 + _handCounter),
      ),
    )..buttonIndex = (_button[table.id] ?? 0) % enginePlayers.length;

    final pre = {for (final p in enginePlayers) p.id: p.stack};
    game.startHand();
    if (game.isHandOver) return const {}; // not enough funded (defensive)
    // Capture the action list (only when a human's watching → recaps are on) so
    // the level's biggest pot can be replayed street by street.
    final actions = _chronicling ? <ActionRecord>[] : null;
    while (!game.isHandOver) {
      final cur = game.currentPlayer;
      if (cur == null) break;
      final street = game.round;
      final decider = _deciders[cur.id]!;
      // Every seat, background tables included, gets a real decision — the
      // fast heuristic sampling (fold/call-only, real decider only 1-in-N
      // actions) was producing visibly off-feeling play, not just faster
      // play. Background tables run through the same PokerGame engine and
      // PersonalityPolicy/ProfilePolicy deciders as the human's own table.
      final action = decider.decide(game, cur);
      game.applyAction(action);
      actions?.add(
        ActionRecord(
          playerId: cur.id,
          street: street,
          type: action.type,
          amount: action.amount,
          potAfter: game.pot,
        ),
      );
    }
    _button[table.id] = game.buttonIndex;

    // Sync stacks back to tournament chips and surface bustouts.
    final busts = <String, int>{};
    for (final p in enginePlayers) {
      state.players[p.id]!.chips = p.stack;
      if (p.stack == 0 && state.players[p.id]!.isActive) {
        busts[p.id] = pre[p.id]!;
      }
    }
    // Tilt accumulates at every table, not just the human's — a player moved to
    // your table part-way through a level should arrive in whatever state their
    // last hour put them in, not freshly calm.
    _mental.observeResults(
      seatIds: [for (final p in enginePlayers) p.id],
      bigBlind: level.bigBlind,
      profileOf: (id) => _profileBySeat[id],
      netOf: (id) => (state.players[id]?.chips ?? 0) - (pre[id] ?? 0),
      enteredPot: (id) => enginePlayers
          .firstWhere((p) => p.id == id, orElse: () => enginePlayers.first)
          .vpip,
    );
    _recorder.recordHand(
      game,
      pre: pre,
      tableId: table.id,
      busted: busts.keys.toSet(),
      levelIndex: state.levelIndex,
      averageStack: state.averageStack,
      actions: actions ?? const [],
      firedTriggers: _triggerLog.drain(),
      notables: _notablesAt(game),
    );
    // Drop the busted players from *this* table's seats directly — the busts all
    // happened here, so there's no need for the O(tables) scan that made huge
    // fields quadratic. The caller records the finish/payout with the global
    // seat-removal skipped.
    if (busts.isNotEmpty) table.playerIds.removeWhere(busts.containsKey);
    return busts;
  }

  /// The persistent engine player for [id], its stack refreshed from the live
  /// tournament chip count (so rebuys/re-entries take effect).
  Player _synced(String id) {
    final ep = _enginePlayers[id]!;
    ep.stack = state.players[id]!.chips;
    return ep;
  }

  void _recordBusts(Map<String, int> busts, {bool removeFromTables = true}) {
    if (busts.isEmpty) return;
    final ordered = busts.keys.toList()
      ..sort(
        (a, b) => busts[a]!.compareTo(busts[b]!),
      ); // fewest chips = worst place
    state.recordBustouts(ordered, removeFromTables: removeFromTables);
  }

  bool _maybeFinish() {
    if (state.playersRemaining > 1) return false;
    state.declareChampion();
    _recordCareer();
    return true;
  }

  /// Writes the finished event to the career store, once.
  ///
  /// Recorded at the champion, which includes the stretch played out headless
  /// after the human busted — so a career page reflects whole fields rather
  /// than only the events its owner survived.
  void _recordCareer() {
    final store = resultStore;
    if (store == null || _careerRecorded) return;
    _careerRecorded = true;
    final faced = _facedHuman;
    store.record(
      TournamentResult(
        timestampMs: DateTime.now().millisecondsSinceEpoch,
        structureName: state.structure.name,
        buyIn: buyIn,
        entrants: state.players.length,
        finishes: [
          for (final p in state.players.values)
            TournamentFinish(
              profileId:
                  _profileBySeat[p.id]?.id ?? (p.isHuman ? 'human' : p.id),
              name: p.name,
              place: p.finishPlace ?? 0,
              prize: p.prizeWon,
              isHuman: p.isHuman,
              facedHuman: faced.contains(p.id),
              generated: _profileBySeat[p.id]?.generated ?? false,
            ),
        ],
      ),
    );
  }

  /// Headless-only level tick (used by [step]/`runToCompletion`, tests): a
  /// nominal wall-clock slice per round, since there's no real player pace to
  /// read time from. Live play uses [_tickLevelRealtime] instead.
  void _tickLevel() {
    final before = state.currentLevel;
    switch (state.structure.clockMode) {
      case LevelClockMode.hands:
        state.handsThisLevel++;
      case LevelClockMode.minutes:
        state.clockElapsed += const Duration(minutes: 2);
    }
    if (state.maybeAdvanceLevel()) {
      _maybeColorUp(before, state.currentLevel);
      _buildRecap(before.level, before.bigBlind);
      _recorder.beginLevel(
        state.activePlayers,
      ); // snapshot the new level's starting stacks
    }
  }

  /// Live-play level tick: hands-mode still counts the player's own hands
  /// (only when [countHand], so the background loop's periodic calls don't
  /// double-count); minutes-mode reads real elapsed time since the level
  /// started, so the level advances on the real clock whether or not anyone
  /// is mid-hand — a real tournament clock doesn't pause for a distracted
  /// player, and this is what lets the background loop advance it even if
  /// the human never acts.
  void _tickLevelRealtime({required bool countHand}) {
    final before = state.currentLevel;
    switch (state.structure.clockMode) {
      case LevelClockMode.hands:
        if (countHand) state.handsThisLevel++;
      case LevelClockMode.minutes:
        if (_levelStartedAt != null) {
          state.clockElapsed = DateTime.now().difference(_levelStartedAt!);
        }
    }
    if (state.maybeAdvanceLevel()) {
      _levelStartedAt = DateTime.now();
      _maybeColorUp(before, state.currentLevel);
      _buildRecap(before.level, before.bigBlind);
      _recorder.beginLevel(
        state.activePlayers,
      ); // snapshot the new level's starting stacks
    }
  }

  /// Builds and stores the recap for the level [levelJustFinished] just closed.
  void _buildRecap(int levelJustFinished, int bigBlind) {
    if (!_chronicling) return;
    final currentChips = {for (final p in state.activePlayers) p.id: p.chips};
    final finishPlaces = <String, int>{};
    final prizes = <String, int>{};
    for (final p in state.players.values) {
      if (p.finishPlace != null) finishPlaces[p.id] = p.finishPlace!;
      if (p.prizeWon > 0) prizes[p.id] = p.prizeWon;
    }
    lastRecap = chronicle.buildRecap(
      levelJustFinished: levelJustFinished,
      playersLeft: state.playersRemaining,
      averageStack: state.averageStack,
      bigBlind: bigBlind,
      paidPlaces: state.paidPlaces,
      inMoney: state.inMoney,
      humanId: humanId!,
      currentChips: currentChips,
      finishPlaces: finishPlaces,
      prizes: prizes,
    );
  }

  /// If the new level retires a chip denomination, races off the field's odd
  /// chips into whole new-unit chips, applies the deltas, and records the
  /// event for display.
  void _maybeColorUp(BlindLevel before, BlindLevel after) {
    final oldUnit = _chipUnitFor(before);
    final newUnit = _chipUnitFor(after);
    if (newUnit <= oldUnit) return;
    if (newUnit > _displayChipUnit) _displayChipUnit = newUnit;

    // Pooled across the whole field, not per table. `ChipSet.colorUp` assumes
    // its pooled remainder is itself an exact multiple of `newUnit` — true
    // for the tournament's total (fixed at entrants × startingStack, and
    // every wager already a multiple of the *old* unit) but not necessarily
    // true for one table's subset of it. A table whose own odd-chip count
    // didn't happen to divide evenly left `colorUp`'s leftover-handling
    // branch bolting a sub-unit remainder directly onto one player's stack —
    // "keep the leftover so the total is conserved" conserved the *total*
    // at the cost of that one player's alignment to the new chip, which is
    // the bug `whole_chips_test` catches. Pooling globally is what actually
    // guarantees the assumption `colorUp` already documents.
    final allStacks = {
      for (final p in state.players.values)
        if (p.isActive) p.id: p.chips,
    };
    final deltas = allStacks.isEmpty
        ? <String, int>{}
        : chips.colorUp(allStacks, newUnit);

    final nonZero = <String, int>{};
    deltas.forEach((id, d) {
      if (d != 0) {
        state.players[id]!.chips += d;
        nonZero[id] = d;
      }
    });
    // Show only the player's own table: a thousand-runner race listing nine
    // hundred strangers gaining and losing odd chips buries the one line the
    // player came for — what happened to them and their table.
    final here = humanId == null
        ? null
        : state.tables
              .where((t) => t.playerIds.contains(humanId))
              .firstOrNull
              ?.playerIds
              .toSet();
    final shown = here == null
        ? nonZero
        : {
            for (final e in nonZero.entries)
              if (here.contains(e.key)) e.key: e.value,
          };
    lastColorUp = ColorUpEvent(
      oldUnit: oldUnit,
      newUnit: newUnit,
      deltas: shown,
    );
  }

  /// Plays one hand at every non-human table, yielding to the event loop so the
  /// UI stays responsive and can paint the progress bar. Returns true if the
  /// tournament ended during the round (caller should stop). Emits [SimProgress]
  /// as it goes, and a final "done" so the UI hides the bar.
  ///
  /// Background tables run independently with their own hand timers, paced to
  /// match the player's table speed. Respects pause/resume state and hand-for-hand
  /// rules (paused during hand-for-hand so all tables end at the same hand count).
  ///
  /// Yield cadence depends on whether a real frame yield is available
  /// ([_yieldToFrame], live play only):
  /// - **With** one: every table yields. A table's hand can now cost real
  ///   money (an MCTS-driven table at the small-field cutover is a couple
  ///   hundred ms, not the near-instant heuristic case this cadence was
  ///   tuned for), and the old `_simYieldEvery` cadence only yielded the
  ///   *first* and *last* table in a batch — everything between ran as one
  ///   uninterrupted block, up to 6 tables' worth with nothing to stop it.
  /// - **Without** one (headless/batch: `runToCompletion`, tests, benchmark
  ///   scripts) — the coarser `_simYieldEvery` cadence, since a real frame
  ///   yield isn't available to wait on anyway and yielding every table
  ///   across a large field is pure overhead nobody is watching.
  Future<bool> _simulateBackgroundTables(int humanTableId) async {
    final tables = [
      for (final t in List.of(state.tables))
        if (t.id != humanTableId && t.size >= 2) t,
    ];
    final total = tables.length;
    if (total == 0) return false; // No background tables to simulate

    final yieldEveryTable = _yieldToFrame != null;

    // Fast path: no pacing, just simulate. Hand-for-hand is enforced at the
    // tournament level (we don't advance rounds until all tables done). Pause
    // (recap dialog on screen, or the user's manual pause button) is checked
    // between tables, never mid-hand — a table always finishes whatever hand
    // it's on before the loop honours a pause.
    for (var i = 0; i < tables.length; i++) {
      await _waitWhilePaused();
      if (_tableCtrl.isClosed) return true;

      // Re-check size here, not just at the round-start snapshot above: a
      // rebalance can empty a table's seats (via a yield inside
      // _waitWhilePaused, or between this table's turn and an earlier one's
      // in the same round) after it was captured but before its turn comes
      // up — feeding an emptied table to _playHand divides by its (now zero)
      // player count and crashes.
      if (tables[i].playerIds.length < 2) continue;

      // Use fast heuristics for all background tables - maximum speed
      _recordBusts(
        _playHand(tables[i], isBackground: true),
        removeFromTables: false,
      );
      // Reconcile after every table's hand, not just at round end — a poll
      // landing mid-round (e.g. a test reading `state` between tables) could
      // otherwise observe a still-drifted total for the length of the round.
      _reconcileChipDrift();

      if (_maybeFinish()) {
        _emitSim(total, total);
        _publishTournament();
        return true;
      }

      // Yield to UI periodically so app stays responsive
      if (yieldEveryTable ||
          i % TournamentController._simYieldEvery == 0 ||
          i == tables.length - 1) {
        _emitSim(i + 1, total);
        await (_yieldToFrame?.call() ?? Future<void>.delayed(Duration.zero));
        if (_tableCtrl.isClosed) return true;
      }
    }
    _emitSim(total, total); // done → UI hides the bar
    return false;
  }

  /// Polls until nothing is asking background simulation to pause (recap
  /// dialog, hand-for-hand, the user's manual pause button, or an away-pause
  /// — see [_checkAwayPause], re-evaluated independently by
  /// [_startRealtimeTicker] every few seconds, so it clears itself the
  /// moment the player acts even while this is stuck waiting).
  Future<void> _waitWhilePaused() async {
    while (_bgSimulator.isPaused && !_tableCtrl.isClosed) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }

  void _emitSim(int done, int total) {
    if (!_simCtrl.isClosed) _simCtrl.add(SimProgress(done: done, total: total));
  }

  /// The smallest chip denomination still needed at [level] — the granularity
  /// every bet at that level must respect.
  int _chipUnitFor(BlindLevel level) => chips.smallestChip(
    smallBlind: level.smallBlind,
    bigBlind: level.bigBlind,
    ante: level.ante,
  );

  /// Chips are meant to be a closed system — the total across every player
  /// must always equal entrants × starting stack. A narrow race in table
  /// rebalancing can occasionally lose (or, in principle, gain) a handful of
  /// chips despite the fixes so far; this is the safety net, not the fix —
  /// it silently nudges a few random off-table seats to bring the total back
  /// to where it belongs, in amounts far too small to be felt by anyone
  /// (never the human, and capped well below what one hand could swing).
  void _reconcileChipDrift() {
    final expected = state.entrants * state.structure.startingStack;
    var drift =
        expected - state.players.values.fold<int>(0, (a, p) => a + p.chips);
    if (drift == 0) return;

    // Nudge in whole chip-unit increments, never literal single chips —
    // every real wager is snapped to the level's smallest denomination, so
    // any stack not aligned to it is itself a bug (see whole_chips_test).
    // Nudging by 1 "fixed" a drift that couldn't be evenly unwound in whole
    // units by instead handing out chip denominations that don't exist at
    // the table, which is a worse bug: a player showing up with (say) 8302
    // chips when the smallest chip in play is 25 or 100.
    final unit = _chipUnitFor(state.currentLevel).clamp(1, 1 << 30);
    final candidates =
        state.players.values
            .where((p) => p.isActive && !p.isHuman && p.chips >= unit)
            .toList()
          ..shuffle(_driftRng ??= Random(seed ^ 0x9e3779b9));
    if (candidates.isEmpty) return;

    var i = 0;
    // Bounded iterations: this is cosmetic bookkeeping, never a loop that
    // should be able to hang on a stubborn remainder.
    while (drift.abs() >= unit && i < candidates.length * 4) {
      final p = candidates[i % candidates.length];
      if (drift > 0) {
        p.chips += unit;
        drift -= unit;
      } else if (p.chips >= unit) {
        p.chips -= unit;
        drift += unit;
      }
      i++;
    }
    // A residual smaller than one chip unit can't be corrected without
    // handing out a denomination that doesn't exist at this level — leaving
    // it alone keeps every stack chip-aligned, which matters more than the
    // sub-chip cosmetic total. See CLAUDE.md/whole_chips_test: alignment is
    // an invariant, not a rounding nicety.
  }

  /// The human is out (busted or railing): resolve the rest of the field with
  /// real hands — nobody is watching, but everyone else's actual finish still
  /// depends on how they really play it out, not a snapshot of chip counts at
  /// the instant the human happened to bust. This used to shortcut straight to
  /// [_settleByChips] whenever more than 72 players remained (a deep bust in a
  /// large field), which meant most tournaments never actually finished being
  /// played — the rest of the field's placings were just today's stack sizes
  /// re-sorted, with nobody's actual equity or skill in it.
  ///
  /// Runs the same [step] loop [runToCompletion] does. Publishes a fresh
  /// [TournamentSnapshot] (with [_resolvingHeadless] set) and yields to the
  /// event loop after *every* round — not batched — so the screen's banner
  /// updates with the true, live player count as the field shrinks and the UI
  /// never goes a visibly long stretch without repainting. Each round is a
  /// single heuristic-only hand per table (no search), so this is cheap
  /// enough to yield this often even for a several-thousand-table field.
  /// [_settleByChips] is kept only as a backstop against a pathological field
  /// that genuinely never terminates; the hand budget is generous enough that
  /// it should not actually fire for any real tournament.
  Future<void> _finishHeadless() async {
    _liveGame = null;
    if (!_tableCtrl.isClosed) _tableCtrl.add(TableSnapshot.empty);
    _resolvingHeadless = true;
    _publishTournament(); // shows the banner immediately, before the loop
    const handBudget = 4000000;
    // Refresh the chip-leaders sort only on a round that actually busted
    // someone — a round where nobody at any table busted can't have changed
    // who's in the top 10, so re-sorting the whole remaining field for it
    // would be pure waste. This is tied to the thing the player actually
    // asked to see move (the leaderboard updating "as you remove players"),
    // not an arbitrary timer that could drift out of step with real busts.
    var playersBefore = state.playersRemaining;
    while (state.status != TournamentStatus.finished &&
        _handCounter < handBudget) {
      step();
      final bustsThisRound = playersBefore != state.playersRemaining;
      playersBefore = state.playersRemaining;
      _publishTournament(refreshChipLeaders: bustsThisRound);
      await Future<void>.delayed(Duration.zero);
      if (_tourCtrl.isClosed) return;
    }
    _resolvingHeadless = false;
    if (state.status != TournamentStatus.finished) {
      // `_settleByChips` calls `state.declareChampion()` directly rather than
      // going through `_maybeFinish()` (it isn't resolving a single hand's
      // bustouts, so there's no natural call site for that check) — which
      // means the one thing `_maybeFinish` also does, `_recordCareer()`, was
      // never getting called for a field settled this way.
      _settleByChips();
      _recordCareer();
    }
    _publishTournament();
  }

  /// Ends a still-running tournament immediately by ranking the remaining active
  /// players by chips: the shortest stacks take the worst open places and the
  /// chip leader is crowned champion. Only used as the budget backstop for a
  /// huge unobserved field (see [_finishHeadless]).
  void _settleByChips() {
    final active = state.activePlayers.toList()
      ..sort((a, b) => a.chips.compareTo(b.chips)); // worst (shortest) first
    if (active.length > 1) {
      state.recordBustouts([
        for (final p in active.take(active.length - 1)) p.id,
      ], removeFromTables: false);
    }
    state.declareChampion();
  }
}
