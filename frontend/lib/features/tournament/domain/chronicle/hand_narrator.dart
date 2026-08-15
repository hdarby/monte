import 'package:monte/core/domain/ai/preflop_ranges.dart';
import 'package:monte/core/domain/engine/actions.dart';
import 'package:monte/core/domain/engine/board_texture.dart';
import 'package:monte/core/domain/engine/card.dart';
import 'package:monte/core/domain/engine/game.dart' show BettingRound;
import 'package:monte/core/domain/engine/hand_evaluator.dart';
import 'package:monte/core/domain/engine/hand_strength.dart';
import 'package:monte/core/util/format.dart';
import 'package:monte/features/tournament/domain/chronicle/hand_replay.dart';

/// Generates Bart-Hanson-style commentary over a completed [HandReplay]: a full
/// read on every street, then a closing take with a verdict on each player.
///
/// It is a *commentator*, not a solver. It works from facts the replay already
/// carries — hole cards, board, exact action, positions, stack depths, and each
/// player's style — and applies standard strategic reasoning: board texture,
/// range and nut advantage, pot odds, stack-to-pot ratio, exact outs, fold
/// equity, and whether a bluff had a story behind it.
///
/// Because it can see every hand, it talks like TV commentary: it will call out
/// a loose preflop entry the player themselves could not have known was bad, and
/// it counts a drawing player's outs exactly rather than guessing.
///
/// Deliberately verbose — this is a training tool, so it would rather say one
/// thing too many than leave a spot unexplained.
///
/// Pure and deterministic: same replay in, same words out. No Flutter, no I/O.
class HandNarrator {
  const HandNarrator._();

  /// Returns [replay] with per-street commentary, a closing take, and one
  /// verdict per player who saw the flop.
  static HandReplay narrate(HandReplay replay) {
    final ctx = _HandContext(replay);
    final streets = [
      for (final s in replay.streets) s.withCommentary(_forStreet(ctx, s)),
    ];
    return replay.copyWith(
      streets: streets,
      commentary: _summary(ctx),
      verdicts: _verdicts(ctx),
    );
  }

  static List<String> _forStreet(_HandContext ctx, ReplayStreet street) {
    // A postflop street with no betting means the money was already in and the
    // board is simply running out. It is still worth narrating — that runout
    // decided the hand — but none of the decision commentary applies, and the
    // flop writer would otherwise call an all-in board "checked through".
    if (street.round != BettingRound.preflop &&
        street.actions.isEmpty &&
        ctx.replay.allIn) {
      return _runout(ctx, street);
    }
    return switch (street.round) {
      BettingRound.preflop => _preflop(ctx, street),
      BettingRound.flop => _flop(ctx, street),
      BettingRound.turn => _turn(ctx, street),
      _ => _river(ctx, street),
    };
  }

