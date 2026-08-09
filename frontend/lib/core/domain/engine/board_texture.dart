import 'package:meta/meta.dart';

import 'package:monte/core/domain/engine/card.dart';

/// The six textures a board can wear. They are **not** mutually exclusive — a
/// board is usually several at once (paired *and* dry *and* static), which is
/// how commentators actually describe them.
///
/// The pairs answer different questions:
/// - **dry / wet** — how much equity is out there *right now* (draws available).
/// - **static / dynamic** — how much the *best hand* is likely to change on
///   later streets. A dry board can still be dynamic if overcards are coming.
enum BoardTextureKind {
  /// Few or no draws; the board hands out very little equity.
  dry('dry'),

  /// Draw-heavy — flush draws, open-enders, or both.
  wet('wet'),

  /// All one suit; a flush is already possible.
  monochrome('monochrome'),

  /// Later cards are likely to change who is winning — the nuts will move.
  dynamicBoard('dynamic'),

  /// Whoever is ahead now is very likely still ahead on the river.
  staticBoard('static'),

  /// Two or more of a rank on board.
  paired('paired');

  const BoardTextureKind(this.label);
  final String label;
}

/// How the board's suits line up.
enum Suitedness {
  /// Three or more different suits, no flush possible yet.
  rainbow('rainbow'),

  /// Exactly two of a suit — a flush draw is live.
  twoTone('two-tone'),

  /// Three of a suit — a made flush is out there.
  monotone('monotone');

  const Suitedness(this.label);
  final String label;
}

/// How connected the board is — how much straight equity it hands out.
enum Connectedness {
  /// No two cards close together; straights are essentially impossible.
  disconnected('disconnected'),

  /// Two cards within a gap or two; some gutshots live.
  semiConnected('semi-connected'),

  /// Three cards inside a five-rank window; open-enders and made straights.
  connected('connected');

  const Connectedness(this.label);
  final String label;
}

/// A read on the community cards: which of the six textures apply, who the
/// board favours, and what draws are live.
///
/// Pure engine analysis, no Flutter — used by the tournament recap's commentary
/// and available to the coach. It describes the *board*, not any particular
/// holding, so callers layer their own hand-specific reads on top.
@immutable
class BoardTexture {
  const BoardTexture({
    required this.cards,
    required this.kinds,
    required this.paired,
    required this.trips,
    required this.suitedness,
    required this.connectedness,
    required this.highRank,
    required this.wetness,
    required this.dynamism,
    required this.broadwayCount,
  });

