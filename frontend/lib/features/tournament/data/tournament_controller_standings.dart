part of 'tournament_controller.dart';

/// Kept out of the rolling window so a lone big pot doesn't count as a heater —
/// see [_TournamentControllerStandings._liveReads].
const _rushWindow = 18;

extension TournamentControllerStandings on TournamentController {
  /// The two-way read on a seat for the HUD, or null when untracked.
  SeatRead? readForSeat(String seatId) {
    final svc = statsService;
    if (svc == null) return null;
    final id = _identityOf(seatId);
    if (id == null) return null;
    // Tracked seats always show a card (a "building a read" state before the
    // baseline), so the model is visibly watching from the first hand.
    final mine = PlayerRead.of(svc.book.read(id) ?? PlayerStats());
    PlayerRead? ofMe;
    final observer = _profileBySeat[seatId];
    if (observer != null && id != PlayerStatsBook.humanIdentity) {
      // This opponent's own impression of the human — only the hands it saw.
      final me = svc.book.read(PlayerStatsBook.meKey(id)) ?? PlayerStats();
      ofMe = PlayerRead.perceivedBy(me, observer);
    }
    return SeatRead(mine: mine, ofMe: ofMe, live: _liveReads(seatId, ofMe));
  }

  /// Reads that come from the state of this session rather than from history.
  ///
  /// Tilt lives in [MentalTable] and had never left the domain — the bots have
  /// been steaming at each other invisibly. A heater is table image rather than
  /// strategy, but it is what a real player notices first. And the last one is
  /// the read worth having: an opponent who both *tracks* opponents and has an
  /// established book on you is the one beating you in specific spots.
  List<LiveRead> _liveReads(String seatId, PlayerRead? ofMe) {
    final out = <LiveRead>[];

    // Stack geometry first: whether a call can end your tournament is the fact
    // that reframes every other read on the card.
    final them = state.players[seatId];
    final bb = state.currentLevel.bigBlind;
    if (them != null && bb > 0) {
      final depth = them.chips / bb;
      if (depth <= 12) {
        // Below roughly a dozen big blinds their game collapses to jam-or-fold
        // (see PushFoldChart) and should be played against completely
        // differently. That was modelled on their side and invisible on yours.
        out.add(
          LiveRead('short — jamming ${depth.round()}bb', LiveReadKind.stack),
        );
      }
    }

    final mood = _mental.stateFor(seatId);
    if (mood != null && mood.isTilted) {
      out.add(
        LiveRead(
          mood.tiltPressure >= 0.7 ? 'steaming' : 'rattled',
          LiveReadKind.tilt,
        ),
      );
    }
    final rush = _recentNet[seatId] ?? 0;
    if (bb > 0 && rush >= 40 * bb) {
      out.add(const LiveRead('running hot', LiveReadKind.rush));
    } else if (bb > 0 && rush <= -40 * bb) {
      out.add(const LiveRead('taking a beating', LiveReadKind.rush));
    }
    // Three gates, because the first version had one and it was useless.
    //
    // The threshold was 0.6, which is exactly `_p`'s default for `oppRead` —
    // so 210 of 218 pros cleared it and the chip appeared on every seat at the
    // table. A warning that is always on is not a warning. It has to be above
    // the default to mean anything, and 0.85 leaves 26 profiles: about one per
    // full table, which is what "this particular player has your number" should
    // feel like.
    //
    // And watching is not the same as having found something. The read must
    // also be confident *and* have produced concrete tendencies — tags are only
    // emitted once there is a real sample behind them — so the chip means they
    // have identified something specific about you, not merely that they were
    // present.
    final observer = _profileBySeat[seatId];
    if (observer != null && ofMe != null && !ofMe.thin) {
      final tracks = observer.behavioralModifiers.weightOnOpponentHistory;
      if (tracks >= 0.85 && ofMe.confidence >= 0.7 && ofMe.tags.isNotEmpty) {
        out.add(const LiveRead('has your number', LiveReadKind.danger));
      }
    }
    return out;
  }

  void _noteSwing(String seatId, int delta) {
    final h = _recentHands.putIfAbsent(seatId, () => <int>[])..add(delta);
    if (h.length > _rushWindow) h.removeAt(0);
    _recentNet[seatId] = h.fold(0, (a, b) => a + b);
  }