  /// A street dealt with no action left to take: everyone is all-in and the
  /// cards are being run out. Says what the card is and, more usefully, whether
  /// it changed who is winning.
  static List<String> _runout(_HandContext ctx, ReplayStreet street) {
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
  static List<String> _preflop(_HandContext ctx, ReplayStreet street) {
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
  static String _openVerdict(_HandContext ctx, ReplayAction open) {
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
  static List<String> _flop(_HandContext ctx, ReplayStreet street) {
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

  /// Reports a re-raise on a street. Classifies it by whether the raiser
  /// actually holds the best hand — we can see every card, so there is no excuse
  /// for calling top pair "a bluff", which a rank threshold used to do.
  static List<String> _raiseRead(
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

  // ---- Turn -----------------------------------------------------------------

  /// Narrow the ranges by what the flop action said, then judge the bluffs.
  static List<String> _turn(_HandContext ctx, ReplayStreet street) {
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
  static List<String> _river(_HandContext ctx, ReplayStreet street) {
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

  // ---- Aggression & bluff evaluation ---------------------------------------

  /// Reads a bet or raise: value, semi-bluff, or pure bluff — and whether the
  /// spot justified it.
  static List<String> _aggressionRead(
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
  static String _bluffVerdict(
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

  // ---- Closing summary ------------------------------------------------------

  static List<String> _summary(_HandContext ctx) {
    final r = ctx.replay;
    final out = <String>[];

    final size = formatChipsWithBb(r.pot, r.bigBlind);
    final won = r.winnerHand.toLowerCase();
    final lost = r.loserHand.toLowerCase();
    if (r.suckout) {
      out.add(ctx.voice.pick([
        'The money went in bad and got there. ${r.winnerName} was behind to '
            '${r.loserName}\'s $lost when the chips went in and spiked it — a '
            '$size pot decided by the deck, not by anybody\'s decision-making.',
        'That is a cooler with a bad ending for ${r.loserName}: drawing thin '
            'when it all went in, and the board obliged. $size to '
            '${r.winnerName}, none of it earned.',
        '${r.winnerName} needed help and got it. $lost was in front until the '
            'deck intervened, and $size changes hands on a card.',
      ], 53));
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

  static List<PlayerVerdict> _verdicts(_HandContext ctx) => [
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

  static (String, VerdictGrade) _verdictFor(_HandContext ctx, ReplaySeat seat) {
    final r = ctx.replay;
    final style = seat.styleLabel;
    final styleTag = style == null ? '' : ' Very much a $style move.';

    if (seat.won) {
      if (r.suckout) {
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
          'That is the whole game in one hand.$styleTag',
          VerdictGrade.excellent,
        );
      }
      if (!r.reachedRiver) {
        return (
          'took the aggressive line and got the fold. No showdown needed, no '
          'cards required — the best kind of pot to win.$styleTag',
          VerdictGrade.good,
        );
      }
      return (
        'won it with ${ctx.finalHand(seat)}, though a touch passively — there '
        'was at least one more bet available on this hand and it was left on '
        'the table.$styleTag',
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
          'street.$styleTag',
          VerdictGrade.questionable,
        );
      }
      if (ctx.wasLooseEntry(seat)) {
        return (
          'never should have been in the pot from ${seat.position.phrase} with '
          '${ctx.holding(seat)}, and paid for the privilege before finding the '
          'fold button on the $street.$styleTag',
          VerdictGrade.poor,
        );
      }
      return (
        'got away from it cleanly on the $street — read the strength, saved the '
        'chips, nothing to fix. Good, disciplined folding is invisible and it '
        'is worth a fortune.$styleTag',
        VerdictGrade.good,
      );
    }

    if (r.suckout && seat.name == r.loserName) {
      return (
        'did everything right and lost anyway — got it in with '
        '${ctx.finalHand(seat)} as a clear favourite and got run down. Bank the '
        'decision and ignore the result.',
        VerdictGrade.unlucky,
      );
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
          '$styleTag',
          VerdictGrade.questionable,
        );
      }
      return (
        'paid it off with ${ctx.finalHand(seat)} — talked into a call that '
        'only ever beats a bluff. That is the most '
        'expensive habit in poker.$styleTag',
        VerdictGrade.questionable,
      );
    }
    return (
      'lost with ${ctx.finalHand(seat)}. Second best is second best, and there '
      'was no obvious place to get away from it — this one just costs '
      'money.$styleTag',
      VerdictGrade.standard,
    );
  }

  // ---- Small helpers --------------------------------------------------------

  static String _sizingWord(double potFraction) {
    if (potFraction <= 0) return 'a token amount';
    if (potFraction < 0.34) return 'a small stab, about a third of the pot';
    if (potFraction < 0.55) return 'about half pot';
    if (potFraction < 0.8) return 'two-thirds of the pot';
    if (potFraction <= 1.1) return 'a pot-sized bet';
    return 'an overbet';
  }

  static String _names(Iterable<String> names) {
    final list = names.toList();
    if (list.isEmpty) return 'nobody';
    if (list.length == 1) return list.first;
    return '${list.sublist(0, list.length - 1).join(', ')} and ${list.last}';
  }

  static String _join(List<String> parts) {
    if (parts.length == 1) return parts.first;
    return '${parts.sublist(0, parts.length - 1).join('; ')}; and ${parts.last}';
  }
}

/// Derived facts about one replay, computed on demand and shared by every
/// commentary pass. Keeps the narrator itself readable.
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

  factory _Voice.of(HandReplay r) => _Voice(
        Object.hashAll([
          r.board.join(),
          r.pot,
          r.bigBlind,
          for (final s in r.seats) ...[s.playerId, s.cards.join()],
        ]),
      );

  final int _seed;

  /// One of [options]. [salt] separates different lines within the same hand so
  /// they don't all land on the same index and read as a matched set.
  String pick(List<String> options, [int salt = 0]) {
    if (options.isEmpty) return '';
    final mixed = (_seed ^ (salt * 0x9E3779B1)) & 0x7FFFFFFF;
    return options[mixed % options.length];
  }
}

class _HandContext {
  _HandContext(this.replay) : voice = _Voice.of(replay);

  final HandReplay replay;

  /// Deterministic phrasing variation for this hand.
  final _Voice voice;

  List<ReplaySeat> get flopSeats => replay.seats;

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

  ReplaySeat? seatByName(String name) =>
      replay.seats.where((s) => s.name == name).firstOrNull;

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
    return rank == null ? holding(seat) : _phrase(rank);
  }

  String finalHand(ReplaySeat seat) {
    final rank = seat.finalRank;
    return rank == null ? holding(seat) : _phrase(rank);
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
          if (rank != null) bits.add('for ${_phrase(rank)}');
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
    final styleTag = seat.styleLabel == null ? '' : ' ${seat.styleLabel}, so no surprise';

    if (seat.position == TablePosition.bigBlind) {
      return '${seat.name} defends the big blind with ${holding(seat)} (top '
          '$pct% of hands). Getting a price closing the action, that is a '
          'perfectly reasonable defend — the big blind is allowed to be wide.';
    }
    if (wasLooseEntry(seat)) {
      return '${seat.name} has no business playing ${holding(seat)} from '
          '${seat.position.phrase}. That is roughly the top $pct% of hands, and '
          'from that seat you want to be in the top $allowed% at most. Out of '
          'position with a hand that flops marginal pairs is how you build a '
          'pot you cannot win.$styleTag.';
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
