part of 'hand_narrator.dart';

/// Deterministic phrase variation.
///
/// Bart should not narrate every hand with the same sentence, but the
/// commentary also has to be reproducible — the same hand must always read the
/// same way, which `recap_end_to_end_test` pins. So the variation cannot come
/// from a random number generator. It comes from a stable hash of the hand
/// itself: different hands pick different phrasings, any single hand always
/// picks the same one.
class _Voice {
  _Voice(this._seed);

  /// Seeds from the hand's *content*, hashed by hand.
  ///
  /// Deliberately not `Object.hashAll`: Dart's `String.hashCode` is stable
  /// within a process but not guaranteed between runs, so that seed produced a
  /// hand that narrated one way today and another way tomorrow. An in-process
  /// determinism test cannot see that. This FNV-1a walk over the characters is
  /// stable everywhere, which is what "the same hand always reads the same way"
  /// actually requires.
  factory _Voice.of(HandReplay r) {
    final buf = StringBuffer()
      ..write(r.board.join())
      ..write(r.pot)
      ..write(r.bigBlind);
    for (final s in r.seats) {
      buf
        ..write(s.playerId)
        ..write(s.cards.join());
    }
    var hash = 0x811C9DC5;
    for (final unit in buf.toString().codeUnits) {
      hash = ((hash ^ unit) * 0x01000193) & 0x7FFFFFFF;
    }
    return _Voice(hash);
  }

  final int _seed;

  /// One of [options]. [salt] separates different lines within the same hand so
  /// they don't all land on the same index and read as a matched set.
  String pick(List<String> options, [int salt = 0]) {
    if (options.isEmpty) return '';
    final mixed = (_seed ^ (salt * 0x9E3779B1)) & 0x7FFFFFFF;
    return options[mixed % options.length];
  }
}

/// Derived facts about one replay, computed on demand and shared by every
/// commentary pass. Keeps the narrator itself readable.
class _HandContext {
  _HandContext(this.replay) : voice = _Voice.of(replay);

  final HandReplay replay;

  /// Deterministic phrasing variation for this hand.
  final _Voice voice;

  List<ReplaySeat> get flopSeats => replay.seats;

  /// The display name for a seat id, or null if they are not in the roster
  /// (folded preflop, so the replay never listed them).
  String? nameOf(String playerId) => replay.seats
      .where((s) => s.playerId == playerId)
      .map((s) => s.name)
      .firstOrNull;

  int bbOf(int chips) =>
      replay.bigBlind <= 0 ? chips : (chips / replay.bigBlind).round();

  String bb(int chips) {
    if (replay.bigBlind <= 0) return formatChips(chips);
    final v = chips / replay.bigBlind;
    return v >= 10
        ? '${v.round()}bb'
        : '${v.toStringAsFixed(1).replaceAll('.0', '')}bb';
  }

  ReplaySeat? seatFor(String playerId) => replay.seatOf(playerId);

  /// Every signature-move id that fired for [playerId] at any point in this
  /// hand, in the order they fired — the fact `_moveTag`/`entryVerdict` ground
  /// a personality callout in, instead of a blind archetype-label splice.
  List<String> movesFiredBy(String playerId) => [
        for (final s in replay.streets)
          for (final t in s.triggers)
            if (t.playerId == playerId) t.triggerId,
      ];

  ReplaySeat? seatByName(String name) =>
      replay.seats.where((s) => s.name == name).firstOrNull;

  /// The winner's exact equity at the moment the money went in, or null when
  /// nobody was ever all-in pre-showdown (`equityWhenAllIn` is null) or the
  /// winner wasn't one of the all-in contenders (a side-pot winner who wasn't
  /// actually at risk in the all-in itself).
  double? get winnerEquityWhenAllIn {
    final eq = replay.equityWhenAllIn;
    if (eq == null) return null;
    final winner = seatByName(replay.winnerName);
    if (winner == null) return null;
    return eq[winner.playerId];
  }

  String boardOf(ReplayStreet street) => street.boardAfter.map(_pretty).join(' ');

  String holding(ReplaySeat seat) => seat.cards.map(_pretty).join('');

  List<Card> cardsOf(ReplaySeat seat) =>
      [for (final c in seat.cards) Card.fromCode(c)];

