part of 'hand_narrator.dart';

// ---- Closing summary ------------------------------------------------------

List<String> _summary(_HandContext ctx) {
  final r = ctx.replay;
  final out = <String>[];

  final size = formatChipsWithBb(r.pot, r.bigBlind);
  final won = r.winnerHand.toLowerCase();
  final lost = r.loserHand.toLowerCase();
  final eq = ctx.winnerEquityWhenAllIn;
  if (eq != null && eq < 0.25) {
    out.add(ctx.voice.pick([
      'The money went in bad and got there. ${r.winnerName} was a '
          '${_pct(1 - eq)}% underdog to ${r.loserName}\'s $lost when the '
          'chips went in and spiked it anyway — a $size pot decided by the '
          'deck, not by anybody\'s decision-making.',
      'That is a cooler with a bad ending for ${r.loserName}: a '
          '${_pct(1 - eq)}% favorite when it all went in, and the board '
          'obliged the other side. $size to ${r.winnerName}, none of it '
          'earned.',
      '${r.winnerName} needed help and got it — only ${_pct(eq)}% to win it '
          'when the chips went in. $lost was in front until the deck '
          'intervened, and $size changes hands on a card.',
    ], 53));
  } else if (eq != null && eq < 0.45) {
    out.add(ctx.voice.pick([
      '${r.loserName} had a real edge here — ${_pct(1 - eq)}% to '
          '${r.winnerName}\'s ${_pct(eq)}% when the money went in — and it '
          'just did not hold. That happens; $size to ${r.winnerName} either '
          'way.',
      'Not a cooler, just an edge that missed: ${r.loserName} was the '
          '${_pct(1 - eq)}% favorite when it all went in and lost the $size '
          'pot regardless. Nothing to fix, just a card that did not '
          'cooperate.',
    ], 54));
  } else if (eq != null && eq <= 0.55) {
    out.add(ctx.voice.pick([
      'That is a genuine coinflip — ${_pct(eq)}/${_pct(1 - eq)} when the '
          'chips went in — and it landed for ${r.winnerName}. $size in the '
          'middle, and there is nothing to review here.',
      '$size on a real coinflip: ${r.winnerName} was barely the ${_pct(eq)}% '
          'side of it and it went their way. Call it luck and move on.',
    ], 55));
  } else if (eq != null && eq < 0.75) {
    out.add(ctx.voice.pick([
      '${r.winnerName} had a real edge — ${_pct(eq)}% when the money went '
          'in — and it held. $size collected, deserved but not a lock.',
      'A fair flip, weighted ${r.winnerName}\'s way at ${_pct(eq)}%, and it '
          'came home for $size.',
    ], 56));
  } else if (eq != null) {
    out.add(ctx.voice.pick([
      '$size in the middle and ${r.winnerName}\'s $won holds against $lost '
          'as a ${_pct(eq)}% favorite when the chips went in. The best of '
          'it, and it stayed there.',
      'Stacks in as a ${_pct(eq)}% favorite, and it holds: $won beats $lost '
          'for $size. Nothing to review — that is the good end of a flip.',
      '${r.winnerName} gets it in ahead — ${_pct(eq)}% — and stays ahead. '
          '$won over $lost, $size shipped.',
    ], 59));
  } else if (r.allIn) {
    out.add(ctx.voice.pick([
      '$size in the middle and ${r.winnerName}\'s $won holds against $lost. '
          'The chips went in with the best of it and stayed there, which is '
          'all you can ask.',
      'Stacks in, and it holds: $won beats $lost for $size. Nothing to '
          'review — that is the good end of a flip.',
      '${r.winnerName} gets it in ahead and stays ahead. $won over $lost, '
          '$size shipped.',
    ], 59));
  } else if (!r.reachedRiver) {
    out.add(ctx.voice.pick([
      '${r.winnerName} takes it down before showdown for $size. Pots like '
          'this are where tournaments are quietly won — no cards had to '
          'cooperate, somebody just applied pressure at a moment nobody '
          'could call.',
      'No showdown needed. ${r.winnerName} picks up $size by betting at a '
          'spot the other hand simply could not continue in.',
      'That is $size collected without ever turning a card over — the least '
          'glamorous and most reliable way to build a stack.',
    ], 61));
  } else {
    out.add(ctx.voice.pick([
      '${r.winnerName} gets there with $won for $size, beating '
          '${r.loserName}\'s $lost.',
      '$size to ${r.winnerName}: $won was good, and ${r.loserName}\'s $lost '
          'pays it off.',
      'It goes to showdown and ${r.winnerName} shows $won for $size, with '
          '${r.loserName} second best holding $lost.',
    ], 67));
  }

  final pivot = ctx.pivotStreet();
  if (pivot != null) {
    out.add(
      'The hand turned on the ${pivot.name.toLowerCase()} — that is where the '
      'pot went from routine to ${formatChipsWithBb(pivot.potAfter, r.bigBlind)} '
      'and everybody\'s decisions suddenly got expensive. If you are '
      'reviewing this hand, that is the street to study.',
    );
  }

  final winner = ctx.seatByName(r.winnerName);
  if (winner != null && !r.suckout && winner.net >= r.bigBlind * 20) {
    final streetsBet = ctx.aggressiveStreetsFor(winner.playerId);
    out.add(
      streetsBet >= 2
          ? 'Full marks to ${winner.name} for the extraction — '
                '${formatChipsWithBb(winner.net, r.bigBlind)} of profit across '
                '$streetsBet streets of betting. The pot never got ahead of '
                'the hand and never stalled out either.'
          : '${winner.name} banks ${formatChipsWithBb(winner.net, r.bigBlind)}, '
                'but let the opponent do all the betting. When you have the '
                'best hand, waiting to be paid is not the same as getting '
                'paid — there was more in this pot than they took.',
    );
  }

  final looseCount = ctx.flopSeats.where(ctx.wasLooseEntry).length;
  if (looseCount > 0) {
    out.add(
      'Worth noting that $looseCount of the players in this pot should not '
      'have been in it at all. Most big pots are not lost on the river — they '
      'are lost the moment somebody enters with a hand that cannot stand '
      'pressure.',
    );
  }
  return out;
}

