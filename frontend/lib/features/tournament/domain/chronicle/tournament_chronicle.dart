import 'package:monte/core/domain/engine/hand_evaluator.dart';
import 'package:monte/core/util/format.dart';
import 'package:monte/features/tournament/domain/chronicle/chronicle_grammar.dart';
import 'package:monte/features/tournament/domain/chronicle/hand_digest.dart';
import 'package:monte/features/tournament/domain/chronicle/hand_narrator.dart';
import 'package:monte/features/tournament/domain/chronicle/hand_replay.dart';
import 'package:monte/features/tournament/domain/chronicle/leaderboard_storylines.dart';
import 'package:monte/features/tournament/domain/chronicle/level_recap.dart';
import 'package:monte/features/tournament/domain/chronicle/player_meta.dart';
import 'package:monte/features/tournament/domain/tournament_snapshot.dart'
    show StandingKind;

/// Accumulates real results across every table and turns each completed level
/// into a [LevelRecap]. Pure and deterministic — fed [HandDigest]s by the
/// controller, snapshotted at level starts, and asked to build a recap at level
/// ends. Flavor lines are only ever emitted when the underlying counts justify
/// them, so the prose stays grounded in what actually happened.
class TournamentChronicle {
  final Map<String, PlayerMeta> _meta = {};

  /// The biggest handful of pots this level, best-first, with what was shown.
  final List<NotablePot> _potsThisLevel = [];

  /// The level's feature hand, kept in full for a replay.
  HandReplay? _biggestReplay;

  /// The digest the feature hand came from, for the table it was played at.
  HandDigest? _biggestDigest;

  /// The feature hand's score (see [_featureScore]), so a later hand can beat it.
  double _bestFeatureScore = 0;

  /// The ids active at the start of the current level — anyone here who isn't
  /// active at level's end busted this level.
  Set<String> _levelStartIds = {};

  /// The overall chip leader recorded at the end of the previous level, so the
  /// next recap can follow up on how they're faring.
  String? _prevLeaderId;
  String? _prevLeaderName;
  int _prevLeaderLevel = 0;

  /// The big blind of the level being recapped, for expressing stacks in BBs.
  int _bb = 0;

  PlayerMeta _of(String id, String name, StandingKind kind) =>
      _meta.putIfAbsent(id, () => PlayerMeta(name, kind))
        ..name = name
        ..kind = kind;

  /// Marks the start of a level: snapshots every active player's chips (to
  /// measure the level's gains/losses and detect who busts), records which are
  /// real personalities, and clears the per-level tallies.
  void beginLevel(Map<String, int> activeChips, Map<String, String> names,
      Map<String, StandingKind> kinds, Set<String> personalities) {
    _potsThisLevel.clear();
    _biggestReplay = null;
    _biggestDigest = null;
    _bestFeatureScore = 0;
    _levelStartIds = activeChips.keys.toSet();
    for (final e in activeChips.entries) {
      final m = _of(e.key, names[e.key] ?? e.key, kinds[e.key] ?? StandingKind.pro);
      // The human is always a character in their own tournament.
      m.isPersonality = personalities.contains(e.key) || m.isHuman;
      m.levelStartChips = e.value;
      m.handsWonL = 0;
      m.showdownsL = 0;
      m.knockoutsL = 0;
      m.luckyWinsL = 0;
      m.badBeatsL = 0;
      m.bigLossesL = 0;
      m.biggestPotL = 0;
      m.biggestPotHandL = null;
      m.handsDealtL = 0;
      m.vpipL = 0;
      m.rfiL = 0;
      m.stealChancesL = 0;
      m.stealAttemptsL = 0;
    }
  }

