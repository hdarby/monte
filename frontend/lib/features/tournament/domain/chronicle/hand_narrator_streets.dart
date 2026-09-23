part of 'hand_narrator.dart';

/// A street dealt with no action left to take: everyone is all-in and the
/// cards are being run out. Says what the card is and, more usefully, whether
/// it changed who is winning.
List<String> _runout(_HandContext ctx, ReplayStreet street) {
  final out = <String>[];
  final tex = ctx.textureAfter(street);
  final board = ctx.boardOf(street);
  final leader = ctx.leaderOn(street);
  final previous = ctx.previousLeader(street);

  final texture = tex != null ? ', ${tex.description}' : '';
  if (street.round == BettingRound.flop) {
    out.add(ctx.voice.pick([
      '$board — the money went in before the flop, so this is a runout'
          '$texture.',
      '$board. Stacks were already in the middle preflop; all that is left '
          'is to deal it out$texture.',
      'No further betting — everyone committed preflop. The flop comes '
          '$board$texture.',
      '$board. Cards on their backs, and this one plays itself from here'
          '$texture.',
    ], 11));
  } else {
    final label = street.round == BettingRound.turn ? 'turn' : 'river';
    out.add(ctx.voice.pick([
      '$board.',
      'The $label brings it to $board.',
      'Running it out: $board.',
      '$board on the $label.',
    ], street.round.index * 7));
  }

  if (leader == null) {
    return out;
  }
  final name = leader.name;
  final made = ctx.made(leader, street);
  if (previous != null && previous.playerId != leader.playerId) {
    out.add(ctx.voice.pick([
      'That card flips it — $name now has $made and takes the lead from '
          '${previous.name}.',
      'And that changes everything: $name gets there with $made, leaving '
          '${previous.name} drawing.',
      '${previous.name} was in front until that one. $name has $made now.',
    ], street.round.index * 13));
  } else if (street.round == BettingRound.river) {
    out.add(ctx.voice.pick([
      '$name wins it with $made.',
      'It holds. $name takes it down with $made.',
      'No change — $made is good for $name.',
    ], 23));
  } else {
    out.add(ctx.voice.pick([
      '$name is still in front with $made.',
      'That is a blank. $name keeps the lead with $made.',
      'Nothing changes there — $name holds on with $made.',
    ], street.round.index * 17));
  }
  return out;
}

// ---- Preflop --------------------------------------------------------------

/// Who came in, at what price, and who had no business being there.
List<String> _preflop(_HandContext ctx, ReplayStreet street) {
  final out = <String>[];

  final open = ctx.firstAggressiveOn(BettingRound.preflop);
  if (open != null) {
    final seat = ctx.seatFor(open.playerId);
    out.add(
      '${open.name} opens to ${ctx.bb(open.amount)} from '
      '${open.position.phrase}'
      '${seat != null ? ' with ${ctx.holding(seat)}' : ''} — '
      '${_openVerdict(ctx, open)}',
    );
  } else {
    out.add(
      'Nobody raised — a limped pot, which is how you end up guessing on '
      'every later street with no range advantage to lean on.',
    );
  }

  // A 3-bet completely changes the shape of the hand, so call it out.
  final threeBet = ctx.raiseOn(BettingRound.preflop);
  if (threeBet != null) {
    final s = ctx.seatFor(threeBet.playerId);
    out.add(
      '${threeBet.name} 3-bets to ${ctx.bb(threeBet.amount)} from '
      '${threeBet.position.phrase}'
      '${s != null ? ' with ${ctx.holding(s)}' : ''}. '
      '${s != null && ctx.preflopPercentile(s) <= 6 ? 'That is the top of the range and exactly the hand you want doing this — it gets value from worse and folds out the hands with equity against you.' : 'That is a 3-bet as a bluff, and it needs the opener to be wide enough to fold. Aggressive, but not automatic.'}',
    );
  }

  // Every entry gets a verdict — the read only a commentator with all the
  // cards can give, and usually where the hand was really decided.
  for (final seat in ctx.flopSeats) {
    out.add(ctx.entryVerdict(seat));
  }

  // Price and depth context for the pot that is about to be played.
  final spr = ctx.sprAfterPreflop();
  if (spr != null) {
    out.add(
      'Going to the flop the pot is ${ctx.bb(street.potAfter)} with an SPR of '
      '${spr.toStringAsFixed(1)} — '
      '${spr < 3 ? 'that is a commitment-threshold pot. Top pair is going to be very hard to fold, so decide now whether you are stacking off.' : spr < 7 ? 'a medium SPR, where one pair is worth a street or two but not a stack.' : 'deep enough that implied odds matter and one pair is a bluff-catcher, not a stack-off hand.'}',
    );
  }
  return out;
}

