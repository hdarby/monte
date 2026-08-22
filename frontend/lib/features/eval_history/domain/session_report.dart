import 'dart:math';

import 'package:meta/meta.dart';

import 'package:monte/core/domain/engine/actions.dart';
import 'package:monte/core/domain/engine/card.dart';
import 'package:monte/core/domain/engine/game.dart';
import 'package:monte/core/domain/engine/hand_evaluator.dart';
import 'package:monte/features/eval_history/domain/eval_hand.dart';

/// Everything a post-session review needs about one player, computed from the
/// full-information log.
///
/// Deliberately reconstructed from the record rather than captured live. The log
/// holds every hole card and the whole board, so a metric like all-in equity is
/// *more* accurate worked out afterwards — against the hands the opponents
/// actually held — than it could be estimated at the table.
@immutable
class SessionReport {
  const SessionReport({
    required this.playerId,
    required this.hands,
    required this.netBb,
    required this.allInEvBb,
    required this.showdownBb,
    required this.nonShowdownBb,
    required this.sawFlop,
    required this.wonWhenSawFlop,
    required this.vpip,
    required this.pfr,
    required this.threeBet,
    required this.limpFirstIn,
    required this.firstInSpots,
    required this.rfiBySeat,
    required this.foldToThreeBet,
    required this.faced3Bet,
    required this.fourBet,
    required this.fiveBet,
    required this.squeeze,
    required this.bbDefend,
    required this.bbFacedSteal,
    required this.limpFolded,
    required this.riverFoldBySize,
    required this.evLostByStreet,
    required this.evLostByAction,
    required this.bustout,
  });

  final String playerId;
  final int hands;

  /// Actual result, and the result the all-in spots *deserved*.
  ///
  /// The pair is the whole answer to "was that bad luck or bad play". A player
  /// far below their all-in expectation ran badly; one at or above it and still
  /// losing is losing on decisions, and no amount of sympathy changes that.
  final double netBb;
  final double allInEvBb;

  /// The red line / blue line split: money won at showdown versus money won
  /// without one. A passive player's non-showdown figure is deeply negative —
  /// they never take a pot away, so every profit must come from holding the best
  /// hand. It is the clearest single picture of passivity there is.
  final double showdownBb;
  final double nonShowdownBb;

  final int sawFlop;
  final int wonWhenSawFlop;

  final int vpip;
  final int pfr;
  final int threeBet;

  /// Limps and opportunities when first into an unopened pot.
  final int limpFirstIn;
  final int firstInSpots;

  /// Seat label → (opportunities, raises) when folded to.
  final Map<String, (int, int)> rfiBySeat;

  final int foldToThreeBet;
  final int faced3Bet;
  final int fourBet;
  final int fiveBet;
  final int squeeze;

  final int bbDefend;
  final int bbFacedSteal;

  /// Limped and then folded the same hand preflop — the worst version of it.
  final int limpFolded;

  /// Bet size faced on the river → (times faced, times folded). Buckets:
  /// `<1/3`, `1/3-2/3`, `2/3-pot`, `overbet`. One aggregate number hides the
  /// only distinction that matters: calling cheap is fine, calling big is not.
  final Map<String, (int, int)> riverFoldBySize;

  /// Big blinds of expected value given up, by street and by action taken.
  final Map<String, double> evLostByStreet;
  final Map<String, double> evLostByAction;

  /// The hand the player busted on, if they did.
  final EvalHand? bustout;

  double _pct(int n, int d) => d == 0 ? 0 : 100 * n / d;
  double get vpipPct => _pct(vpip, hands);
  double get pfrPct => _pct(pfr, hands);
  double get threeBetPct => _pct(threeBet, hands);
  double get limpPct => _pct(limpFirstIn, firstInSpots);
  double get foldTo3BetPct => _pct(foldToThreeBet, faced3Bet);
  double get wwsfPct => _pct(wonWhenSawFlop, sawFlop);
  double get bbDefendPct => _pct(bbDefend, bbFacedSteal);
  double get bbPer100 => hands == 0 ? 0 : 100 * netBb / hands;
  double get allInEvPer100 => hands == 0 ? 0 : 100 * allInEvBb / hands;

  /// How far the actual result sits from what the all-in spots deserved.
  /// Strongly negative = ran below expectation; near zero = the result is real.
  double get luckBb => netBb - allInEvBb;

  static const _streets = ['preflop', 'flop', 'turn', 'river'];