  /// Folds one completed hand into the tally. [avgStack] scales the "big pot"
  /// bar so notability is relative to the current stacks, not an absolute.
  void record(HandDigest d, {required int avgStack}) {
    final winners = d.winners.toSet();
    final big = d.pot >= _bigPotBar(avgStack);

    // Human preflop play-style — every hand at the human's table is a hand
    // they were dealt into, whether or not they ever acted (a walk is still a
    // hand seen).
    if (d.humanTable) {
      final humanId = _humanIdOrNull();
      final m = humanId == null ? null : _meta[humanId];
      if (m != null) {
        m.handsDealtL++;
        if (d.vpipHuman) m.vpipL++;
        if (d.rfiHuman) m.rfiL++;
        if (d.stealChanceHuman) m.stealChancesL++;
        if (d.stealAttemptHuman) m.stealAttemptsL++;
      }
    }

    // Per-player showdown bookkeeping.
    ShowdownEntry? aheadLoser;
    ShowdownEntry? topWinner;
    for (final s in d.showdown) {
      final m = _meta[s.id];
      if (m != null) m.showdownsL++;
      if (winners.contains(s.id)) {
        if (topWinner == null || s.net > topWinner.net) topWinner = s;
      } else if (s.wentAllIn && s.aheadOnFlop) {
        aheadLoser = s;
      }
      // A strong made hand that lost a big pot: a cooler.
      if (big && !winners.contains(s.id) && _isStrong(s.rank)) {
        _meta[s.id]?.bigLossesL++;
      }
    }

    for (final id in winners) {
      final m = _meta[id];
      if (m == null) continue;
      m.handsWonL++;
      final self = d.showdown.where((s) => s.id == id).firstOrNull;
      if (self != null && self.net > m.biggestPotL) {
        m.biggestPotL = self.net;
        m.biggestPotHandL = self.rank?.label;
      }
    }

    // Suck-out / bad-beat: the winner was behind on the flop, an all-in loser
    // was ahead. Both facts come straight from the real cards + runout.
    if (topWinner != null && aheadLoser != null && !topWinner.aheadOnFlop) {
      _meta[topWinner.id]?.luckyWinsL++;
      _meta[aheadLoser.id]?.badBeatsL++;
    }

    // Knockout credit to the biggest winner of a hand that eliminated someone.
    if (d.busted.isNotEmpty && topWinner != null) {
      final m = _meta[topWinner.id];
      if (m != null) {
        m.knockoutsL += d.busted.length;
        m.knockouts += d.busted.length;
      }
    }

    // Keep the level's biggest contested pots (with the two headline hands).
    if (big && d.showdown.length >= 2) {
      _potsThisLevel.add(_toNotablePot(d));
      _potsThisLevel.sort((a, b) => b.pot.compareTo(a.pot));
      if (_potsThisLevel.length > 4) _potsThisLevel.removeLast();
    }

    // Retain one hand in full, for the level's replay.
    //
    // A showdown is the usual requirement — you cannot narrate cards nobody
    // turned over — but a hand containing a **signature move** qualifies without
    // one. The most characterful hands end precisely *because* nobody showed:
    // a float that works takes the pot down uncontested, and requiring a
    // showdown filtered every one of them out. Measured over a level, moves
    // fired eight times and not one hand was even eligible.
    final hasMove = d.replay?.streets.any((s) => s.triggers.isNotEmpty) ?? false;
    if (d.replay != null && (d.showdown.length >= 2 || hasMove)) {
      final score = _featureScore(d, _humanIdOrNull());
      if (_biggestReplay == null || score > _bestFeatureScore) {
        _biggestReplay = d.replay;
        _biggestDigest = d;
        _bestFeatureScore = score;
      }
    }
  }

  /// How much a hand deserves the level's one replay slot — how *interesting*
  /// it is, not merely how many chips were attached to it.
  ///
  /// Only one hand per level is ever narrated, and picking it on pot size alone
  /// throws away most of what is worth watching. Measured over a level of 27
  /// runners, signature moves fired three times and not one landed in the
  /// biggest pot, so a trap or a float was essentially never shown. A bad beat,
  /// a knockout, a cooler and a four-way showdown are all more worth a minute of
  /// someone's attention than a slightly larger routine pot.
  ///
  /// Pot stays the multiplicative **base**, so a trivial pot can never win the
  /// slot no matter how many flags it sets: with every bonus at once a hand
  /// still has to be roughly a third the size of the biggest to beat it. Nothing
  /// in the recap claims the feature hand *is* the biggest pot of the level.
  /// The human's seat id, if one of the tracked players is the human.
  String? _humanIdOrNull() {
    for (final e in _meta.entries) {
      if (e.value.isHuman) return e.key;
    }
    return null;
  }

