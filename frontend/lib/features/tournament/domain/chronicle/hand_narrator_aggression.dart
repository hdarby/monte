part of 'hand_narrator.dart';

/// Reports a re-raise on a street. Classifies it by whether the raiser
/// actually holds the best hand — we can see every card, so there is no excuse
/// for calling top pair "a bluff", which a rank threshold used to do.
List<String> _raiseRead(
  _HandContext ctx,
  ReplayStreet street,
  BoardTexture? tex,
) {
  final raise = ctx.raiseOn(street.round);
  if (raise == null) return const [];
  final rs = ctx.seatFor(raise.playerId);
  if (rs == null) return const [];

  final best = ctx.hasBestHand(rs, street);
  final outs = ctx.outsFor(rs, street);
  final dynamic_ = tex?.isDynamic ?? false;

  if (best) {
    return [
      '${raise.name} raises to ${ctx.bb(raise.amount)} with '
          '${ctx.made(rs, street)} — the best hand out there right now, so '
          'this is a value raise. '
          '${dynamic_ ? 'On a dynamic board it doubles as protection against everything still drawing.' : 'On a static board it is purely about getting money in while they still have a hand they can call with.'}',
    ];
  }
  if (outs >= 6) {
    return [
      '${raise.name} raises to ${ctx.bb(raise.amount)} with '
          '${ctx.holding(rs)} — a semi-bluff raise. $outs outs plus the fold '
          'equity is a genuinely strong combination, and it takes the betting '
          'lead away from someone who has already shown they like their hand.',
    ];
  }
  return [
    '${raise.name} raises to ${ctx.bb(raise.amount)} with '
        '${ctx.holding(rs)}, which is behind. That is a bluff raise and it '
        'needs a lot of folds to show a profit — raising is the most expensive '
        'way to find out you are beaten.',
  ];
}

// ---- Aggression & bluff evaluation ---------------------------------------

/// Reads a bet or raise: value, semi-bluff, or pure bluff — and whether the
/// spot justified it.
List<String> _aggressionRead(
  _HandContext ctx,
  ReplayAction bet,
  ReplayStreet street,
  BoardTexture tex,
) {
  final out = <String>[];
  final seat = ctx.seatFor(bet.playerId);
  if (seat == null) return out;

  final made = ctx.rankOn(seat, street);
  final sizing = _sizingWord(bet.potFraction);
  // "Value" means actually being ahead — we can see the cards, so say so.
  final isValue = ctx.hasBestHand(seat, street);
  final drawing = ctx.isSemiBluff(seat, street);

  if (isValue && made != null && made.index >= HandRank.twoPair.index) {
    out.add(
      '${bet.name} bets ${ctx.bb(bet.amount)} — $sizing — with '
      '${ctx.made(seat, street)}. That is a clean value bet. '
      '${tex.isDynamic ? 'On a dynamic board build it now: the hand is at peak value this second and the river may well take it away.' : 'On a static board there is no rush, so the goal is picking the size that gets called by the most worse hands over three streets.'}',
    );
  } else if (isValue) {
    out.add(
      '${bet.name} bets $sizing with ${ctx.made(seat, street)}. '
      '${tex.isDynamic ? 'Betting one pair on a dynamic board is right — you are charging the draws and denying equity that is genuinely worth denying.' : 'One pair on a static board is a thin bet; it mostly folds out the hands you beat and gets called by the hands that beat you.'}',
    );
  } else if (made != null && made.index >= HandRank.twoPair.index) {
    // Strong, but behind. Betting here is not a bluff — it is value-betting
    // into a better hand, which is how good players lose big pots.
    out.add(
      '${bet.name} bets $sizing with ${ctx.made(seat, street)}, which looks '
      'like a value bet and is actually second best. This is the hand class '
      'that costs the most money — too strong to fold, not strong enough to '
      'win, and betting it just builds the pot they are going to lose.',
    );
  } else if (drawing) {
    final outs = ctx.outsFor(seat, street);
    out.add(
      '${bet.name} semi-bluffs $sizing with ${ctx.holding(seat)}. That is the '
      'right kind of bluff: ${outs > 0 ? '$outs outs to improve, ' : ''}'
      'so you win outright when they fold and you still have a hand when they '
      'do not. Semi-bluffing is where aggression is close to free.',
    );
  } else if (made != null && made.index >= HandRank.pair.index) {
    out.add(
      '${bet.name} bets $sizing with ${ctx.made(seat, street)} and is behind. '
      'Betting a pair that is already beaten is the classic way to turn a '
      'small loss into a big one — this is a check.',
    );
  } else {
    out.add(_bluffVerdict(ctx, bet, seat, tex));
  }
  return out;
}

/// The "time and a place" judgement on a pure bluff: fold equity, texture,
/// position, and how many players still have to be got through.
String _bluffVerdict(
  _HandContext ctx,
  ReplayAction bet,
  ReplaySeat seat,
  BoardTexture tex,
) {
  final opponents = ctx.liveOpponentsAt(bet);
  final inPosition = seat.position.isLate;
  final tellsAStory = tex.raiserAdvantage > 0.15 || tex.aceHigh;
  final bigEnough = bet.potFraction >= 0.55;

  final against = <String>[];
  if (opponents > 1) {
    against.add(
      'there are still $opponents players to get through, and every extra '
      'player roughly halves the chance everyone folds',
    );
  }
  if (!tellsAStory) {
    against.add(
      'the board does not fit the story — their range does not credibly have '
      'the hands they are representing here',
    );
  }
  if (!bigEnough) {
    against.add(
      'the size is too small to fold out anything that has a pair, which is '
      'the only thing they need to fold',
    );
  }
  if (!inPosition) {
    against.add(
      'doing it out of position means no free showdown and no information',
    );
  }

  if (against.isEmpty) {
    return '${bet.name} fires ${ctx.bb(bet.amount)} with ${ctx.holding(seat)} '
        '— a pure bluff, and a well-chosen one. Heads-up, in position, on a '
        'board that belongs to their range, at a size that puts a real '
        'decision on the opponent. That is the time and the place, and I have '
        'no problem with it even though it is nothing.';
  }
  return '${bet.name} bluffs ${ctx.bb(bet.amount)} with ${ctx.holding(seat)}, '
      'and I do not love it: ${_join(against)}. The instinct to apply '
      'pressure is fine — a bluff just needs all of those boxes ticked, not '
      'one of them.';
}
