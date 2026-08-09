import 'package:monte/core/domain/engine/hand_evaluator.dart';
import 'package:monte/features/tournament/domain/tournament_snapshot.dart'
    show StandingKind;

/// One player's showing at a completed hand, as observed at the table (the
/// engine knows every hole card, so a recap of an *off-table* hand can honestly
/// report what was shown down). [aheadOnFlop] is true when this player held the
/// best hand among the all-in contenders as of the flop — used to tell a genuine
/// suck-out/bad-beat from a hand that was simply best throughout.
class ShowdownEntry {
  const ShowdownEntry({
    required this.id,
    required this.name,
    required this.kind,
    required this.wentAllIn,
    required this.net,
    required this.rank,
    this.aheadOnFlop = false,
  });

  final String id;
  final String name;
  final StandingKind kind;
  final bool wentAllIn;

  /// Chips won (+) or lost (-) this hand.
  final int net;

  /// The player's made hand at showdown, or null if they folded before it.
  final HandRank? rank;
  final bool aheadOnFlop;
}

/// A compact, fully-factual summary of one completed hand, handed to the
/// [TournamentChronicle]. Everything here is real engine output — no invention.
class HandDigest {
  const HandDigest({
    required this.levelIndex,
    required this.tableId,
    required this.pot,
    required this.showdown,
    required this.winners,
    required this.busted,
    this.humanTable = false,
    this.replay,
  });

  final int levelIndex;
  final int tableId;

  /// Total chips contested (won from opponents) this hand.
  final int pot;

  /// Players who reached showdown (empty when the hand ended on a fold).
  final List<ShowdownEntry> showdown;

  /// Ids of the winner(s).
  final List<String> winners;

  /// Ids eliminated this hand (busted).
  final List<String> busted;
  final bool humanTable;

  /// Full hand detail for a showdown (hole cards, board, street action), so the
  /// recap can replay the level's biggest pot. Null for folds / uncontested pots.
  final HandReplay? replay;
}

/// One line of a street's action, e.g. "Daniel Negreanu raises to 250".
class ReplayLine {
  const ReplayLine(this.text);
  final String text;
}

/// One street of a replayed hand: its name and the ordered action lines.
class ReplayStreet {
  const ReplayStreet(this.name, this.lines);
  final String name;
  final List<String> lines;
}

/// A player's showdown holding in a replay.
class ReplaySeat {
  const ReplaySeat(
      {required this.name, required this.cards, required this.won});
  final String name;
  final List<String> cards; // two card codes, e.g. ['Ah','Kd']
  final bool won;
}

/// A full, factual replay of one hand for the recap: the hole cards shown down,
/// the board, and the action street by street. Everything is real engine output.
class HandReplay {
  const HandReplay({
    required this.pot,
    required this.board,
    required this.seats,
    required this.streets,
    required this.winnerName,
    required this.winnerHand,
    required this.loserName,
    required this.loserHand,
    required this.winnerRank,
    required this.loserRank,
    required this.allIn,
    required this.suckout,
    required this.reachedRiver,
    this.commentary = const [],
  });

  final int pot;
  final List<String> board;
  final List<ReplaySeat> seats;
  final List<ReplayStreet> streets;
  final String winnerName;
  final String winnerHand;
  final String loserName;
  final String loserHand;
  final HandRank winnerRank;
  final HandRank loserRank;
  final bool allIn;
  final bool suckout;
  final bool reachedRiver;

  /// Bart-Hanson-style evaluative commentary, filled in by the chronicle.
  final List<String> commentary;

  HandReplay withCommentary(List<String> lines) => HandReplay(
        pot: pot,
        board: board,
        seats: seats,
        streets: streets,
        winnerName: winnerName,
        winnerHand: winnerHand,
        loserName: loserName,
        loserHand: loserHand,
        winnerRank: winnerRank,
        loserRank: loserRank,
        allIn: allIn,
        suckout: suckout,
        reachedRiver: reachedRiver,
        commentary: lines,
      );
}

/// Running per-player metagame counters. The `L`-suffixed fields are reset each
/// level (recaps talk about "this level"); the rest are tournament-wide.
class _Meta {
  _Meta(this.name, this.kind);
  String name;
  StandingKind kind;

  /// A real, named personality (a chosen pro/reg), not an anonymous generated
  /// filler and not the human — the players the recap tells stories about.
  bool isPersonality = false;

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