  static double _featureScore(HandDigest d, String? humanId) {
    final r = d.replay;
    if (r == null) return 0;

    // What makes this hand worth a minute of someone's attention, over and
    // above its size.
    var interest = 0.0;

    // A signature move is the whole reason the personalities have character;
    // seeing one is the point of having authored it. Was 0.25 — measured
    // against a real level, that left a hand with a genuine, named move still
    // needing to be roughly a third the size of the biggest pot to win the
    // slot, so moves essentially never got shown even after being correctly
    // wired and templated. 0.6 is still capped (at 2 moves) and pot is still
    // the multiplicative base, so a trivial pot cannot win on flags alone —
    // but a real move now meaningfully competes rather than barely registering.
    final moves =
        r.streets.fold<int>(0, (a, s) => a + s.triggers.length).clamp(0, 2);
    interest += 0.6 * moves;

    // The hand everyone in the room talks about afterwards.
    if (r.suckout) interest += 0.60;
    // Somebody's tournament ended here.
    if (d.busted.isNotEmpty) interest += 0.40;
    // Stacks in the middle.
    if (r.allIn) interest += 0.35;
    // A cooler: two players both turned up a real hand.
    if (r.winnerRank.index >= HandRank.twoPair.index &&
        r.loserRank.index >= HandRank.twoPair.index) {
      interest += 0.30;
    }
    // It went the distance, and not heads-up.
    if (d.showdown.length >= 3) interest += 0.25;
    // The player was sitting at the table for it.
    if (d.humanTable) interest += 0.10;

    // The feature table: two or more named personalities in the same game.
    // This is the table a broadcast points its cameras at, and the reason is
    // not the pot size — it is that you know who these people are. A hand
    // between two strangers and a hand between two players you have watched all
    // tournament are not the same hand.
    final notable = d.notables.length;
    if (notable >= 2) interest += 0.30 + 0.15 * (notable - 2).clamp(0, 4);

    // A hand the human actually contested **amplifies** whatever already made
    // it interesting, rather than adding a bonus of its own. Getting your own
    // play analysed is the most useful thing the recap does — but only when
    // there was something to analyse. A pot you happened to be in where nothing
    // happened is still a boring hand, and multiplying zero leaves it there.
    // Keyed on the replay roster (everyone who saw the flop), so folding
    // preflop does not count as playing it.
    if (humanId != null && r.seats.any((s) => s.playerId == humanId)) {
      interest *= 1.9;
    }

    return d.pot * (1 + interest);
  }