/// Judges the opening raise: right hand for the seat, right size for the
/// stack depth?
String _openVerdict(_HandContext ctx, ReplayAction open) {
  final seat = ctx.seatFor(open.playerId);
  if (seat == null) return 'a standard open.';

  final stack = seat.stackBb(ctx.replay.bigBlind);
  if (stack <= 20) {
    return 'at ${stack.round()}bb that is really a shove-or-fold stack, and '
        'opening small just invites the blinds to play back at a price they '
        'cannot refuse.';
  }
  if (ctx.wasLooseEntry(seat)) {
    return 'that is too wide for the seat. From ${open.position.phrase} you '
        'want hands that flop well and can stand a 3-bet, and '
        '${ctx.holding(seat)} is neither — it is in the bottom half of what '
        'should even be opening there.';
  }
  if (open.position.isLate) {
    return 'standard and correct. Late position is exactly where you widen '
        'out and put the blinds to a decision with position guaranteed for '
        'the rest of the hand.';
  }
  return 'a solid, honest open from an early seat — the kind of hand that '
      'still plays well when it gets called.';
}

// ---- Flop -----------------------------------------------------------------

/// Texture first, then what everyone actually flopped, then whether the
/// action fits any of it.
List<String> _flop(_HandContext ctx, ReplayStreet street) {
  final out = <String>[];
  final tex = ctx.textureAfter(street);
  if (tex == null) return out;

  final draws = tex.drawPhrase;
  final advantage = tex.raiserAdvantage;
  out.add(
    '${ctx.boardOf(street)} — ${tex.description}'
    '${draws != null ? ', with $draws out there' : ''}. '
    '${advantage > 0.25 ? 'That board belongs to the raising range: high cards connect with the hands that opened, not the hands that called.' : advantage < -0.25 ? 'That texture connects far better with the calling range than the preflop raiser — the caller has all the small pairs and suited connectors here.' : 'Neither range smashes that board, which usually means a lot of small bets and a lot of folding.'}',
  );

  // Static vs dynamic drives every sizing decision on this street.
  out.add(
    tex.isDynamic
        ? 'This is a dynamic board — the winner is very likely to change by '
              'the river, so equity denial is worth real money here.'
        : tex.isStatic
        ? 'This is a static board — whoever is ahead now is almost certainly '
              'still ahead on the river, so protection is worth very little '
              'and thin value is worth a lot.'
        : 'The board sits between static and dynamic; enough can change that '
              'you cannot get too attached, but not enough to panic.',
  );

  // What everyone is actually working with.
  for (final line in ctx.holdingReads(street)) {
    out.add(line);
  }

  final bet = ctx.firstAggressiveOn(BettingRound.flop);
  if (bet == null) {
    final verdict = tex.isStatic
        ? 'that is defensible — nothing is getting outdrawn, so keeping the '
            'weak hands in has value'
        : 'that is a mistake; every turn card changes who is winning and a '
            'free one is the last thing you want to give';
    final kind = tex.isStatic ? 'static' : 'dynamic';
    out.add(ctx.voice.pick([
      'Checked through. On a $kind board $verdict.',
      'Nobody wanted it. That is a $kind board, and $verdict.',
      'Both players tap the table. $kind board — $verdict.',
      'A free card goes out. On this $kind texture $verdict.',
    ], 31));
    return out;
  }

  out.addAll(_aggressionRead(ctx, bet, street, tex));

  out.addAll(_raiseRead(ctx, street, tex));
  out.addAll(ctx.callPriceReads(street));
  return out;
}

// ---- Turn -----------------------------------------------------------------

