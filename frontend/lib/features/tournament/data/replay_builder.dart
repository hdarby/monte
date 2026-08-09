import 'package:monte/core/domain/ai/player_profile.dart';
import 'package:monte/core/domain/engine/actions.dart';
import 'package:monte/core/domain/engine/game.dart';
import 'package:monte/core/domain/engine/hand_evaluator.dart';
import 'package:monte/core/domain/engine/player.dart';
import 'package:monte/core/domain/hand_history.dart';
import 'package:monte/features/tournament/domain/chronicle/hand_replay.dart';

/// Turns a finished [PokerGame] plus its action log into a [HandReplay] rich
/// enough for the commentary to work from: seat positions, stack depths in
/// chips, every action with the pot it went into, and the board street by
/// street.
///
/// Kept separate from `ChronicleRecorder` because this is fiddly, mechanical
/// reconstruction; the recorder decides *whether* to record, this decides *what*
/// the record contains.
///
/// The replay comes back **un-narrated**: commentary is expensive (it enumerates
/// outs street by street) and only the level's single biggest pot is ever shown,
/// so `TournamentChronicle` narrates that one at recap time rather than paying
/// the cost on every hand at every table.
class ReplayBuilder {
  const ReplayBuilder._();

  /// Builds the replay, or null when the hand isn't worth replaying
  /// (fewer than two players saw the flop).
  static HandReplay? build({
    required PokerGame game,
    required List<ActionRecord> actions,
    required Map<String, int> preChips,
    required int bigBlind,
    PlayerProfile? Function(String playerId)? profileForSeat,
  }) {
    final positions = _positions(game);
    final foldedOn = _foldStreets(actions);

    // Only players who saw the flop appear in the roster.
    final flopPlayers = [
      for (final p in game.players)
        if (foldedOn[p.id] != BettingRound.preflop &&
            _wasDealtIn(p, actions, preChips))
          p,
    ];
    if (flopPlayers.length < 2) return null;

    final winners = {
      for (final r in game.results)
        if (r.netWon > 0) r.player.id,
    };
    final pot = game.results.fold<int>(
      0,
      (a, r) => a + (r.netWon > 0 ? r.netWon : 0),
    );

    final seats = <ReplaySeat>[
      for (final p in flopPlayers)
        ReplaySeat(
          playerId: p.id,
          name: p.name,
          cards: [for (final c in p.hole) c.code],
          position: positions[p.id] ?? TablePosition.middle,
          startingStack: preChips[p.id] ?? p.stack,
          won: winners.contains(p.id),
          net: p.stack - (preChips[p.id] ?? p.stack),
          styleLabel: _styleOf(profileForSeat?.call(p.id)),
          foldedOn: foldedOn[p.id],
          finalRank: foldedOn[p.id] == null && game.board.length >= 5
              ? HandEvaluator.evaluate([...p.hole, ...game.board]).rank
              : null,
        ),
    ]..sort((a, b) => a.position.index.compareTo(b.position.index));

    final streets = _streets(game, actions, positions, bigBlind);
    if (streets.isEmpty) return null;

    final ranked = [
      for (final s in seats)
        if (s.reachedShowdown && s.finalRank != null) s,
    ]..sort((a, b) => b.finalRank!.index.compareTo(a.finalRank!.index));

    final winner = seats.where((s) => s.won).firstOrNull ?? seats.first;
    final loser = ranked.where((s) => !s.won).firstOrNull ??
        seats.where((s) => !s.won).firstOrNull ??
        seats.last;

    final replay = HandReplay(
      pot: pot,
      bigBlind: bigBlind,
      board: [for (final c in game.board) c.code],
      seats: seats,
      streets: streets,
      winnerName: winner.name,
      winnerHand: winner.finalRank?.label ?? 'the winner',
      loserName: loser.name,
      loserHand: loser.finalRank?.label ?? 'a losing hand',
      winnerRank: winner.finalRank ?? HandRank.highCard,
      loserRank: loser.finalRank ?? HandRank.highCard,
      allIn: game.players.any((p) => p.isAllIn),
      suckout: _suckout(game, seats, winners),
      reachedRiver: game.board.length >= 5,
    );

    return replay;
  }

  /// Maps each seat to its position label, working backwards from the button.
  static Map<String, TablePosition> _positions(PokerGame game) {
    final n = game.players.length;
    if (n == 0) return const {};

    // Order of action preflop starts left of the big blind; the canonical
    // labels run SB, BB, UTG, ... , CO, BTN from the button.
    final order = <TablePosition>[];
    if (n == 2) {
      // Heads-up the button posts the small blind, so the seat to its left
      // (button + 1, i.e. index 0 below) is the big blind.
      order.addAll([TablePosition.bigBlind, TablePosition.button]);
    } else {
      const early = [
        TablePosition.underTheGun,
        TablePosition.underTheGun1,
        TablePosition.middle,
        TablePosition.middle1,
        TablePosition.lojack,
        TablePosition.hijack,
      ];
      order
        ..add(TablePosition.smallBlind)
        ..add(TablePosition.bigBlind)
        // Three-handed there are no early seats at all, hence the clamp.
        ..addAll(early.take((n - 4).clamp(0, early.length)));
      if (n >= 4) order.add(TablePosition.cutoff);
      if (n >= 3) order.add(TablePosition.button);
    }

    final out = <String, TablePosition>{};
    for (var i = 0; i < n && i < order.length; i++) {
      // Seat (button + 1 + i) is the i-th position in the list above.
      final seat = game.players[(game.buttonIndex + 1 + i) % n];
      out[seat.id] = order[i];
    }
    return out;
  }