  /// Builds the recap for the level just completed. [finishPlaces] / [prizes]
  /// give the finish place and payout of anyone who busted (for cash reports);
  /// [paidPlaces] / [inMoney] drive the bubble flavor. Prose is varied by level
  /// so repeated recaps don't read the same.
  LevelRecap buildRecap({
    required int levelJustFinished,
    required int playersLeft,
    required int averageStack,
    required int bigBlind,
    required int paidPlaces,
    required bool inMoney,
    required String humanId,
    required Map<String, int> currentChips,
    required Map<String, int> finishPlaces,
    required Map<String, int> prizes,
  }) {
    final salt = levelJustFinished; // deterministic per-level template rotation.
    _bb = bigBlind;

    // Who fell this level: level-start ids no longer active.
    final eliminated =
        _levelStartIds.where((id) => !currentChips.containsKey(id)).toList();
    final eliminatedCount = eliminated.length;

    // TEMP diagnostic, requested to eyeball bust rates by skill tier before
    // deciding whether to act on them — not a real feature, rip out once
    // reviewed.
    final debugBustRates = _debugBustRatesByKind(eliminated);

    // Ranking (for chip leaders + "top 100" personality watch).
    final ranked = currentChips.keys.toList()
      ..sort((a, b) => currentChips[b]!.compareTo(currentChips[a]!));
    final rankOf = {for (var i = 0; i < ranked.length; i++) ranked[i]: i + 1};

    // Tournament-wide leaderboard-history bookkeeping — every player's best
    // rank ever and whether they've ever started a level on crumbs, so a bust
    // or a comeback many levels later can still be recognised as one. Must run
    // before anything below reads `bestRankEver`/`wasCrippledEarlier`.
    final crumbs = _crumbs(averageStack);
    LeaderboardStorylines.updateHistory(
      meta: _meta,
      ranked: ranked,
      rankOf: rankOf,
      crumbs: crumbs,
      levelJustFinished: levelJustFinished,
    );

    // 1) Intro: field size + this level's carnage.
    final intro = _intro(salt, levelJustFinished, playersLeft, eliminatedCount);

    // 2) Bubble tension.
    final bubbleLine = _bubbleLine(salt, playersLeft, paidPlaces, inMoney);

    // 3) Chip leaders: top 3, with the level's delta (full names).
    final leaders = [
      for (final id in ranked.take(3))
        ChipLeaderLine(
          name: _meta[id]?.name ?? id,
          chips: currentChips[id]!,
          delta: currentChips[id]! - (_meta[id]?.levelStartChips ?? currentChips[id]!),
          isHuman: id == humanId,
        ),
    ];

    // 4) Personality eliminations — every named player who busted this level,
    //    with a payout note for those who reached the money.
    final eliminations = _eliminationLines(
        salt, eliminated, finishPlaces, prizes);

    // 5) Personalities running deep (top 100) — hyped.
    final risers = _riserLines(salt, ranked, rankOf);

    // 6) Personalities struggling (short and still in).
    final fallers = _fallerLines(salt, currentChips, averageStack);

    // 7) Follow-up on the previous level's chip leader.
    final leaderFollowUp = _leaderFollowUp(
        levelJustFinished, currentChips, finishPlaces, prizes);
    // Record this level's leader for next time.
    if (ranked.isNotEmpty) {
      _prevLeaderId = ranked.first;
      _prevLeaderName = _meta[ranked.first]?.name ?? ranked.first;
      _prevLeaderLevel = levelJustFinished;
    }

    // 8) The bounty leader among the players still in.
    final bountyLine = _bountyLeader(currentChips);

    // 9) Storylines: a table bully and comebacks first (from real stack moves),
    //    then cross-level leaderboard swings, then the generic hand-driven
    //    notes (hot / coolered / KO / card-dead).
    final notables = <String>[];
    final bully = _bullyLine(ranked, currentChips, averageStack);
    if (bully != null) notables.add(bully);
    notables.addAll(_comebackLines(currentChips, averageStack));
    notables.addAll(LeaderboardStorylines.fallenStar(
      meta: _meta,
      eliminated: eliminated,
      finishPlaces: finishPlaces,
      prizes: prizes,
    ));
    notables.addAll(LeaderboardStorylines.fadedLeader(
      meta: _meta,
      currentChips: currentChips,
      crumbs: crumbs,
      bigBlind: bigBlind,
    ));
    notables.addAll(LeaderboardStorylines.backFromDead(
      meta: _meta,
      levelJustFinished: levelJustFinished,
      currentChips: currentChips,
      avgStack: averageStack,
    ));
    notables.addAll(_storylines(currentChips));

    // 10) A full replay of the level's most interesting hand (see
    //     [_featureScore]), narrated now that we know which hand won the slot —
    //     narrating every hand at every table would be wasted work on a large
    //     field.
    final biggest = _biggestReplay;
    final featureHand = biggest == null ? null : HandNarrator.narrate(biggest);
    // Name the table when the hand came off a notable one. Two recognisable
    // players in the same game is what makes a feature table, and sitting at it
    // is the thing a tournament player tells people about afterwards.
    final fd = _biggestDigest;
    final featureTable = (fd != null && fd.notables.length >= 2)
        ? FeatureTable(
            number: fd.tableId + 1,
            names: fd.notables,
            humanSeated: fd.humanTable,
          )
        : null;

    // 11) The player's own story, plus a concrete breakdown of how they played.
    final yourStory = _yourStory(humanId, currentChips);
    final yourPlayStyle = _yourPlayStyleLines(humanId);

    return LevelRecap(
      levelJustFinished: levelJustFinished,
      playersLeft: playersLeft,
      eliminatedThisLevel: eliminatedCount,
      averageStack: averageStack,
      bigBlind: bigBlind,
      intro: intro,
      bubbleLine: bubbleLine,
      chipLeaders: leaders,
      biggestPots: List.of(_potsThisLevel),
      eliminations: eliminations,
      risers: risers,
      fallers: fallers,
      leaderFollowUp: leaderFollowUp,
      bountyLine: bountyLine,
      notables: notables,
      featureHand: featureHand,
      featureTable: featureTable,
      yourStory: yourStory,
      yourPlayStyle: yourPlayStyle,
      debugBustRates: debugBustRates,
    );
  }

