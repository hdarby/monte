import 'package:monte/core/domain/engine/hand_evaluator.dart';
import 'package:monte/core/util/format.dart';
import 'package:monte/features/tournament/domain/chronicle/hand_digest.dart';
import 'package:monte/features/tournament/domain/chronicle/hand_narrator.dart';
import 'package:monte/features/tournament/domain/chronicle/hand_replay.dart';
import 'package:monte/features/tournament/domain/chronicle/level_recap.dart';
import 'package:monte/features/tournament/domain/tournament_snapshot.dart'
    show StandingKind;

/// Running per-player metagame counters. The `L`-suffixed fields are reset each
/// level (recaps talk about "this level"); the rest are tournament-wide.
class _Meta {
  _Meta(this.name, this.kind);
  String name;
  StandingKind kind;

  /// A real, named personality (a chosen pro/reg) or the human — i.e. not an
  /// anonymous generated filler. These are the players the recap tells stories
  /// about. The human is included deliberately: they are as much a character in
  /// the tournament as anyone else, and leaving them out made the recap read
  /// like it was about somebody else's game.
  bool isPersonality = false;

  /// True for the human's seat, so prose can address them in second person
  /// ("you are running hot") instead of third ("Alex is running hot").
  bool get isHuman => kind == StandingKind.human;

  int levelStartChips = 0;

  // Per-level.
  int handsWonL = 0;
  int showdownsL = 0;
  int knockoutsL = 0;
  int luckyWinsL = 0; // won an all-in while behind on the flop
  int badBeatsL = 0; // lost an all-in while ahead on the flop
  int bigLossesL = 0; // lost a big pot at showdown holding a strong hand
  int biggestPotL = 0;
  String? biggestPotHandL; // hero's hand in their biggest won pot this level

  // Tournament-wide.
  int knockouts = 0;
}

/// Accumulates real results across every table and turns each completed level
/// into a [LevelRecap]. Pure and deterministic — fed [HandDigest]s by the
/// controller, snapshotted at level starts, and asked to build a recap at level
/// ends. Flavor lines are only ever emitted when the underlying counts justify
/// them, so the prose stays grounded in what actually happened.
class TournamentChronicle {
  final Map<String, _Meta> _meta = {};

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