  /// Builds the report for [playerId] over [hands].
  static SessionReport of(List<EvalHand> hands, String playerId) {
    var n = 0;
    var netBb = 0.0, allIn = 0.0, sd = 0.0, nsd = 0.0;
    var sawFlop = 0, wwsf = 0;
    var vpip = 0, pfr = 0, tb = 0, fourBet = 0, fiveBet = 0, squeeze = 0;
    var firstIn = 0, limped = 0, limpFolded = 0;
    var faced3 = 0, fold3 = 0;
    var bbFaced = 0, bbDef = 0;
    final rfi = <String, (int, int)>{};
    final riverSize = <String, (int, int)>{};
    final evStreet = {for (final s in _streets) s: 0.0};
    final evAction = <String, double>{};
    EvalHand? bust;

    for (final h in hands) {
      final me = h.players.where((p) => p.id == playerId).firstOrNull;
      if (me == null) continue;
      n++;
      final bb = h.bigBlind <= 0 ? 1 : h.bigBlind;
      final net = me.net / bb;
      netBb += net;
      if (me.finalStack <= 0) bust = h;

      final showdown = h.results.any((r) => r.handRank != null);
      if (showdown && !me.folded) {
        sd += net;
      } else {
        nsd += net;
      }

      final pre = h.actions.where((a) => a.street == BettingRound.preflop);
      final mine = pre.where((a) => a.playerId == playerId).toList();
      if (mine.any((a) => _isVoluntary(a.type))) vpip++;
      if (mine.any((a) => _isRaise(a.type))) pfr++;

      // Postflop participation.
      if (h.actions.any((a) =>
          a.playerId == playerId && a.street != BettingRound.preflop)) {
        sawFlop++;
        if (net > 0) wwsf++;
      }

      // Walk preflop once, tracking how many raises preceded each of my actions.
      var raisesBefore = 0;
      var callersBefore = 0;
      var actedYet = false;
      for (final a in pre) {
        if (a.playerId == playerId) {
          if (!actedYet) {
            actedYet = true;
            final seat = me.position;
            if (raisesBefore == 0 && callersBefore == 0 && seat != 'BB') {
              firstIn++;
              final cur = rfi[seat] ?? (0, 0);
              rfi[seat] = (cur.$1 + 1, cur.$2 + (_isRaise(a.type) ? 1 : 0));
              if (a.type == ActionType.call) {
                limped++;
                if (mine.skip(1).any((x) => x.type == ActionType.fold)) {
                  limpFolded++;
                }
              }
            }
            if (raisesBefore == 1) {
              if (_isRaise(a.type)) {
                tb++;
                if (callersBefore > 0) squeeze++;
              }
              if (seat == 'BB') {
                bbFaced++;
                if (a.type != ActionType.fold) bbDef++;
              }
            }
            if (raisesBefore == 2 && _isRaise(a.type)) fourBet++;
            if (raisesBefore >= 3 && _isRaise(a.type)) fiveBet++;
          } else if (raisesBefore >= 2 &&
              mine.any((x) => _isRaise(x.type))) {
            // Re-raised over my own raise: did I continue?
          }
          continue;
        }
        if (_isRaise(a.type)) {
          raisesBefore++;
        } else if (a.type == ActionType.call) {
          callersBefore++;
        }
      }

      // Did my raise get re-raised, and what did I do about it?
      final myRaise = h.actions.indexWhere((a) =>
          a.playerId == playerId &&
          a.street == BettingRound.preflop &&
          _isRaise(a.type));
      if (myRaise >= 0) {
        final after = h.actions.skip(myRaise + 1).where(
            (a) => a.street == BettingRound.preflop);
        final rr = after.where((a) => _isRaise(a.type)).firstOrNull;
        if (rr != null) {
          faced3++;
          final resp = after
              .skipWhile((a) => a != rr)
              .skip(1)
              .where((a) => a.playerId == playerId)
              .firstOrNull;
          if (resp == null || resp.type == ActionType.fold) fold3++;
        }
      }

      // River bets faced, bucketed by size relative to the pot.
      _riverFacings(h, playerId, riverSize);

      // Give-ups, by street and by the action actually taken.
      for (final d in h.decisions.where((d) => d.playerId == playerId)) {
        evStreet[d.street] = (evStreet[d.street] ?? 0) + d.evLost;
        evAction[d.actualType] = (evAction[d.actualType] ?? 0) + d.evLost;
      }

      allIn += _allInEvBb(h, playerId);
    }

    return SessionReport(
      playerId: playerId,
      hands: n,
      netBb: netBb,
      allInEvBb: allIn,
      showdownBb: sd,
      nonShowdownBb: nsd,
      sawFlop: sawFlop,
      wonWhenSawFlop: wwsf,
      vpip: vpip,
      pfr: pfr,
      threeBet: tb,
      limpFirstIn: limped,
      firstInSpots: firstIn,
      rfiBySeat: rfi,
      foldToThreeBet: fold3,
      faced3Bet: faced3,
      fourBet: fourBet,
      fiveBet: fiveBet,
      squeeze: squeeze,
      bbDefend: bbDef,
      bbFacedSteal: bbFaced,
      limpFolded: limpFolded,
      riverFoldBySize: riverSize,
      evLostByStreet: evStreet,
      evLostByAction: evAction,
      bustout: bust,
    );
  }