  /// TEMP: "N% of pros busted, M% of amateurs busted" this level, so bust
  /// rates by skill tier can be eyeballed across a run. Remove this method,
  /// the `debugBustRates` field on [LevelRecap], and its render line once
  /// that's done — it is diagnostic, not a recap feature.
  String? _debugBustRatesByKind(List<String> eliminated) {
    final startByKind = <StandingKind, int>{};
    for (final id in _levelStartIds) {
      final k = _meta[id]?.kind;
      if (k == null) continue;
      startByKind[k] = (startByKind[k] ?? 0) + 1;
    }
    final bustedByKind = <StandingKind, int>{};
    for (final id in eliminated) {
      final k = _meta[id]?.kind;
      if (k == null) continue;
      bustedByKind[k] = (bustedByKind[k] ?? 0) + 1;
    }
    String pct(StandingKind k) {
      final start = startByKind[k] ?? 0;
      if (start == 0) return 'n/a';
      final busted = bustedByKind[k] ?? 0;
      return '${(100 * busted / start).toStringAsFixed(1)}% ($busted/$start)';
    }

    return 'DEBUG bust rate — pros: ${pct(StandingKind.pro)}, '
        'amateurs: ${pct(StandingKind.amateur)}';
  }

  /// A big-stack "bully": the chip leader who's well above average and racking
  /// up knockouts — the table can't win a pot off them.
  String? _bullyLine(
      List<String> ranked, Map<String, int> currentChips, int avgStack) {
    if (ranked.isEmpty || avgStack <= 0) return null;
    final id = ranked.first;
    final chips = currentChips[id] ?? 0;
    final m = _meta[id];
    if (m == null || chips < avgStack * 2 || m.knockoutsL < 2) return null;
    final xAvg = (chips / avgStack).toStringAsFixed(1);
    return '${ChronicleGrammar.who(m, capital: true)} ${ChronicleGrammar.isVerb(m)} bullying the table — $xAvg× the '
        'average stack and ${m.knockoutsL} knockouts this level; nobody can win '
        'a pot off ${ChronicleGrammar.whom(m)}.';
  }

  /// "Crumbs": the stack a player entering a level with this little is
  /// considered left for dead — ≲8 BB, or a tenth of average when there's no
  /// blind level to measure against (used both within a level and, via
  /// `wasCrippledEarlier`, across the whole tournament).
  int _crumbs(int avgStack) => _bb > 0 ? 8 * _bb : avgStack ~/ 10;

  /// Comebacks: players who came into the level on fumes and clawed back to a
  /// healthy stack. Same-level only — see `LeaderboardStorylines.backFromDead`
  /// for a recovery that took several levels.
  List<String> _comebackLines(Map<String, int> currentChips, int avgStack) {
    if (avgStack <= 0) return const [];
    final out = <String>[];
    final crumbs = _crumbs(avgStack);
    _meta.forEach((id, m) {
      final chips = currentChips[id];
      if (chips == null) return;
      if (m.levelStartChips <= crumbs && chips >= avgStack) {
        out.add('${ChronicleGrammar.who(m, capital: true)} ${ChronicleGrammar.was(m)} left for dead at '
            '${ChronicleGrammar.amt(m.levelStartChips, _bb)} and ${ChronicleGrammar.has(m)} clawed all the way back '
            'to ${ChronicleGrammar.amt(chips, _bb)}.');
      }
    });
    return out.take(2).toList();
  }

  /// The remaining player with the most knockouts, or null if nobody's racked
  /// up a meaningful count yet.
  String? _bountyLeader(Map<String, int> currentChips) {
    String? bestId;
    var best = 0;
    for (final id in currentChips.keys) {
      final ko = _meta[id]?.knockouts ?? 0;
      if (ko > best) {
        best = ko;
        bestId = id;
      }
    }
    if (bestId == null || best < 2) return null;
    final m = _meta[bestId];
    if (m == null) return null;
    return 'Bounty leader: ${ChronicleGrammar.who(m, capital: true)} ${ChronicleGrammar.has(m)} sent $best '
        'players to the rail.';
  }


