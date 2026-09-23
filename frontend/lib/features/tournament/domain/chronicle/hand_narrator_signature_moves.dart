part of 'hand_narrator.dart';

/// Names the signature moves that fired on this street.
///
/// This is the point of giving players signature moves at all: a trap only
/// reads as a trap if somebody says so. Without this the commentary describes
/// an anonymous check, and the character that was carefully authored into the
/// profile is invisible to the person watching.
List<String> _signatureMoves(_HandContext ctx, ReplayStreet street) {
  final out = <String>[];
  for (final t in street.triggers) {
    final who = ctx.nameOf(t.playerId);
    if (who == null) continue;
    final line = switch (t.triggerId) {
      'Slow_Play_Trap' => ctx.voice.pick([
          'And that is the trap — $who has a monster and just checked it. '
              'They are not trying to win this pot now; they are trying to '
              'win a much bigger one on the next street.',
          '$who checks a hand nobody checks — that is a trap, plainly laid: '
              'give them a card, let them catch something, then charge for '
              'it.',
          'Do not read that check as weakness. $who is slow-playing, and the '
              'trap is set.',
        ], 71),
      'Sticky_Showdown' => ctx.voice.pick([
          '$who is never folding this. Once they have a piece of it the price '
              'stops mattering — that is the call you were hoping for when '
              'you bet.',
          'That is a crying call from $who, and they knew it. They simply do '
              'not lay down a made hand.',
          '$who pays it off. You will not bluff this player off a pair.',
        ], 73),
      'Float_And_Take_Away' => ctx.voice.pick([
          'There it is — $who floated the flop with nothing, waiting for '
              'exactly this. The aggressor gave up, so $who takes it.',
          'That is a float, and it just got collected. $who never had a hand; '
              'they had a plan.',
          '$who bets the moment the initiative is dropped. That flop call '
              'was a float, and this is the half that collects.',
        ], 79),
      'Bubble_Predator' => ctx.voice.pick([
          '$who is attacking the bubble. Everyone else is trying to survive, '
              'which is precisely what makes this profitable.',
          'That raise is about the pay jump, not the cards. $who knows nobody '
              'here can afford to call.',
          '$who applies the pressure only a big stack can. This is where '
              'tournaments are won.',
        ], 83),
      'Limp_Reraise' => ctx.voice.pick([
          '$who limps — and that is not weakness, it is an invitation. They '
              'want somebody to raise so they can come back over the top.',
          'An early-position limp from $who. Old school, and there is a very '
              'good hand behind it.',
          'Watch what happens if anyone raises here: $who limped in with the '
              'intention of re-raising.',
        ], 89),
      'Underbluff_Exploit' => ctx.voice.pick([
          '$who folds, and it is a read rather than a hand: recreational '
              'players almost never bluff the river, so a bluff-catcher is '
              'catching nothing.',
          'That is a disciplined laydown by $who. Against this opponent a '
              'river bet means a river hand.',
          '$who is not paying this one off. They have decided this player '
              'does not have a bluff in their range here.',
        ], 97),
      'Check_Raise_Merchant' => ctx.voice.pick([
          '$who checked into this and now raises — that is the check-raise, '
              'the play that only exists because they were willing to look '
              'weak for one street to get two streets of value.',
          'There it is: $who lets the bet come to them and springs the trap '
              'right back over the top.',
          'That check was never weakness. $who was fishing for exactly this '
              'bet so they could raise it.',
        ], 101),
      'Positional_Warfare' => ctx.voice.pick([
          '$who opens a hand that has no business being raised from anywhere '
              'else — this is a button-and-cutoff-only raise, and the seat is '
              'the whole reason for it.',
          'That raise is about the chair, not the cards. $who is exploiting '
              'position the way the position is supposed to be exploited.',
          '$who widens exactly where a raise is supposed to widen — fewer '
              'players left to get through changes what a hand is worth.',
        ], 103),
      'Leverage_Pressure' => ctx.voice.pick([
          'This size threatens a stack, and that is the point — $who is '
              'applying the kind of pressure only a big stack can, in a spot '
              'that can actually put someone all in.',
          '$who is not just betting, they are hunting: this is a jam threat, '
              'not a value bet, and the sizing says so.',
          'That bet puts real chips at risk for the opponent. $who picked '
              'this exact spot because it does.',
        ], 107),
      'Soul_Read' => ctx.voice.pick([
          '$who closes the action in position after everyone checked, and '
              'attacks harder than a standard read would — that is a read on '
              'weakness, not a standard continuation.',
          'Everybody checked to $who, and this is what a player does when '
              'they believe nobody here has anything: bet bigger, bluff more.',
          '$who is playing the position, not just the hand — last to act, '
              'weakness in front of them, and they take it.',
        ], 109),
      'Geometric_Overbet_Execution' => ctx.voice.pick([
          'That is an overbet, not a standard size — $who has the nut '
              'advantage on this street and is building the pot geometrically '
              'rather than betting a normal fraction of it.',
          '$who sizes this one for maximum value, well past a pot-sized bet. '
              'With the best hand possible here, why would you bet small?',
          'This is a deliberately oversized bet from $who — the math behind a '
              'geometric bet says this is exactly the size that gets the whole '
              'stack in by the river.',
        ], 113),
      'Tilt_Blowup' => ctx.voice.pick([
          '$who fires at a pot they have no business firing at — that is '
              'tilt talking, wider and louder than the hand justifies.',
          'This is not the same player from a few hands ago. $who is coming '
              'in raising and bluffing pots they would normally leave alone.',
          '$who is on tilt and it shows: more aggression than the hand can '
              'support, at a moment a level head sits out.',
        ], 127),
      'Tilt_Chase' => ctx.voice.pick([
          '$who is not folding this, tilted or not — but tilted, the calls '
              'come wider and looser, chasing a pot to make up for the last '
              'one.',
          'That is a tilt call: $who is not getting off this hand no matter '
              'the price, trying to win the last pot back in this one.',
          '$who pays it off wider than they normally would. Tilt does not '
              'make this player aggressive — it makes them sticky.',
        ], 131),
      'Tilt_Shutdown' => ctx.voice.pick([
          '$who folds here, and tighter than usual — some players get loud '
              'on tilt, this one goes quiet and waits it out.',
          'That is a player who has shut down: $who is folding hands they '
              'would normally continue with, rattled and playing it safe.',
          '$who clams up after the last pot instead of chasing it. Not every '
              'tilt reaction is aggression — this one is retreat.',
        ], 137),
      _ => null,
    };
    if (line != null) out.add(line);
  }
  return out;
}