  void _publishTable() {
    if (_liveGame == null || _tableCtrl.isClosed) return;
    // Anchor the human at the bottom-centre seat wherever they've been reseated.
    _tableCtrl.add(
      projectTableSnapshot(
        _liveGame!,
        frontPlayerId: humanId,
        // Colour each seat pro vs recreational, matching the standings panel.
        seatProfiles: _profileBySeat,
        // Draw stacks in the denominations actually in play at this level —
        // never redraw a chip that's already been raced off by a color-up.
        denominations: chips.denominations,
        chipUnit: _displayChipUnit,
        // Highlight players new to this table for their first hand.
        newToTablePlayers: _newToTablePlayers,
      ),
    );
  }

  /// Tables holding two or more recognisable players. A tournament breaks
  /// somebody else's table before it breaks the one with the cameras on it.
  Set<int> _featureTables() => {
    for (final t in state.tables)
      if (t.playerIds
              .where((id) => _profileBySeat[id]?.generated == false)
              .length >=
          2)
        t.id,
  };

  /// The single table a broadcast would actually put on screen: whichever
  /// [_featureTables] candidate has the most recognisable players seated,
  /// ties broken by the lower table id so the pick doesn't flicker between
  /// two equally-loaded tables from one publish to the next. Null once
  /// nothing qualifies (no table has two-plus named personalities).
  int? get _nominatedFeatureTableId {
    int? best;
    var bestCount = 0;
    for (final id in _featureTables()) {
      final t = state.tables.firstWhere((t) => t.id == id);
      final count = t.playerIds
          .where((pid) => _profileBySeat[pid]?.generated == false)
          .length;
      if (best == null || count > bestCount || (count == bestCount && id < best)) {
        best = id;
        bestCount = count;
      }
    }
    return best;
  }

  /// The named personalities dealt into [game] — the ones a viewer would
  /// recognise, as opposed to the anonymous profiles that fill out a field.
  ///
  /// `FieldBuilder` marks auto-filled seats `generated`, so the flag is already
  /// there; nothing had ever asked it a question.
  List<String> _notablesAt(PokerGame game) => [
    for (final p in game.players)
      if (_profileBySeat[p.id]?.generated == false) _profileBySeat[p.id]!.name,
  ];

  /// Notes only the seat changes that affect the **human's** table.
  ///
  /// This used to announce whichever table broke anywhere in the field, which
  /// in a large event is a stream of notices about strangers being moved
  /// between tables the player will never see. Two things actually matter: being
  /// moved yourself, and somebody new sitting down opposite you.
  void _noteTableBreak(List<SeatMove> moves) {
    if (moves.isEmpty || humanId == null) return;
    final me = humanId!;

    // Were *we* moved? Then our table broke (or we were balanced away).
    final mine = moves.where((m) => m.playerId == me).firstOrNull;
    if (mine != null) {
      final together = moves.where((m) => m.fromTable == mine.fromTable);
      _lastTableBreak = TableBreakDisplay(
        tableNumber: mine.fromTable + 1,
        broke: true,
        moves: [
          for (final m in together)
            TableBreakMove(
              name: state.players[m.playerId]?.name ?? m.playerId,
              isHuman: m.playerId == me,
              toTable: m.toTable + 1,
              toSeat: m.toSeat,
            ),
        ],
      );
      return;
    }

    // Otherwise: did anyone arrive at our table?
    final here = state.tables
        .where((t) => t.playerIds.contains(me))
        .firstOrNull
        ?.id;
    if (here == null) return;
    final arrived = [
      for (final m in moves)
        if (m.toTable == here) state.players[m.playerId]?.name ?? m.playerId,
    ];
    if (arrived.isEmpty) return;
    _lastTableBreak = TableBreakDisplay(
      tableNumber: here + 1,
      broke: false,
      arrivals: arrived,
      moves: const [],
    );
  }

  void _publishTournament({bool refreshChipLeaders = true}) {
    if (humanId == null || _tourCtrl.isClosed) return;
    // Always publish. This used to be throttled to every 10 hands to reduce
    // standings-panel jitter, but that throttled the *whole* snapshot — chips,
    // level, and the human's own live place along with it, so those numbers
    // could lag up to 9 hands behind reality. The standings panel now windows
    // itself to the rows around the human instead (see
    // TournamentController.standings), which is what was actually causing the
    // visible jitter/cost — so the numbers here can stay exact.
    //
    // The chip-leaders sort is the one thing here that *is* throttled (see
    // [_finishHeadless]): it's a full sort of every remaining active player,
    // which for a several-thousand-runner field is real cost to pay every
    // single round just to refresh a top-10 list nobody can perceive
    // hand-by-hand anyway.
    if (_resolvingHeadless && refreshChipLeaders) {
      _cachedTopChipLeaders = _topChipLeaders(10);
    }
    _tourCtrl.add(
      TournamentSnapshot.of(
        state,
        humanId!,
        chipSet: chips,
        colorUp: lastColorUp,
        recap: lastRecap,
        tableBreak: _lastTableBreak,
        resolvingRestOfField: _resolvingHeadless,
        topChipLeaders: _resolvingHeadless ? _cachedTopChipLeaders : const [],
        atFeatureTable: _humanTableId != null &&
            _humanTableId == _nominatedFeatureTableId,
      ),
    );
    lastColorUp = null; // one-shot: only the tick it happened carries it
    lastRecap = null;
    _lastTableBreak = null;
  }