  // ---- section generators --------------------------------------------------
  // Second-person grammar ("you are" vs. "Alex is") lives in ChronicleGrammar.

  String _intro(int salt, int level, int left, int out) {
    final tail = out == 0
        ? 'nobody hit the rail that level'
        : '$out ${out == 1 ? 'player' : 'players'} hit the rail';
    final pool = [
      'Level $level is in the books — ${formatChips(left)} still standing, $tail.',
      'That\'s a wrap on level $level. ${formatChips(left)} remain; $tail this level.',
      '${formatChips(left)} players left after level $level ($tail).',
      'Level $level down. Survivors: ${formatChips(left)}. This level, $tail.',
    ];
    return pool[salt % pool.length];
  }

  String? _bubbleLine(int salt, int left, int paid, bool inMoney) {
    if (paid <= 0 || left <= paid) return null;
    final fromMoney = left - paid;
    if (inMoney) return null;
    // Only start talking bubble once it's within reach.
    final window = (paid * 0.25).clamp(12.0, 400.0);
    if (fromMoney > window) return null;
    if (fromMoney <= 3) {
      final pool = [
        'Hand-for-hand territory — just $fromMoney from the money!',
        'The bubble is here: $fromMoney to go until everyone left cashes.',
        'Gut-check time — $fromMoney spots from the money.',
      ];
      return pool[salt % pool.length];
    }
    final pool = [
      'The money bubble looms — $fromMoney spots until the cash.',
      '$fromMoney to go until the money; stacks are tightening up.',
      'Pay jumps are in sight: $fromMoney from the money.',
    ];
    return pool[salt % pool.length];
  }

  List<String> _eliminationLines(int salt, List<String> eliminated,
      Map<String, int> finishPlaces, Map<String, int> prizes) {
    final names = <String>[];
    final cashes = <String>[];
    for (final id in eliminated) {
      final m = _meta[id];
      if (m == null || !m.isPersonality) continue;
      final prize = prizes[id] ?? 0;
      final place = finishPlaces[id];
      if (prize > 0) {
        final placeStr = place != null ? ' in ${ordinal(place)}' : '';
        cashes.add(
            '${ChronicleGrammar.who(m, capital: true)} banked \$${formatChips(prize)}$placeStr.');
      } else {
        names.add(ChronicleGrammar.who(m));
      }
    }
    final out = <String>[];
    if (names.isNotEmpty) {
      const intros = [
        'Some well-known names hit the rail: ',
        'Say goodbye to ',
        'The field claimed a few big names — out this level: ',
        'Rail news: no more bullets for ',
      ];
      out.add('${intros[salt % intros.length]}${ChronicleGrammar.nameList(names)}.');
    }
    for (final c in cashes) {
      out.add(c);
    }
    return out;
  }

  List<String> _riserLines(
      int salt, List<String> ranked, Map<String, int> rankOf) {
    final deep = [
      for (final id in ranked)
        if ((_meta[id]?.isPersonality ?? false) &&
            (rankOf[id] ?? 1 << 30) <= 100)
          id,
    ];
    if (deep.isEmpty) return const [];
    final out = <String>[];
    final lead = _meta[deep.first]!;

    // Separate template sets rather than patched grammar — second person wants
    // genuinely different phrasing, not just a swapped verb.
    const thirdPerson = [
      '$_ph is towering over the field — the rail is filling up with their fans.',
      '$_ph is on a heater; whispers of a deep run are already starting.',
      '$_ph\'s supporters are making arrangements to come rail their favorite.',
      '$_ph has a mountain of chips and a target on every back at the table.',
    ];
    const secondPerson = [
      'You are towering over the field — this is the stack everyone else is '
          'trying to avoid.',
      'You are on a heater, and the whole room can see it.',
      'You have a mountain of chips and a target on your back at every table.',
      'You are the one they are all going to have to go through.',
    ];
    out.add(lead.isHuman
        ? secondPerson[salt % secondPerson.length]
        : thirdPerson[salt % thirdPerson.length].replaceAll(_ph, lead.name));

    // Everyone else still in the top 100 — the human included, as "you".
    final others = deep.skip(1).map((id) => ChronicleGrammar.who(_meta[id]!)).toList();
    if (others.isNotEmpty) {
      const lead = ['Also cruising: ', 'Also deep in it: ', 'Still dangerous: '];
      out.add('${lead[salt % lead.length]}${ChronicleGrammar.nameList(others)}.');
    }
    return out;
  }