  /// The street each player folded on, or absent if they reached showdown.
  static Map<String, BettingRound?> _foldStreets(List<ActionRecord> actions) {
    final out = <String, BettingRound?>{};
    for (final a in actions) {
      if (a.type == ActionType.fold) out[a.playerId] = a.street;
    }
    return out;
  }

  /// Whether a player was actually dealt in (put chips in or acted at all).
  static bool _wasDealtIn(
    Player p,
    List<ActionRecord> actions,
    Map<String, int> preChips,
  ) =>
      actions.any((a) => a.playerId == p.id) ||
      (preChips[p.id] ?? 0) != p.stack ||
      p.inHand;

  /// Rebuilds the per-street action, tracking the pot and what each action cost
  /// so the narrator can talk about sizing.
  static List<ReplayStreet> _streets(
    PokerGame game,
    List<ActionRecord> actions,
    Map<String, TablePosition> positions,
    int bigBlind,
  ) {
    final nameOf = {for (final p in game.players) p.id: p.name};
    final allIn = {
      for (final p in game.players)
        if (p.isAllIn) p.id,
    };

    const rounds = [
      (BettingRound.preflop, 'Preflop', 0),
      (BettingRound.flop, 'Flop', 3),
      (BettingRound.turn, 'Turn', 4),
      (BettingRound.river, 'River', 5),
    ];

    final out = <ReplayStreet>[];
    var potBefore = 0;

    for (final (round, label, boardCount) in rounds) {
      final onStreet = actions.where((a) => a.street == round).toList();
      if (onStreet.isEmpty && round != BettingRound.preflop) continue;
      if (game.board.length < boardCount) break;

      // What each player has already committed on this street, so a raise's
      // true cost (and the amount to call) can be recovered.
      final committed = <String, int>{};
      var highest = 0;
      var pot = potBefore;

      final replayActions = <ReplayAction>[];
      for (final a in onStreet) {
        final already = committed[a.playerId] ?? 0;
        final toCall = (highest - already).clamp(0, 1 << 30);

        replayActions.add(
          ReplayAction(
            playerId: a.playerId,
            name: nameOf[a.playerId] ?? a.playerId,
            position: positions[a.playerId] ?? TablePosition.middle,
            type: a.type,
            street: round,
            amount: a.amount,
            potBefore: pot,
            toCall: toCall,
            isAllIn: a.type == ActionType.allIn || allIn.contains(a.playerId),
          ),
        );

        switch (a.type) {
          case ActionType.bet:
          case ActionType.raise:
          case ActionType.allIn:
            committed[a.playerId] = a.amount;
            if (a.amount > highest) highest = a.amount;
          case ActionType.call:
            committed[a.playerId] = already + a.amount;
            if (committed[a.playerId]! > highest) {
              highest = committed[a.playerId]!;
            }
          case ActionType.check:
          case ActionType.fold:
            break;
        }
        // `potAfter` is authoritative engine output — prefer it to our tally.
        pot = a.potAfter;
      }

      out.add(
        ReplayStreet(
          name: label,
          round: round,
          boardAfter: [
            for (final c in game.board.take(boardCount)) c.code,
          ],
          actions: replayActions,
          potAfter: pot,
        ),
      );
      potBefore = pot;
    }
    return out;
  }

  /// True when the eventual winner was behind on the flop among the all-in
  /// contenders and got there later.
  static bool _suckout(
    PokerGame game,
    List<ReplaySeat> seats,
    Set<String> winners,
  ) {
    if (game.board.length < 5) return false;
    final contenders = game.players.where((p) => p.inHand && p.isAllIn).toList();
    if (contenders.length < 2) return false;

    final flop = game.board.take(3).toList();
    HandValue? best;
    String? bestId;
    for (final p in contenders) {
      final v = HandEvaluator.evaluate([...p.hole, ...flop]);
      if (best == null || v > best) {
        best = v;
        bestId = p.id;
      }
    }
    return bestId != null && !winners.contains(bestId);
  }

  /// A one-word style tag for a personality, for commentary colour.
  static String? _styleOf(PlayerProfile? profile) {
    if (profile == null || profile.archetype.isEmpty) return null;
    return profile.archetype.replaceAll('_', ' ');
  }
}