  List<Card> boardCards(ReplayStreet street) =>
      [for (final c in street.boardAfter) Card.fromCode(c)];

  BoardTexture? textureAfter(ReplayStreet street) =>
      BoardTexture.maybeOf(boardCards(street));

  BoardTexture? textureBefore(ReplayStreet street) {
    final i = replay.streets.indexOf(street);
    if (i <= 0) return null;
    return BoardTexture.maybeOf(boardCards(replay.streets[i - 1]));
  }

  HandRank? rankOn(ReplaySeat seat, ReplayStreet street) {
    final board = boardCards(street);
    if (board.length < 3) return null;
    return HandEvaluator.evaluate([...cardsOf(seat), ...board]).rank;
  }

  HandValue? valueOn(ReplaySeat seat, ReplayStreet street) {
    final board = boardCards(street);
    if (board.length < 3) return null;
    return HandEvaluator.evaluate([...cardsOf(seat), ...board]);
  }

  String made(ReplaySeat seat, ReplayStreet street) {
    final rank = rankOn(seat, street);
    return rank == null
        ? holding(seat)
        : _phraseFor(rank, cardsOf(seat), boardCards(street));
  }

  String finalHand(ReplaySeat seat) {
    final rank = seat.finalRank;
    return rank == null
        ? holding(seat)
        : _phraseFor(rank, cardsOf(seat), boardCards(replay.streets.last));
  }

  bool isStrong(ReplaySeat seat, ReplayStreet street) {
    final r = rankOn(seat, street);
    return r != null && r.index >= HandRank.twoPair.index;
  }

  /// Where this hand sits among all starting hands, as a percentile (1 = the
  /// very best). Lets the commentary say "top 3% of hands".
  int preflopPercentile(ReplaySeat seat) {
    final cards = cardsOf(seat);
    final strength = HandStrength.preflopOf(cards[0], cards[1]);
    // Binary-search-free: sample fractions until the threshold drops below.
    for (var pct = 1; pct <= 100; pct++) {
      if (strength >= PreflopRanges.thresholdForFraction(pct / 100)) return pct;
    }
    return 100;
  }

  /// The players still live on a street, in position order.
  List<ReplaySeat> liveOn(ReplayStreet street) => [
    for (final s in replay.seats)
      if (s.foldedOn == null ||
          s.foldedOn!.index >= street.round.index)
        s,
  ];

  /// One line per live player describing exactly what they are working with —
  /// made hand, draws, and outs. This is the "TV commentary" view.
  List<String> holdingReads(ReplayStreet street) {
    final live = liveOn(street);
    if (live.length < 2) return const [];
    final leader = leaderOn(street);

    return [
      for (final s in live)
        () {
          final bits = <String>['${s.name} has ${holding(s)}'];
          final rank = rankOn(s, street);
          if (rank != null) {
            bits.add('for ${_phraseFor(rank, cardsOf(s), boardCards(street))}');
          }
          if (leader != null && s.playerId == leader.playerId) {
            bits.add('— best hand right now');
          } else if (leader != null) {
            // Judge "live" vs "thin" on the actual out count, never on whether
            // the hand happens to fit the flush/straight-draw pattern — two
            // overcards are six outs and deserve to be called live.
            final o = outsFor(s, street);
            bits.add(
              o >= 6
                  ? '— behind, but live with $o outs '
                        '(roughly ${equityFromOuts(o, street)}% to get there)'
                  : o > 0
                  ? '— behind with only $o outs against ${leader.name}'
                  : street.round == BettingRound.river
                  ? '— beaten by ${leader.name}'
                  : '— drawing dead against ${leader.name}',
            );
          }
          return bits.join(' ');
        }(),
    ];
  }

  /// The player with the best hand at this point in the hand.
  ReplaySeat? leaderOn(ReplayStreet street) {
    final live = liveOn(street);
    if (live.isEmpty) return null;
    ReplaySeat? best;
    HandValue? bestValue;
    for (final s in live) {
      final v = valueOn(s, street);
      if (v == null) continue;
      if (bestValue == null || v > bestValue) {
        bestValue = v;
        best = s;
      }
    }
    return best;
  }