  List<String> _fallerLines(
      int salt, Map<String, int> currentChips, int avgStack) {
    if (avgStack <= 0) return const [];
    final short = <String>[];
    _meta.forEach((id, m) {
      if (!m.isPersonality) return;
      final chips = currentChips[id];
      if (chips == null) return; // busted — handled by eliminations
      final delta = chips - m.levelStartChips;
      if (chips <= avgStack ~/ 3 && delta < 0) short.add(ChronicleGrammar.who(m));
    });
    if (short.isEmpty) return const [];
    final names = short.take(4).toList();
    const pool = [
      'Down to the felt and fighting for a double: ',
      'Nursing short stacks: ',
      'On the ropes: ',
    ];
    return ['${pool[salt % pool.length]}${ChronicleGrammar.nameList(names)}.'];
  }

  String? _leaderFollowUp(int level, Map<String, int> currentChips,
      Map<String, int> finishPlaces, Map<String, int> prizes) {
    final id = _prevLeaderId;
    if (id == null || _prevLeaderLevel != level - 1) return null;
    final m = _meta[id];
    final name = _prevLeaderName ?? id;
    final chips = currentChips[id];
    if (chips != null) {
      return m != null && m.isHuman
          ? 'You were last level\'s chip leader and ${ChronicleGrammar.areStill(m)} in the mix '
              'with ${ChronicleGrammar.amt(chips, _bb)}.'
          : 'Last level\'s chip leader $name is still in the mix with '
              '${ChronicleGrammar.amt(chips, _bb)}.';
    }
    // The former leader busted since.
    final place = finishPlaces[id];
    final prize = prizes[id] ?? 0;
    final placeStr = place != null ? ' in ${ordinal(place)}' : '';
    final cash = prize > 0 ? ' for \$${formatChips(prize)}' : '';
    return 'How the mighty fall — last level\'s chip leader $name busted$placeStr$cash.';
  }

  List<String> _storylines(Map<String, int> currentChips) {
    final scored = <({int score, String line})>[];
    _meta.forEach((id, m) {
      final who = ChronicleGrammar.who(m, capital: true);
      // The human's own storylines outrank the field's: it is their tournament,
      // and a line about their level is the one they most want to read.
      final bump = m.isHuman ? 1000 : 0;

      if (m.knockoutsL >= 3) {
        scored.add((
          score: bump + 100 + m.knockoutsL,
          line: '$who ${ChronicleGrammar.isVerb(m)} a wrecking ball — ${m.knockoutsL} knockouts '
              'this level.'
        ));
      }
      if (m.luckyWinsL >= 2) {
        scored.add((
          score: bump + 90 + m.luckyWinsL,
          line: '$who ${ChronicleGrammar.isVerb(m)} running hot — won ${m.luckyWinsL} all-ins from '
              'behind this level.'
        ));
      }
      if (m.badBeatsL >= 2) {
        scored.add((
          score: bump + 80 + m.badBeatsL,
          line: '$who can\'t catch a break — ${m.badBeatsL} bad beats this level.'
        ));
      } else if (m.bigLossesL >= 2) {
        scored.add((
          score: bump + 70 + m.bigLossesL,
          line: '$who ${ChronicleGrammar.keeps(m)} getting coolered — lost ${m.bigLossesL} big '
              'pots with a real hand.'
        ));
      }
      final chips = currentChips[id];
      if (chips != null && m.showdownsL == 0 && m.levelStartChips > 0) {
        final delta = chips - m.levelStartChips;
        if (delta <= -(m.levelStartChips ~/ 3)) {
          scored.add((
            score: bump + 40,
            line: '$who ${ChronicleGrammar.isVerb(m)} card dead — blinded off ${formatChips(-delta)} '
                'without a showdown.'
          ));
        }
      }
    });
    scored.sort((a, b) => b.score.compareTo(a.score));
    return [for (final s in scored.take(3)) s.line];
  }