  _Meta _of(String id, String name, StandingKind kind) =>
      _meta.putIfAbsent(id, () => _Meta(name, kind))
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
    }
  }

  /// Folds one completed hand into the tally. [avgStack] scales the "big pot"
  /// bar so notability is relative to the current stacks, not an absolute.
  void record(HandDigest d, {required int avgStack}) {
    final winners = d.winners.toSet();
    final big = d.pot >= _bigPotBar(avgStack);

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
    // seeing one is the point of having authored it.
    final moves =
        r.streets.fold<int>(0, (a, s) => a + s.triggers.length).clamp(0, 2);
    interest += 0.25 * moves;

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

    // Ranking (for chip leaders + "top 100" personality watch).
    final ranked = currentChips.keys.toList()
      ..sort((a, b) => currentChips[b]!.compareTo(currentChips[a]!));
    final rankOf = {for (var i = 0; i < ranked.length; i++) ranked[i]: i + 1};

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
    //    then the generic hand-driven notes (hot / coolered / KO / card-dead).
    final notables = <String>[];
    final bully = _bullyLine(ranked, currentChips, averageStack);
    if (bully != null) notables.add(bully);
    notables.addAll(_comebackLines(currentChips, averageStack));
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

    // 11) The player's own story.
    final yourStory = _yourStory(humanId, currentChips);

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
    );
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
    return '${_who(m, capital: true)} ${_is(m)} bullying the table — $xAvg× the '
        'average stack and ${m.knockoutsL} knockouts this level; nobody can win '
        'a pot off ${_whom(m)}.';
  }

  /// Comebacks: players who came into the level on fumes and clawed back to a
  /// healthy stack.
  List<String> _comebackLines(Map<String, int> currentChips, int avgStack) {
    if (avgStack <= 0) return const [];
    final out = <String>[];
    _meta.forEach((id, m) {
      final chips = currentChips[id];
      if (chips == null) return;
      // Started the level with crumbs (≲8 BB or a tenth of average), now healthy.
      final crumbs = _bb > 0 ? 8 * _bb : avgStack ~/ 10;
      if (m.levelStartChips <= crumbs && chips >= avgStack) {
        out.add('${_who(m, capital: true)} ${_was(m)} left for dead at '
            '${_amt(m.levelStartChips)} and ${_has(m)} clawed all the way back '
            'to ${_amt(chips)}.');
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
    return 'Bounty leader: ${_who(m, capital: true)} ${_has(m)} sent $best '
        'players to the rail.';
  }


  // ---- second-person grammar -----------------------------------------------
  //
  // The human appears in the recap alongside everyone else, so every line that
  // names a player needs to work in both third person ("Negreanu is running
  // hot") and second ("you are running hot"). These keep the agreement right
  // without duplicating every template.

  /// How to refer to a player: their name, or "you" for the human.
  /// [capital] for sentence-initial use.
  static String _who(_Meta m, {bool capital = false}) =>
      m.isHuman ? (capital ? 'You' : 'you') : m.name;

  /// "are still" / "is still" — the leader follow-up's only agreement wrinkle.
  static String _areStill(_Meta m) => m.isHuman ? 'are still' : 'is still';

  /// Object form, for "nobody can win a pot off them / you".
  static String _whom(_Meta m) => m.isHuman ? 'you' : 'them';

  static String _is(_Meta m) => m.isHuman ? 'are' : 'is';
  static String _has(_Meta m) => m.isHuman ? 'have' : 'has';
  static String _was(_Meta m) => m.isHuman ? 'were' : 'was';
  static String _keeps(_Meta m) => m.isHuman ? 'keep' : 'keeps';

  // ---- section generators --------------------------------------------------

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
            '${_who(m, capital: true)} banked \$${formatChips(prize)}$placeStr.');
      } else {
        names.add(_who(m));
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
      out.add('${intros[salt % intros.length]}${_nameList(names)}.');
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
    final others = deep.skip(1).map((id) => _who(_meta[id]!)).toList();
    if (others.isNotEmpty) {
      const lead = ['Also cruising: ', 'Also deep in it: ', 'Still dangerous: '];
      out.add('${lead[salt % lead.length]}${_nameList(others)}.');
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
      if (chips <= avgStack ~/ 3 && delta < 0) short.add(_who(m));
    });
    if (short.isEmpty) return const [];
    final names = short.take(4).toList();
    const pool = [
      'Down to the felt and fighting for a double: ',
      'Nursing short stacks: ',
      'On the ropes: ',
    ];
    return ['${pool[salt % pool.length]}${_nameList(names)}.'];
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
          ? 'You were last level\'s chip leader and ${_areStill(m)} in the mix '
              'with ${_amt(chips)}.'
          : 'Last level\'s chip leader $name is still in the mix with '
              '${_amt(chips)}.';
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
      final who = _who(m, capital: true);
      // The human's own storylines outrank the field's: it is their tournament,
      // and a line about their level is the one they most want to read.
      final bump = m.isHuman ? 1000 : 0;

      if (m.knockoutsL >= 3) {
        scored.add((
          score: bump + 100 + m.knockoutsL,
          line: '$who ${_is(m)} a wrecking ball — ${m.knockoutsL} knockouts '
              'this level.'
        ));
      }
      if (m.luckyWinsL >= 2) {
        scored.add((
          score: bump + 90 + m.luckyWinsL,
          line: '$who ${_is(m)} running hot — won ${m.luckyWinsL} all-ins from '
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
          line: '$who ${_keeps(m)} getting coolered — lost ${m.bigLossesL} big '
              'pots with a real hand.'
        ));
      }
      final chips = currentChips[id];
      if (chips != null && m.showdownsL == 0 && m.levelStartChips > 0) {
        final delta = chips - m.levelStartChips;
        if (delta <= -(m.levelStartChips ~/ 3)) {
          scored.add((
            score: bump + 40,
            line: '$who ${_is(m)} card dead — blinded off ${formatChips(-delta)} '
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
    final buf = StringBuffer('You sit ${_amt(currentChips[humanId]!)} ($swing).');
    if (you.biggestPotHandL != null && you.biggestPotL > 0) {
      buf.write(
          ' Your best pot: ${formatChips(you.biggestPotL)} with ${_phrase(you.biggestPotHandL!)}.');
    } else if (you.knockoutsL > 0) {
      buf.write(' You scored ${you.knockoutsL} knockout'
          '${you.knockoutsL == 1 ? '' : 's'}.');
    }
    return buf.toString();
  }

  // ---- helpers -------------------------------------------------------------

  /// Placeholder token for name substitution in hype templates.
  static const _ph = '@';

  /// Joins names as "A, B and C".
  static String _nameList(List<String> names) {
    if (names.isEmpty) return '';
    if (names.length == 1) return names.first;
    return '${names.sublist(0, names.length - 1).join(', ')} and ${names.last}';
  }

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

  /// A natural-language phrase for a made hand ("a flush", "a set", …).
  static String _phrase(String label) {
    switch (label) {
      case 'Three of a Kind':
        return 'a set';
      case 'Two Pair':
        return 'two pair';
      case 'High Card':
        return 'ace-high';
      default:
        return 'a ${label.toLowerCase()}';
    }
  }

  /// A chip amount with its big-blind equivalent, e.g. "250,000 (125 BB)",
  /// using the big blind of the level being recapped.
  String _amt(int chips) => formatChipsWithBb(chips, _bb);
}