  /// The standings around the human, built on demand: active players ranked
  /// by chips take places 1..K, then busted players follow in finish order
  /// (best finish first) — but only [radius] rows either side of the human's
  /// own place are actually materialised. A large field is thousands of
  /// players deep; nobody reads past their own neighbourhood on a semi-static
  /// side panel, and building/sorting the *entire* field into row objects on
  /// every redraw was real, avoidable cost sitting right next to background
  /// simulation on the same event loop. Background simulation is paused for
  /// the duration of this call so a table can't mutate a stack mid-read.
  List<StandingRow> standings({int radius = 60}) {
    _bgSimulator.pauseForRender();
    try {
      final active = state.activePlayers.toList()
        ..sort((a, b) => b.chips.compareTo(a.chips));
      final busted = state.players.values.where((p) => !p.isActive).toList()
        ..sort(
          (a, b) =>
              (a.finishPlace ?? 1 << 30).compareTo(b.finishPlace ?? 1 << 30),
        );

      final total = active.length + busted.length;
      if (total == 0) return const [];

      TournamentPlayer itemAt(int i) =>
          i < active.length ? active[i] : busted[i - active.length];
      int placeAt(int i) => i < active.length
          ? i + 1
          : (busted[i - active.length].finishPlace ?? i + 1);
      bool bustedAt(int i) => i >= active.length;

      var humanIndex = active.indexWhere((p) => p.isHuman);
      if (humanIndex < 0) {
        final bustedIndex = busted.indexWhere((p) => p.isHuman);
        humanIndex = bustedIndex < 0 ? 0 : active.length + bustedIndex;
      }

      final start = (humanIndex - radius).clamp(0, total - 1);
      final end = (humanIndex + radius).clamp(0, total - 1);

      final rows = <StandingRow>[];
      for (var i = start; i <= end; i++) {
        final p = itemAt(i);
        final isBusted = bustedAt(i);
        final deco = _winDecorations[_identityOf(p.id) ??
            (p.isHuman ? 'human' : p.id)];
        rows.add(
          StandingRow(
            place: placeAt(i),
            name: p.name,
            isHuman: p.isHuman,
            chips: isBusted ? 0 : p.chips,
            busted: isBusted,
            prize: isBusted ? p.prizeWon : 0,
            kind: _kindOf(p),
            generated: _generatedOf(p),
            bracelets: deco?.bracelets ?? 0,
            rings: deco?.rings ?? 0,
          ),
        );
      }
      return rows;
    } finally {
      _bgSimulator.resumeAfterRender();
    }
  }

  StandingKind _kindOf(TournamentPlayer p) {
    if (p.isHuman) return StandingKind.human;
    final prof = _profileBySeat[p.id];
    return (prof != null && isAmateurProfile(prof))
        ? StandingKind.amateur
        : StandingKind.pro;
  }

  bool _generatedOf(TournamentPlayer p) =>
      _profileBySeat[p.id]?.generated ?? false;

  /// The top [n] active players by chip count, for the "running out the
  /// field" banner — cheap enough to compute every round (unlike [standings],
  /// this skips the busted-players windowing entirely) but still only called
  /// while [_resolvingHeadless], since nobody else needs it.
  List<StandingRow> _topChipLeaders(int n) {
    final active = state.activePlayers.toList()
      ..sort((a, b) => b.chips.compareTo(a.chips));
    return [
      for (var i = 0; i < active.length && i < n; i++)
        StandingRow(
          place: i + 1,
          name: active[i].name,
          isHuman: active[i].isHuman,
          chips: active[i].chips,
          busted: false,
          prize: 0,
          kind: _kindOf(active[i]),
          generated: _generatedOf(active[i]),
        ),
    ];
  }
}