  /// Who was ahead on the street *before* this one, so a runout can say whether
  /// the card that just landed changed the answer. Null on the flop, where
  /// there is no previous board to compare against.
  ReplaySeat? previousLeader(ReplayStreet street) {
    final i = replay.streets.indexOf(street);
    if (i <= 0) return null;
    final prev = replay.streets[i - 1];
    if (prev.boardAfter.length < 3) return null; // preflop: no board yet
    return leaderOn(prev);
  }

  /// Whether a seat holds the effective nuts on this board.
  bool isNuts(ReplaySeat seat, ReplayStreet street) => hasBestHand(seat, street);

  /// Whether this seat currently holds the best hand among the live players.
  ///
  /// The commentary can see every hole card, so this is exact — and it is a far
  /// better basis for calling a bet "value" or "a bluff" than a hand-rank
  /// threshold, which mislabelled top pair as air.
  bool hasBestHand(ReplaySeat seat, ReplayStreet street) {
    final leader = leaderOn(street);
    return leader != null && leader.playerId == seat.playerId;
  }

  /// Exact outs: how many unseen cards give this seat the best hand on the
  /// next street. Enumerates the remaining deck — cheap and precise, and much
  /// better commentary than a hand-wavy "he has a draw".
  int outsFor(ReplaySeat seat, ReplayStreet street) {
    final board = boardCards(street);
    if (board.length < 3 || board.length >= 5) return 0;

    final live = liveOn(street).where((s) => s.playerId != seat.playerId);
    if (live.isEmpty) return 0;

    final seen = <String>{
      for (final c in board) c.code,
      for (final s in replay.seats)
        for (final c in s.cards) c,
    };

    final mine = cardsOf(seat);
    var outs = 0;
    for (final rank in Rank.values) {
      for (final suit in Suit.values) {
        final card = Card(rank, suit);
        if (seen.contains(card.code)) continue;
        final next = [...board, card];
        final myValue = HandEvaluator.evaluate([...mine, ...next]);
        var best = true;
        for (final other in live) {
          final theirs = HandEvaluator.evaluate([...cardsOf(other), ...next]);
          if (theirs > myValue) {
            best = false;
            break;
          }
        }
        if (best) outs++;
      }
    }
    return outs;
  }

  /// Converts an exact out count into a rough percentage to improve, using the
  /// rule of 4 and 2 with the standard correction — plain `outs * 4` badly
  /// overstates anything above eight outs.
  int equityFromOuts(int outs, ReplayStreet street) {
    final twoCards = street.round == BettingRound.flop;
    if (!twoCards) return (outs * 2).clamp(0, 100);
    final raw = outs <= 8 ? outs * 4 : outs * 4 - (outs - 8);
    return raw.clamp(0, 100);
  }

  /// A hand with real equity behind its aggression: six outs is the classic
  /// two-overcards threshold, which makes a bet a semi-bluff rather than air.
  bool isSemiBluff(ReplaySeat seat, ReplayStreet street) =>
      hasDraw(seat, street) || outsFor(seat, street) >= 6;

  /// Whether a player holds a real draw — four to a flush or four to a straight.
  bool hasDraw(ReplaySeat seat, ReplayStreet street) {
    final board = boardCards(street);
    if (board.length < 3 || board.length >= 5) return false;
    final all = [...cardsOf(seat), ...board];

    final bySuit = <Suit, int>{};
    for (final c in all) {
      bySuit[c.suit] = (bySuit[c.suit] ?? 0) + 1;
    }
    if (bySuit.values.any((n) => n == 4)) return true;

    final vals = {for (final c in all) c.rank.value}.toList()..sort();
    for (var i = 0; i + 3 < vals.length; i++) {
      if (vals[i + 3] - vals[i] <= 4) return true;
    }
    return false;
  }

  /// The pot odds a call was getting, as a percentage of the final pot.
  double? potOddsFor(ReplayAction call, ReplayStreet street) {
    if (call.toCall <= 0) return null;
    final total = call.potBefore + call.toCall;
    if (total <= 0) return null;
    return call.toCall / total * 100;
  }