  /// Analyses 3-5 community cards. Use [maybeOf] when the board may be shorter.
  factory BoardTexture.of(List<Card> board) {
    final ranks = [for (final c in board) c.rank.value]..sort();
    final counts = <int, int>{};
    for (final r in ranks) {
      counts[r] = (counts[r] ?? 0) + 1;
    }
    final maxCount = counts.values.fold(0, (a, b) => a > b ? a : b);

    final suitCounts = <Suit, int>{};
    for (final c in board) {
      suitCounts[c.suit] = (suitCounts[c.suit] ?? 0) + 1;
    }
    final maxSuit = suitCounts.values.fold(0, (a, b) => a > b ? a : b);
    final suitedness = maxSuit >= 3
        ? Suitedness.monotone
        : maxSuit == 2
        ? Suitedness.twoTone
        : Suitedness.rainbow;

    final connectedness = _connectedness(ranks);
    final broadway = ranks.where((r) => r >= 10).length;
    final highRank = ranks.isEmpty ? 0 : ranks.last;
    final isPaired = maxCount >= 2;

    // Wetness: equity available *now*.
    var wetness = 0.0;
    wetness += switch (suitedness) {
      Suitedness.monotone => 0.40,
      Suitedness.twoTone => 0.28,
      Suitedness.rainbow => 0.0,
    };
    wetness += switch (connectedness) {
      Connectedness.connected => 0.34,
      Connectedness.semiConnected => 0.16,
      Connectedness.disconnected => 0.0,
    };
    if (isPaired) wetness -= 0.08;
    if (broadway >= 2) wetness += 0.08;
    wetness = wetness.clamp(0.0, 1.0);

    // Dynamism: how much later cards can move the nuts. Distinct from wetness —
    // a low rainbow board is dry, but overcards still change everything.
    var dynamism = 0.0;
    if (suitedness == Suitedness.twoTone) dynamism += 0.30;
    if (suitedness == Suitedness.monotone) dynamism += 0.15;
    dynamism += switch (connectedness) {
      Connectedness.connected => 0.35,
      Connectedness.semiConnected => 0.18,
      Connectedness.disconnected => 0.0,
    };
    if (highRank <= 9) dynamism += 0.22; // overcards still to come
    if (highRank == 14) dynamism -= 0.18; // the top card is already out
    if (isPaired) dynamism += 0.08; // boats and trips can arrive
    if (board.length >= 5) dynamism = 0; // river: nothing left to change
    dynamism = dynamism.clamp(0.0, 1.0);

    final kinds = <BoardTextureKind>{
      if (isPaired) BoardTextureKind.paired,
      if (suitedness == Suitedness.monotone) BoardTextureKind.monochrome,
      if (wetness >= 0.45) BoardTextureKind.wet,
      if (wetness < 0.25) BoardTextureKind.dry,
      if (dynamism >= 0.45) BoardTextureKind.dynamicBoard,
      if (dynamism < 0.25) BoardTextureKind.staticBoard,
    };

    return BoardTexture(
      cards: List.unmodifiable(board),
      kinds: Set.unmodifiable(kinds),
      paired: maxCount == 2,
      trips: maxCount >= 3,
      suitedness: suitedness,
      connectedness: connectedness,
      highRank: highRank,
      wetness: wetness,
      dynamism: dynamism,
      broadwayCount: broadway,
    );
  }

  /// Null-safe entry point: returns null before the flop.
  static BoardTexture? maybeOf(List<Card> board) =>
      board.length < 3 ? null : BoardTexture.of(board);

  final List<Card> cards;

  /// Every texture that applies to this board.
  final Set<BoardTextureKind> kinds;

  /// Exactly one pair on board.
  final bool paired;

  /// Three or more of a rank on board.
  final bool trips;

  final Suitedness suitedness;
  final Connectedness connectedness;

  /// Rank value (2-14) of the highest board card.
  final int highRank;

  /// Equity available to draws right now, in [0,1].
  final double wetness;

  /// How much later cards can change the winner, in [0,1]. Zero on the river.
  final double dynamism;

  /// How many broadway (T+) cards are out.
  final int broadwayCount;

  bool has(BoardTextureKind kind) => kinds.contains(kind);

  bool get isDry => has(BoardTextureKind.dry);
  bool get isWet => has(BoardTextureKind.wet);
  bool get isMonochrome => has(BoardTextureKind.monochrome);
  bool get isDynamic => has(BoardTextureKind.dynamicBoard);
  bool get isStatic => has(BoardTextureKind.staticBoard);
  bool get isPaired => has(BoardTextureKind.paired);

  /// True when a flush is already possible.
  bool get flushPossible => suitedness == Suitedness.monotone;

  /// True when one more card of the right suit completes a flush.
  bool get flushDrawLive => suitedness == Suitedness.twoTone;

  /// Ace-high — the range-advantage board par excellence for a preflop raiser.
  bool get aceHigh => highRank == 14;

  /// Low boards, which connect much better with a caller's range than with a
  /// preflop raiser's.
  bool get lowBoard => highRank <= 9;

  /// The textures worth naming, in the order a commentator would say them:
  /// structural facts first (paired, monochrome), then dry/wet, then
  /// static/dynamic.
  List<BoardTextureKind> get orderedKinds => [
    for (final k in const [
      BoardTextureKind.paired,
      BoardTextureKind.monochrome,
      BoardTextureKind.dry,
      BoardTextureKind.wet,
      BoardTextureKind.staticBoard,
      BoardTextureKind.dynamicBoard,
    ])
      if (has(k)) k,
  ];