// ---- Per-player verdicts --------------------------------------------------

List<PlayerVerdict> _verdicts(_HandContext ctx) => [
  for (final seat in ctx.flopSeats)
    () {
      final (line, grade) = _verdictFor(ctx, seat);
      return PlayerVerdict(
        name: seat.name,
        position: seat.position,
        line: line,
        grade: grade,
      );
    }(),
];

(String, VerdictGrade) _verdictFor(_HandContext ctx, ReplaySeat seat) {
  final r = ctx.replay;

  if (seat.won) {
    final winEq = ctx.winnerEquityWhenAllIn;
    if (winEq != null && winEq < 0.25) {
      return (
        'got there — only ${_pct(winEq)}% to win it when the chips went '
        'in. The chips are real but the decision was not — do not take the '
        'wrong lesson from a hand you were drawing dead-ish in.',
        VerdictGrade.unlucky,
      );
    }
    if (winEq != null && winEq < 0.45) {
      return (
        'got there against a real edge — ${_pct(1 - winEq)}% the other way '
        'when it all went in — and it just missed for the other side '
        'instead. That is not a bad beat to study, it is a card that '
        'sometimes falls your way.',
        VerdictGrade.unlucky,
      );
    }
    if (winEq == null && r.suckout) {
      return (
        'got there. The chips are real but the decision was not — do not take '
        'the wrong lesson from a hand you were drawing dead-ish in.',
        VerdictGrade.unlucky,
      );
    }
    final streetsBet = ctx.aggressiveStreetsFor(seat.playerId);
    if (streetsBet >= 3) {
      return (
        'played it perfectly — $streetsBet streets of betting with '
        '${ctx.finalHand(seat)}, each one sized so the call kept coming. '
        'That is the whole game in one hand.'
        '${_moveTag(ctx, seat, aggressive: true)}',
        VerdictGrade.excellent,
      );
    }
    if (!r.reachedRiver) {
      return (
        'took the aggressive line and got the fold. No showdown needed, no '
        'cards required — the best kind of pot to win.'
        '${_moveTag(ctx, seat, aggressive: true)}',
        VerdictGrade.good,
      );
    }
    return (
      'won it with ${ctx.finalHand(seat)}, though a touch passively — there '
      'was at least one more bet available on this hand and it was left on '
      'the table.',
      VerdictGrade.good,
    );
  }

  if (seat.foldedOn != null) {
    final street = seat.foldedOn!.name;
    if (ctx.wasBluffedOut(seat)) {
      return (
        'was bluffed off the best hand on the $street. The '
        'fold is understandable in isolation, but that is precisely the spot '
        'where you have to look up somebody who has been firing every '
        'street.',
        VerdictGrade.questionable,
      );
    }
    if (ctx.wasLooseEntry(seat)) {
      return (
        'never should have been in the pot from ${seat.position.phrase} with '
        '${ctx.holding(seat)}, and paid for the privilege before finding the '
        'fold button on the $street.',
        VerdictGrade.poor,
      );
    }
    return (
      'got away from it cleanly on the $street — read the strength, saved the '
      'chips, nothing to fix. Good, disciplined folding is invisible and it '
      'is worth a fortune.'
      '${_moveTag(ctx, seat, aggressive: false)}',
      VerdictGrade.good,
    );
  }

  if (seat.name == r.loserName) {
    final eq = r.equityWhenAllIn?[seat.playerId];
    if (eq != null && eq >= 0.75) {
      return (
        'did everything right and lost anyway — got it in with '
        '${ctx.finalHand(seat)} as a ${_pct(eq)}% favourite and got run '
        'down. Bank the decision and ignore the result.',
        VerdictGrade.unlucky,
      );
    }
    if (eq != null && eq >= 0.55) {
      return (
        'had the better of it with ${ctx.finalHand(seat)} — ${_pct(eq)}% '
        'when it all went in — and lost anyway. A real edge, and it did '
        'not hold; nothing to review.',
        VerdictGrade.unlucky,
      );
    }
    if (eq == null && r.suckout) {
      return (
        'did everything right and lost anyway — got it in with '
        '${ctx.finalHand(seat)} as a clear favourite and got run down. Bank '
        'the decision and ignore the result.',
        VerdictGrade.unlucky,
      );
    }
    if (eq != null) {
      return (
        'got it in as close to a coinflip as it gets — ${_pct(eq)}% with '
        '${ctx.finalHand(seat)} — and lost it. That is a coinflip landing '
        'the other way, not a bad beat; there is nothing here to review.',
        VerdictGrade.standard,
      );
    }
  }

  final rank = seat.finalRank;
  if (rank != null && rank.index <= HandRank.pair.index) {
    // Betting a weak hand into a caller is a failed bluff, not a crying call
    // — completely different mistakes, so do not conflate them.
    if (ctx.wasLastAggressor(seat)) {
      return (
        'ran ${ctx.finalHand(seat)} into a hand that was never folding. The '
        'idea of turning a busted draw into a bluff is sound, but the story '
        'has to be one the opponent can believe, and this one was not.'
        '${_moveTag(ctx, seat, aggressive: true)}',
        VerdictGrade.questionable,
      );
    }
    return (
      'paid it off with ${ctx.finalHand(seat)} — talked into a call that '
      'only ever beats a bluff. That is the most '
      'expensive habit in poker.'
      '${_moveTag(ctx, seat, aggressive: false)}',
      VerdictGrade.questionable,
    );
  }
  return (
    'lost with ${ctx.finalHand(seat)}. Second best is second best, and there '
    'was no obvious place to get away from it — this one just costs '
    'money.',
    VerdictGrade.standard,
  );
}