  /// Whether each caller on a street was getting the right price, given what
  /// they actually held.
  List<String> callPriceReads(ReplayStreet street) {
    final out = <String>[];
    for (final a in street.actions.where((a) => a.type == ActionType.call)) {
      final seat = seatFor(a.playerId);
      final odds = potOddsFor(a, street);
      if (seat == null || odds == null) continue;

      if (hasDraw(seat, street)) {
        final o = outsFor(seat, street);
        final equity = equityFromOuts(o, street);
        out.add(
          '${a.name} calls ${bb(a.toCall)} needing ${odds.toStringAsFixed(0)}% '
          'to break even, and with $o outs has roughly $equity% — '
          '${equity >= odds ? 'a clear call on price alone, before you even count the times they win by betting later' : 'strictly a losing call on direct odds; it needs implied odds to rescue it'}.',
        );
      } else if (isStrong(seat, street)) {
        final facingRaise = street.actions
            .where((x) => x.isAggressive)
            .length >=
            2;
        final ahead = hasBestHand(seat, street);
        out.add(
          facingRaise
              ? '${a.name} calls the raise with ${made(seat, street)}'
                    '${ahead ? ' — right call, they are still ahead and there is no need to escalate' : ', and is behind. Calling is at least cheaper than raising, but this is the spot to consider that a strong hand can still be second best'}.'
              : '${a.name} just calls with ${made(seat, street)}. Slowplaying is '
                    'defensible on a static board, but it invites a free card on '
                    'anything dynamic.',
        );
      }
    }
    return out;
  }

  /// Stack-to-pot ratio going to the flop, using the shortest live stack.
  double? sprAfterPreflop() {
    final preflop = replay.streets
        .where((s) => s.round == BettingRound.preflop)
        .firstOrNull;
    if (preflop == null || preflop.potAfter <= 0) return null;

    final stacks = [
      for (final s in replay.seats) s.startingStack,
    ]..sort();
    if (stacks.isEmpty) return null;
    return stacks.first / preflop.potAfter;
  }

  /// A verdict on why each player was (or wasn't) entitled to enter the pot.
  String entryVerdict(ReplaySeat seat) {
    final pct = preflopPercentile(seat);
    final allowed = (seat.position.openingFrequency * 100).round();

    if (seat.position == TablePosition.bigBlind) {
      return '${seat.name} defends the big blind with ${holding(seat)} (top '
          '$pct% of hands). Getting a price closing the action, that is a '
          'perfectly reasonable defend — the big blind is allowed to be wide.';
    }
    if (wasLooseEntry(seat)) {
      // Grounded in a move that actually fired, not a blind archetype splice
      // — see `_moveTag`'s doc for why that used to be wrong as often as it
      // was right.
      final tag = _moveTag(this, seat, aggressive: true);
      return '${seat.name} has no business playing ${holding(seat)} from '
          '${seat.position.phrase}. That is roughly the top $pct% of hands, and '
          'from that seat you want to be in the top $allowed% at most. Out of '
          'position with a hand that flops marginal pairs is how you build a '
          'pot you cannot win.$tag';
    }
    return '${seat.name} comes in with ${holding(seat)} from '
        '${seat.position.phrase} — top $pct%, comfortably inside the $allowed% '
        'you should be playing there. No complaints.';
  }

  /// Whether this seat's entry was looser than its position warrants.
  bool wasLooseEntry(ReplaySeat seat) {
    // The big blind gets a price to defend, so it is judged separately.
    if (seat.position == TablePosition.bigBlind) return false;
    final cards = cardsOf(seat);
    final strength = HandStrength.preflopOf(cards[0], cards[1]);
    return strength <
        PreflopRanges.thresholdForFraction(seat.position.openingFrequency);
  }

  List<ReplayAction> get allActions => [
    for (final s in replay.streets) ...s.actions,
  ];

  List<ReplayAction> actionsOn(BettingRound round) => [
    for (final s in replay.streets)
      if (s.round == round) ...s.actions,
  ];

  ReplayAction? aggressorOn(BettingRound round) {
    ReplayAction? last;
    for (final a in actionsOn(round)) {
      if (a.isAggressive) last = a;
    }
    return last;
  }

  ReplayAction? firstAggressiveOn(BettingRound round) =>
      actionsOn(round).where((a) => a.isAggressive).firstOrNull;

  /// The second aggressive action on a street — the raise or 3-bet.
  ReplayAction? raiseOn(BettingRound round) {
    final aggressive = actionsOn(round).where((a) => a.isAggressive).toList();
    return aggressive.length >= 2 ? aggressive[1] : null;
  }