  /// The biggest showdown of the level, kept in full for a replay.
  HandReplay? _biggestReplay;

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
    _levelStartIds = activeChips.keys.toSet();
    for (final e in activeChips.entries) {
      final m = _of(e.key, names[e.key] ?? e.key, kinds[e.key] ?? StandingKind.pro);
      m.isPersonality = personalities.contains(e.key);
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

    // Retain the single biggest showdown in full, for the level's hand replay.
    if (d.replay != null &&
        d.showdown.length >= 2 &&
        (_biggestReplay == null || d.pot > _biggestReplay!.pot)) {
      _biggestReplay = d.replay;
    }
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
    final risers = _riserLines(salt, ranked, rankOf, currentChips, humanId);

    // 6) Personalities struggling (short and still in).
    final fallers = _fallerLines(salt, currentChips, averageStack, humanId);

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
    final bountyLine = _bountyLeader(currentChips, humanId);

    // 9) Storylines: a table bully and comebacks first (from real stack moves),
    //    then the generic hand-driven notes (hot / coolered / KO / card-dead).
    final notables = <String>[];
    final bully = _bullyLine(ranked, currentChips, averageStack, humanId);
    if (bully != null) notables.add(bully);
    notables.addAll(_comebackLines(currentChips, averageStack, humanId));
    notables.addAll(_storylines(humanId, currentChips));

    // 10) A full replay of the level's biggest showdown, with commentary.
    final featureHand =
        _biggestReplay?.withCommentary(_commentary(_biggestReplay!, salt));

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
      yourStory: yourStory,
    );
  }

  /// A big-stack "bully": the chip leader who's well above average and racking
  /// up knockouts — the table can't win a pot off them.
  String? _bullyLine(List<String> ranked, Map<String, int> currentChips,
      int avgStack, String humanId) {
    if (ranked.isEmpty || avgStack <= 0) return null;
    final id = ranked.first;
    if (id == humanId) return null;
    final chips = currentChips[id] ?? 0;
    final m = _meta[id];
    if (m == null || chips < avgStack * 2 || m.knockoutsL < 2) return null;
    final xAvg = (chips / avgStack).toStringAsFixed(1);
    return '${m.name} is bullying the table — $xAvg× the average stack and '
        '${m.knockoutsL} knockouts this level; nobody can win a pot off them.';
  }

  /// Comebacks: players who came into the level on fumes and clawed back to a
  /// healthy stack.
  List<String> _comebackLines(
      Map<String, int> currentChips, int avgStack, String humanId) {
    if (avgStack <= 0) return const [];
    final out = <String>[];
    _meta.forEach((id, m) {
      if (id == humanId) return;
      final chips = currentChips[id];
      if (chips == null) return;
      // Started the level with crumbs (≲8 BB or a tenth of average), now healthy.
      final crumbs = _bb > 0 ? 8 * _bb : avgStack ~/ 10;
      if (m.levelStartChips <= crumbs && chips >= avgStack) {
        out.add('${m.name} was left for dead at ${_amt(m.levelStartChips)} and '
            'has clawed all the way back to ${_amt(chips)}.');
      }
    });
    return out.take(2).toList();
  }

  /// Bart-Hanson-style commentary on a replayed hand — evaluative, range- and
  /// exploit-minded, and grounded entirely in what actually happened.
  List<String> _commentary(HandReplay r, int salt) {
    final out = <String>[];
    final w = r.winnerName;
    final l = r.loserName;
    final wh = r.winnerHand.toLowerCase();
    final lh = r.loserHand.toLowerCase();
    if (r.suckout) {
      out.add('Bart: the money went in bad here — $l had $w drawing thin and '
          'got there anyway. That\'s variance, not a misplay by $l.');
    } else if (r.allIn && r.winnerRank.index >= HandRank.straight.index) {
      out.add('Bart: textbook stack-off. With $wh, $w is never folding, and '
          'getting it in against $lh is exactly the spot you want.');
    } else if (r.allIn) {
      out.add('Bart: a thin stack-off — $w gets it in with $wh and gets there. '
          'I\'d want a little more before playing a pot this size.');
    }
    if (!r.suckout && r.reachedRiver && r.winnerRank.index >= HandRank.twoPair.index) {
      out.add('Bart: nice line by $w — betting for value with $wh the whole way '
          'and getting max out of it.');
    }
    if (!r.suckout && r.loserRank.index <= HandRank.pair.index) {
      out.add('Bart: the call at the end from $l with $lh is loose — you have to '
          'ask what worse hand is paying you off there.');
    }
    if (out.isEmpty) {
      const generic = [
        'Bart: a clean, standard pot — well played by both.',
        'Bart: nothing fancy here, just value finding a caller.',
        'Bart: a level-defining pot; the chips found the right stack.',
      ];
      out.add(generic[salt % generic.length]);
    }
    return out.take(2).toList();
  }

  /// The remaining player with the most knockouts, or null if nobody's racked
  /// up a meaningful count yet.
  String? _bountyLeader(Map<String, int> currentChips, String humanId) {
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
    final name = bestId == humanId ? 'You' : (_meta[bestId]?.name ?? bestId);
    final verb = bestId == humanId ? 'have' : 'has';
    return 'Bounty leader: $name $verb sent $best players to the rail.';
  }

  // ---- section generators --------------------------------------------------

  String _intro(int salt, int level, int left, int out) {
    final tail = out == 0
        ? 'nobody hit the rail that level'
        : '$out ${out == 1 ? 'player' : 'players'} hit the rail';
    final pool = [
      'Level $level is in the books — ${_chips(left)} still standing, $tail.',
      'That\'s a wrap on level $level. ${_chips(left)} remain; $tail this level.',
      '${_chips(left)} players left after level $level ($tail).',
      'Level $level down. Survivors: ${_chips(left)}. This level, $tail.',
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
        final placeStr = place != null ? ' in ${_ordinal(place)}' : '';
        cashes.add('${m.name} banked \$${_chips(prize)}$placeStr.');
      } else {
        names.add(m.name);
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

  List<String> _riserLines(int salt, List<String> ranked,
      Map<String, int> rankOf, Map<String, int> currentChips, String humanId) {
    final deep = [
      for (final id in ranked)
        if (id != humanId &&
            (_meta[id]?.isPersonality ?? false) &&
            (rankOf[id] ?? 1 << 30) <= 100)
          id,
    ];
    if (deep.isEmpty) return const [];
    final out = <String>[];
    final leadId = deep.first;
    final leadName = _meta[leadId]!.name;
    const hype = [
      '$_ph is towering over the field — the rail is filling up with their fans.',
      '$_ph is on a heater; whispers of a deep run are already starting.',
      '$_ph\'s supporters are making arrangements to come rail their favorite.',
      '$_ph has a mountain of chips and a target on every back at the table.',
    ];
    out.add(hype[salt % hype.length].replaceAll(_ph, leadName));
    // List every remaining personality who's still in the top 100 — by name.
    final others = deep.skip(1).map((id) => _meta[id]!.name).toList();
    if (others.isNotEmpty) {
      const lead = ['Also cruising: ', 'Also deep in it: ', 'Still dangerous: '];
      out.add('${lead[salt % lead.length]}${_nameList(others)}.');
    }
    return out;
  }

  List<String> _fallerLines(
      int salt, Map<String, int> currentChips, int avgStack, String humanId) {
    if (avgStack <= 0) return const [];
    final short = <String>[];
    _meta.forEach((id, m) {
      if (id == humanId || !m.isPersonality) return;
      final chips = currentChips[id];
      if (chips == null) return; // busted — handled by eliminations
      final delta = chips - m.levelStartChips;
      if (chips <= avgStack ~/ 3 && delta < 0) short.add(m.name);
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
    final name = _prevLeaderName ?? id;
    final chips = currentChips[id];
    if (chips != null) {
      return 'Last level\'s chip leader $name is still in the mix with ${_amt(chips)}.';
    }
    // The former leader busted since.
    final place = finishPlaces[id];
    final prize = prizes[id] ?? 0;
    final placeStr = place != null ? ' in ${_ordinal(place)}' : '';
    final cash = prize > 0 ? ' for \$${_chips(prize)}' : '';
    return 'How the mighty fall — last level\'s chip leader $name busted$placeStr$cash.';
  }

  List<String> _storylines(String humanId, Map<String, int> currentChips) {
    final scored = <({int score, String line})>[];
    _meta.forEach((id, m) {
      if (id == humanId) return;
      final name = m.name;
      if (m.knockoutsL >= 3) {
        scored.add((
          score: 100 + m.knockoutsL,
          line: '$name is a wrecking ball — ${m.knockoutsL} knockouts this level.'
        ));
      }
      if (m.luckyWinsL >= 2) {
        scored.add((
          score: 90 + m.luckyWinsL,
          line:
              '$name is running hot — won ${m.luckyWinsL} all-ins from behind this level.'
        ));
      }
      if (m.badBeatsL >= 2) {
        scored.add((
          score: 80 + m.badBeatsL,
          line: '$name can\'t catch a break — ${m.badBeatsL} bad beats this level.'
        ));
      } else if (m.bigLossesL >= 2) {
        scored.add((
          score: 70 + m.bigLossesL,
          line: '$name keeps getting coolered — lost ${m.bigLossesL} big pots '
              'with a real hand.'
        ));
      }
      final chips = currentChips[id];
      if (chips != null && m.showdownsL == 0 && m.levelStartChips > 0) {
        final delta = chips - m.levelStartChips;
        if (delta <= -(m.levelStartChips ~/ 3)) {
          scored.add((
            score: 40,
            line: '$name is card dead — blinded off ${_chips(-delta)} '
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
    final swing = delta >= 0 ? 'up ${_chips(delta)}' : 'down ${_chips(-delta)}';
    final buf = StringBuffer('You sit ${_amt(currentChips[humanId]!)} ($swing).');
    if (you.biggestPotHandL != null && you.biggestPotL > 0) {
      buf.write(
          ' Your best pot: ${_chips(you.biggestPotL)} with ${_phrase(you.biggestPotHandL!)}.');
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

  static String _ordinal(int n) {
    if (n >= 11 && n <= 13) return '${n}th';
    return switch (n % 10) {
      1 => '${n}st',
      2 => '${n}nd',
      3 => '${n}rd',
      _ => '${n}th',
    };
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

  /// A chip amount with its big-blind equivalent, e.g. "250,000 (125 BB)".
  String _amt(int chips) =>
      _bb > 0 ? '${_chips(chips)} (${_chips((chips / _bb).round())} BB)' : _chips(chips);

  static String _chips(int n) {
    final neg = n < 0;
    final s = n.abs().toString();
    final b = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
      b.write(s[i]);
    }
    return neg ? '-$b' : b.toString();
  }
}

/// A headline pot from a level, with the hands that were shown down.
class NotablePot {
  const NotablePot({
    required this.levelIndex,
    required this.tableId,
    required this.pot,
    required this.winnerName,
    required this.winnerHand,
    required this.loserName,
    required this.loserHand,
    required this.allIn,
    required this.suckout,
    required this.humanTable,
  });
  final int levelIndex;
  final int tableId;
  final int pot;
  final String winnerName;
  final String winnerHand;
  final String loserName;
  final String loserHand;
  final bool allIn;
  final bool suckout;
  final bool humanTable;
}

/// One line of the chip-leader board in a recap.
class ChipLeaderLine {
  const ChipLeaderLine({
    required this.name,
    required this.chips,
    required this.delta,
    required this.isHuman,
  });
  final String name;
  final int chips;
  final int delta;
  final bool isHuman;
}

/// A generated recap for one completed level — everything the UI needs to draw
/// the "level N in the books" card. All content is derived from real results.
class LevelRecap {
  const LevelRecap({
    required this.levelJustFinished,
    required this.playersLeft,
    required this.eliminatedThisLevel,
    required this.averageStack,
    required this.bigBlind,
    required this.intro,
    required this.bubbleLine,
    required this.chipLeaders,
    required this.biggestPots,
    required this.eliminations,
    required this.risers,
    required this.fallers,
    required this.leaderFollowUp,
    required this.bountyLine,
    required this.notables,
    required this.featureHand,
    required this.yourStory,
  });
  final int levelJustFinished;
  final int playersLeft;
  final int eliminatedThisLevel;
  final int averageStack;

  /// The big blind of the level recapped (for expressing stacks in BBs).
  final int bigBlind;

  /// Lead line: field size + this level's eliminations.
  final String intro;

  /// Money-bubble tension, or null when it's not near.
  final String? bubbleLine;
  final List<ChipLeaderLine> chipLeaders;
  final List<NotablePot> biggestPots;

  /// Named personalities who busted this level (with cash notes when ITM).
  final List<String> eliminations;

  /// Named personalities running deep (top 100), hyped.
  final List<String> risers;

  /// Named personalities on short stacks, struggling.
  final List<String> fallers;

  /// A follow-up on the previous level's chip leader, or null.
  final String? leaderFollowUp;

  /// The remaining knockout (bounty) leader, or null.
  final String? bountyLine;

  /// Table-bully / comeback / hand-driven storylines (hot / coolered / KO).
  final List<String> notables;

  /// A full replay (with commentary) of the level's biggest showdown, or null.
  final HandReplay? featureHand;
  final String? yourStory;
}