/// Narrow the ranges by what the flop action said, then judge the bluffs.
List<String> _turn(_HandContext ctx, ReplayStreet street) {
  final out = <String>[];
  final tex = ctx.textureAfter(street);
  final prev = ctx.textureBefore(street);
  if (tex == null) return out;

  final change = prev != null ? tex.changeFrom(prev) : tex.description;
  out.add(ctx.voice.pick([
    '${ctx.boardOf(street)} — $change. The board reads ${tex.description} '
        'now.',
    'The turn: ${ctx.boardOf(street)}. $change, leaving ${tex.description}.',
    '${ctx.boardOf(street)} on fourth street — $change. That is '
        '${tex.description} to play against.',
  ], 41));

  // Range narrowing from the flop action — the heart of turn strategy.
  // Whoever put in the *last* aggressive action on the flop is the one with
  // the lead going into the turn — and they must not also appear in the list
  // of players who called them.
  final flopAgg = ctx.aggressorOn(BettingRound.flop);
  final callers = ctx
      .callersOn(BettingRound.flop)
      .where((c) => c.playerId != flopAgg?.playerId)
      .toList();
  if (flopAgg != null && callers.isNotEmpty) {
    out.add(
      '${_names(callers.map((c) => c.name))} calling the flop narrows things '
      'a long way. That range is pairs that want another card and draws that '
      'have a price — it is almost never total air, because air folds to a '
      'flop bet. So ${flopAgg.name} needs a reason to fire again beyond '
      'momentum.',
    );
  } else if (flopAgg == null) {
    out.add(
      'With the flop checked through, nobody has told the truth about their '
      'hand yet. Both ranges are still uncapped, which makes this turn much '
      'harder to bluff into.',
    );
  }

  for (final line in ctx.holdingReads(street)) {
    out.add(line);
  }

  final bet = ctx.firstAggressiveOn(BettingRound.turn);
  if (bet == null) {
    out.add(
      'Checked round. With the pot at ${ctx.bb(street.potAfter)} that is both '
      'players admitting they are in bluff-catch mode and would rather see a '
      'cheap river than build a pot they cannot defend.',
    );
    return out;
  }

  out.addAll(_aggressionRead(ctx, bet, street, tex));
  out.addAll(_raiseRead(ctx, street, tex));
  out.addAll(ctx.callPriceReads(street));
  return out;
}

// ---- River ----------------------------------------------------------------

/// The payoff street: no more equity, only value and bluffs.
List<String> _river(_HandContext ctx, ReplayStreet street) {
  final out = <String>[];
  final tex = ctx.textureAfter(street);
  final prev = ctx.textureBefore(street);

  if (tex != null) {
    out.add(
      '${ctx.boardOf(street)} — '
      '${prev != null ? tex.changeFrom(prev) : tex.description}. '
      'No more cards, so every chip from here is either value or a bluff.',
    );
  }

  for (final line in ctx.holdingReads(street)) {
    out.add(line);
  }

  final bet = ctx.firstAggressiveOn(BettingRound.river);
  if (bet == null) {
    if (street.actions.isNotEmpty) {
      out.add(ctx.voice.pick([
        'Checked to showdown. Somebody left a value bet out there — there is '
            'nothing left to protect against on the river, so if you beat '
            'their calling range you are obliged to bet.',
        'It goes check-check. That is money left on the table: no card can '
            'hurt you now, so beating their calling range means betting it.',
        'They both give up on the end. Protection is worth nothing here — if '
            'worse hands call, that is a bet you have to make.',
      ], 37));
    }
    return out;
  }

  final seat = ctx.seatFor(bet.playerId);
  if (seat == null) return out;
  final made = ctx.rankOn(seat, street);
  final sizing = _sizingWord(bet.potFraction);

  if (ctx.hasBestHand(seat, street)) {
    out.add(
      '${bet.name} bets $sizing with ${ctx.made(seat, street)} — the best hand, '
      'so this is purely about picking a size they will actually pay.',
    );
  } else if (made != null && made.index >= HandRank.twoPair.index) {
    out.add(
      '${bet.name} bets $sizing with ${ctx.made(seat, street)}. Strong, but '
      'second best here — that is the hand class that loses the most money on '
      'a river, because it is too good to fold and not good enough to win.',
    );
  } else {
    out.add(
      '${bet.name} turns ${ctx.holding(seat)} into a bluff. '
      '${bet.potFraction >= 0.7 ? 'The size is right — a river bluff has to be big enough to make a bluff-catcher genuinely uncomfortable, and this one is.' : 'The size is the problem: too small to fold out a pair, and a pair was the only hand ever folding.'}',
    );
  }

  out.addAll(_raiseRead(ctx, street, tex));

  // The call, and whether it was right.
  final call = street.actions
      .where((a) => a.type == ActionType.call)
      .firstOrNull;
  if (call != null) {
    final cs = ctx.seatFor(call.playerId);
    if (cs != null) {
      final odds = ctx.potOddsFor(call, street);
      final cr = ctx.rankOn(cs, street);
      final weak = cr == null || cr.index <= HandRank.pair.index;
      out.add(
        '${call.name} calls ${ctx.bb(call.toCall)} with '
        '${ctx.made(cs, street)}'
        '${odds != null ? ', getting ${odds.toStringAsFixed(0)}% — they need to be right that often' : ''}. '
        '${weak ? 'You have to ask what worse hand is ever betting there. Against a range that is mostly value, that is a call with the wrong half of your own range.' : 'Good call — it beats the bluffs and enough of the thin value bets to show a profit.'}',
      );
    }
  }
  return out;
}