  List<ReplayAction> callersOn(BettingRound round) =>
      actionsOn(round).where((a) => a.type == ActionType.call).toList();

  int liveOpponentsAt(ReplayAction action) {
    final foldedBefore = <String>{};
    for (final a in allActions) {
      if (identical(a, action)) break;
      if (a.isFold) foldedBefore.add(a.playerId);
    }
    return replay.seats
        .where((s) => s.playerId != action.playerId)
        .where((s) => !foldedBefore.contains(s.playerId))
        .length;
  }

  int aggressiveStreetsFor(String playerId) => replay.streets
      .where(
        (s) => s.actions.any((a) => a.playerId == playerId && a.isAggressive),
      )
      .length;

  /// The street on which the pot grew the most — where the hand was decided.
  ReplayStreet? pivotStreet() {
    ReplayStreet? best;
    var bestGrowth = 0;
    var prev = 0;
    for (final s in replay.streets) {
      final growth = s.potAfter - prev;
      if (growth > bestGrowth && s.round != BettingRound.preflop) {
        bestGrowth = growth;
        best = s;
      }
      prev = s.potAfter;
    }
    return bestGrowth >= replay.pot * 0.4 ? best : null;
  }

  /// Whether this seat put in the last bet or raise of the hand — the
  /// difference between a failed bluff and a bad call.
  bool wasLastAggressor(ReplaySeat seat) {
    ReplayAction? last;
    for (final a in allActions) {
      if (a.isAggressive) last = a;
    }
    return last != null && last.playerId == seat.playerId;
  }

  /// Whether a player folded the best hand to a bet from someone with less.
  bool wasBluffedOut(ReplaySeat seat) {
    final street = seat.foldedOn;
    if (street == null || street == BettingRound.preflop) return false;
    final rs = replay.streets.where((s) => s.round == street).firstOrNull;
    if (rs == null) return false;

    final bettor = rs.actions.where((a) => a.isAggressive).lastOrNull;
    if (bettor == null) return false;
    final bs = seatFor(bettor.playerId);
    if (bs == null) return false;

    final bettorValue = valueOn(bs, rs);
    final folderValue = valueOn(seat, rs);
    if (bettorValue == null || folderValue == null) return false;
    return folderValue > bettorValue;
  }

  /// Three of a kind is "a set" only when it's made from a pocket pair plus
  /// one matching board card — the live-poker distinction Bart's commentary
  /// is supposed to be making. The same rank made from a single hole card
  /// matching a paired board is "trips", a materially different (and weaker
  /// to play, since two of the four cards of that rank are already visible
  /// to the table) hand — collapsing both into "a set" was a real
  /// misread, not just looser phrasing.
  static String _phraseFor(HandRank rank, List<Card> hole, List<Card> board) {
    if (rank == HandRank.threeOfAKind) {
      final counts = <int, int>{};
      for (final c in [...hole, ...board]) {
        counts[c.rank.value] = (counts[c.rank.value] ?? 0) + 1;
      }
      final tripValue = counts.entries
          .firstWhere((e) => e.value == 3, orElse: () => counts.entries.first)
          .key;
      final holeMatches = hole.where((c) => c.rank.value == tripValue).length;
      return holeMatches == 2 ? 'a set' : 'trips';
    }
    return _phrase(rank);
  }

  static String _phrase(HandRank rank) => switch (rank) {
    HandRank.highCard => 'nothing but high card',
    HandRank.pair => 'one pair',
    HandRank.twoPair => 'two pair',
    HandRank.threeOfAKind => 'a set',
    HandRank.straight => 'a straight',
    HandRank.flush => 'a flush',
    HandRank.fullHouse => 'a full house',
    HandRank.fourOfAKind => 'quads',
    HandRank.straightFlush => 'a straight flush',
  };

  /// `"Ah"` -> `"A♥"`.
  static String _pretty(String code) {
    if (code.length < 2) return code;
    final rank = code.substring(0, code.length - 1);
    final suit = switch (code[code.length - 1].toLowerCase()) {
      'h' => '♥',
      'd' => '♦',
      's' => '♠',
      _ => '♣',
    };
    return '$rank$suit';
  }
}