  static bool _isVoluntary(ActionType t) =>
      t == ActionType.call ||
      t == ActionType.bet ||
      t == ActionType.raise ||
      t == ActionType.allIn;

  static bool _isRaise(ActionType t) =>
      t == ActionType.bet || t == ActionType.raise || t == ActionType.allIn;

  /// Records each river bet [playerId] faced into a size bucket.
  static void _riverFacings(
      EvalHand h, String playerId, Map<String, (int, int)> out) {
    final river = h.actions.where((a) => a.street == BettingRound.river).toList();
    for (var i = 0; i < river.length; i++) {
      final a = river[i];
      if (a.playerId == playerId || !_isRaise(a.type)) continue;
      final resp = river.skip(i + 1).where((x) => x.playerId == playerId).firstOrNull;
      if (resp == null) continue;
      final pot = a.potAfter - a.amount;
      final frac = pot <= 0 ? 1.0 : a.amount / pot;
      final key = frac < 1 / 3
          ? '<1/3'
          : frac < 2 / 3
              ? '1/3-2/3'
              : frac <= 1.0
                  ? '2/3-pot'
                  : 'overbet';
      final cur = out[key] ?? (0, 0);
      out[key] = (cur.$1 + 1, cur.$2 + (resp.type == ActionType.fold ? 1 : 0));
      break;
    }
  }

  /// The big blinds this hand was *worth* to [playerId] when the money went in.
  ///
  /// Only meaningful when they were all-in with cards still to come, which is
  /// where results and merit come apart. Everything else scores at its actual
  /// value, so the totals stay comparable.
  static double _allInEvBb(EvalHand h, String playerId) {
    final bb = h.bigBlind <= 0 ? 1 : h.bigBlind;
    final me = h.players.where((p) => p.id == playerId).firstOrNull;
    if (me == null) return 0;
    final actual = me.net / bb;
    if (me.finalStack > 0 && !h.actions.any((a) =>
        a.playerId == playerId && a.type == ActionType.allIn)) {
      return actual;
    }
    // Live opponents at the end, with known cards.
    final live = h.players
        .where((p) => p.id != playerId && !p.folded && p.holeCards.length == 2)
        .toList();
    if (live.isEmpty || me.holeCards.length != 2) return actual;

    // The street the all-in happened on decides how many cards were to come.
    final allInAt = h.actions
        .where((a) => a.playerId == playerId && a.type == ActionType.allIn)
        .firstOrNull;
    final known = switch (allInAt?.street) {
      BettingRound.preflop => 0,
      BettingRound.flop => 3,
      BettingRound.turn => 4,
      _ => 5,
    };
    if (known >= 5) return actual; // no cards to come; result is deserved

    final board = [for (final c in h.board) Card.fromCode(c)];
    if (board.length < known) return actual;
    final hero = [for (final c in me.holeCards) Card.fromCode(c)];
    final opps = [
      for (final p in live) [for (final c in p.holeCards) Card.fromCode(c)]
    ];
    final share = _equityShare(hero, opps, board.take(known).toList());
    // The pot this hand played for, from everyone's contribution.
    final pot = h.results.fold<int>(0, (a, r) => a + r.amountWon) / bb;
    final invested = -me.net / bb + (me.net > 0 ? 0 : 0);
    // Expected return = share of the pot, minus what was put in.
    final put = (me.startingStack - me.finalStack) / bb;
    return share * pot - (put > 0 ? put : invested);
  }

  /// Hero's share of the pot against known opponent hands, running the board out.
  static double _equityShare(
      List<Card> hero, List<List<Card>> opps, List<Card> board) {
    final rng = Random(20240822);
    final dead = <Card>{...hero, ...board, for (final o in opps) ...o};
    final deck = [
      for (final s in Suit.values)
        for (final r in Rank.values)
          if (!dead.contains(Card(r, s))) Card(r, s),
    ];
    final need = 5 - board.length;
    if (need <= 0) return _showdownShare(hero, opps, board);
    var total = 0.0;
    const iterations = 400;
    for (var i = 0; i < iterations; i++) {
      final pool = [...deck];
      final run = <Card>[];
      for (var k = 0; k < need; k++) {
        final idx = k + rng.nextInt(pool.length - k);
        final t = pool[k];
        pool[k] = pool[idx];
        pool[idx] = t;
        run.add(pool[k]);
      }
      total += _showdownShare(hero, opps, [...board, ...run]);
    }
    return total / iterations;
  }

  static double _showdownShare(
      List<Card> hero, List<List<Card>> opps, List<Card> board) {
    final mine = HandEvaluator.evaluate([...hero, ...board]);
    var tied = 0;
    for (final o in opps) {
      final cmp = mine.compareTo(HandEvaluator.evaluate([...o, ...board]));
      if (cmp < 0) return 0;
      if (cmp == 0) tied++;
    }
    return 1 / (tied + 1);
  }
}