/// The moves that show up on an aggressive line vs. a passive/defensive
/// one — used to keep a personality callout honest: never "that is the
/// Sticky_Showdown in them" on a hand where they bet, never "that is the
/// Slow_Play_Trap" on a hand where they folded.
const _aggressiveMoveIds = {
  'Slow_Play_Trap', 'Check_Raise_Merchant', 'Float_And_Take_Away',
  'Bubble_Predator', 'Limp_Reraise', 'Leverage_Pressure',
  'Positional_Warfare', 'Geometric_Overbet_Execution', 'Soul_Read',
  'Tilt_Blowup',
};
const _passiveMoveIds = {
  'Sticky_Showdown', 'Underbluff_Exploit', 'Tilt_Chase', 'Tilt_Shutdown',
};

/// A closing callout naming a move that actually fired for [seat] this
/// hand — a true, hand-specific fact — or '' when none did.
///
/// This replaces a blind splice of the profile's archetype label onto every
/// verdict regardless of fit (a disciplined fold from a "Loose Aggressive"
/// seat used to read as "very much a Loose Aggressive move," which is
/// backwards). No move fired this hand ⇒ no personality remark at all — a
/// disciplined fold needs no character commentary, and forcing one is
/// exactly the "shallow and often wrong" failure mode this replaces.
String _moveTag(_HandContext ctx, ReplaySeat seat, {required bool aggressive}) {
  final pool = aggressive ? _aggressiveMoveIds : _passiveMoveIds;
  final fired = ctx.movesFiredBy(seat.playerId);
  final match = fired.where(pool.contains).firstOrNull;
  if (match == null) return '';
  return ' That is the $match in them talking.';
}