  String? _yourStory(String humanId, Map<String, int> currentChips) {
    final you = _meta[humanId];
    if (you == null || !currentChips.containsKey(humanId)) return null;
    final delta = currentChips[humanId]! - you.levelStartChips;
    final swing = delta >= 0 ? 'up ${formatChips(delta)}' : 'down ${formatChips(-delta)}';
    final buf = StringBuffer('You sit ${ChronicleGrammar.amt(currentChips[humanId]!, _bb)} ($swing).');
    if (you.biggestPotHandL != null && you.biggestPotL > 0) {
      buf.write(
          ' Your best pot: ${formatChips(you.biggestPotL)} with ${ChronicleGrammar.phrase(you.biggestPotHandL!)}.');
    } else if (you.knockoutsL > 0) {
      buf.write(' You scored ${you.knockoutsL} knockout'
          '${you.knockoutsL == 1 ? '' : 's'}.');
    }
    return buf.toString();
  }

  /// Concrete, numbers-included lines about *how* the human played this level
  /// — not just the chip swing `_yourStory` already covers. Each line is
  /// independently gated on its own sample size, the same rule every other
  /// flavor line in this file follows: don't claim a trend a handful of hands
  /// can't support.
  ///
  /// No "mixing it up"/bluff-variety line yet — the only existing proxy
  /// (postflop aggression factor, `features/analytics`) is computed from a
  /// separate pipeline and doesn't capture bet-sizing or bluff variety
  /// anyway, so there is no real metric for it in this codebase yet.
  List<String> _yourPlayStyleLines(String humanId) {
    final you = _meta[humanId];
    if (you == null || you.handsDealtL < 5) return const [];
    final out = <String>[];

    final vpipPct = (100 * you.vpipL / you.handsDealtL).round();
    final style = vpipPct <= 15
        ? 'playing tight'
        : vpipPct >= 40
            ? 'getting involved a lot'
            : 'playing a balanced range';
    out.add('You\'ve played ${you.vpipL} of ${you.handsDealtL} hands this '
        'level ($vpipPct%) — $style.');

    if (you.stealChancesL >= 3) {
      out.add('You\'ve taken ${you.stealAttemptsL} of ${you.stealChancesL} '
          'late-position steal chances this level.');
    }

    if (you.luckyWinsL > 0) {
      out.add('Cards have been kind: ${you.luckyWinsL} all-in'
          '${you.luckyWinsL == 1 ? '' : 's'} won from behind.');
    }
    if (you.badBeatsL > 0) {
      out.add('Cards have been cruel: ${you.badBeatsL} bad beat'
          '${you.badBeatsL == 1 ? '' : 's'} this level.');
    }

    return out;
  }

  // ---- helpers -------------------------------------------------------------

  /// Placeholder token for name substitution in hype templates.
  static const _ph = '@';

  int _bigPotBar(int avgStack) => avgStack <= 0 ? 1 : (avgStack * 0.6).round();

  static bool _isStrong(HandRank? r) =>
      r != null && r.index >= HandRank.threeOfAKind.index;

  NotablePot _toNotablePot(HandDigest d) {
    final winners = d.winners.toSet();
    final winner = d.showdown
        .where((s) => winners.contains(s.id))
        .fold<ShowdownEntry?>(
            null, (best, s) => best == null || s.net > best.net ? s : best);
    final loser = d.showdown
        .where((s) => !winners.contains(s.id))
        .fold<ShowdownEntry?>(
            null, (worst, s) => worst == null || s.net < worst.net ? s : worst);
    final anyAllIn = d.showdown.any((s) => s.wentAllIn);
    final suckout = winner != null && !winner.aheadOnFlop &&
        (loser?.aheadOnFlop ?? false) && anyAllIn;
    return NotablePot(
      levelIndex: d.levelIndex,
      tableId: d.tableId,
      pot: d.pot,
      winnerName: winner?.name ?? '',
      winnerHand: winner?.rank?.label ?? 'the winner',
      loserName: loser?.name ?? '',
      loserHand: loser?.rank?.label ?? 'a losing hand',
      allIn: anyAllIn,
      suckout: suckout,
      humanTable: d.humanTable,
    );
  }

}