  /// A phrase for the board, e.g. "paired, dry and static, king-high" — the
  /// kind of thing a commentator leads with.
  String get description {
    final labels = [for (final k in orderedKinds) k.label];
    final texture = labels.isEmpty
        ? 'middling'
        : labels.length == 1
        ? labels.first
        : '${labels.sublist(0, labels.length - 1).join(', ')} and ${labels.last}';
    return '$texture, ${_rankWord(highRank)}-high';
  }

  /// The draws this board hands out, as a phrase, or null when there is nothing
  /// meaningful to chase.
  String? get drawPhrase {
    final bits = <String>[];
    if (flushPossible) {
      bits.add('a flush already out there');
    } else if (flushDrawLive) {
      bits.add('a flush draw');
    }
    if (connectedness == Connectedness.connected) {
      bits.add('open-enders');
    } else if (connectedness == Connectedness.semiConnected) {
      bits.add('gutshots');
    }
    if (bits.isEmpty) return null;
    return bits.length == 1 ? bits.first : '${bits.first} and ${bits.last}';
  }

  /// Whether this board structurally favours the preflop aggressor (high,
  /// disconnected boards) or the caller (low, connected ones).
  ///
  /// Returns a value in [-1, 1]: positive favours the raiser.
  double get raiserAdvantage {
    var score = 0.0;
    if (aceHigh) score += 0.5;
    if (broadwayCount >= 2) score += 0.3;
    if (lowBoard) score -= 0.4;
    if (connectedness == Connectedness.connected) score -= 0.25;
    if (suitedness == Suitedness.monotone) score -= 0.15;
    return score.clamp(-1.0, 1.0);
  }

  /// Describes how the newest card changed things, against an earlier street's
  /// texture — the language of turn and river commentary.
  String changeFrom(BoardTexture previous) {
    final newCard = cards.length > previous.cards.length ? cards.last : null;
    if (newCard == null) return 'the board pairs up';

    if (trips && !previous.trips) return 'the board trips up';
    if (isPaired && !previous.isPaired) {
      return 'the board pairs, which counterfeits a lot of two-pair hands';
    }
    if (flushPossible && !previous.flushPossible) {
      return 'the flush gets there';
    }
    if (flushDrawLive && !previous.flushDrawLive) {
      return 'a flush draw arrives and the board turns dynamic';
    }
    if (connectedness == Connectedness.connected &&
        previous.connectedness != Connectedness.connected) {
      return 'the board connects and straights come into play';
    }
    if (newCard.rank.value >= 12 && newCard.rank.value > previous.highRank) {
      return 'an overcard peels off — a genuine scare card for one-pair hands';
    }
    if (previous.isDynamic && isStatic) {
      return 'a card that dries the board right out';
    }
    if (newCard.rank.value <= 6) return 'a low blank';
    return 'a relative brick';
  }

  static Connectedness _connectedness(List<int> sortedRanks) {
    final uniq = sortedRanks.toSet().toList()..sort();
    if (uniq.length < 2) return Connectedness.disconnected;

    // Three cards inside a five-rank window makes straights very live.
    for (var i = 0; i + 2 < uniq.length; i++) {
      if (uniq[i + 2] - uniq[i] <= 4) return Connectedness.connected;
    }
    // Wheel-side: treat the ace as a 1 for connectivity.
    if (uniq.contains(14)) {
      final wheel = [1, ...uniq.where((r) => r != 14)]..sort();
      for (var i = 0; i + 2 < wheel.length; i++) {
        if (wheel[i + 2] - wheel[i] <= 4) return Connectedness.connected;
      }
    }
    for (var i = 0; i + 1 < uniq.length; i++) {
      if (uniq[i + 1] - uniq[i] <= 3) return Connectedness.semiConnected;
    }
    return Connectedness.disconnected;
  }

  static String _rankWord(int v) => switch (v) {
    14 => 'ace',
    13 => 'king',
    12 => 'queen',
    11 => 'jack',
    10 => 'ten',
    9 => 'nine',
    8 => 'eight',
    7 => 'seven',
    6 => 'six',
    5 => 'five',
    4 => 'four',
    3 => 'three',
    _ => 'deuce',
  };
}
