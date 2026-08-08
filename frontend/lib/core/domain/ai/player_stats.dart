import 'dart:convert';

import 'package:monte/core/domain/engine/actions.dart';
import 'package:monte/core/domain/engine/game.dart';
import 'package:monte/core/domain/hand_history.dart';

/// Accumulated poker statistics for one tracked player identity, built purely
/// from observed action (see [PlayerStatsBook.observe]) — never from hidden
/// cards, honouring the "no free information" rule.
///
/// Each stat is an (made, opportunities) counter pair so rates can be smoothed
/// by a shrinkage prior and weighted by sample size ([confidence]) — an
/// exploitative pro only trusts a read once it has seen enough of it.
class PlayerStats {
  PlayerStats();

  // Counters are doubles so a recency decay can scale them smoothly. Each new
  // observation first fades the running totals ([_decay]), so recent hands
  // dominate and stale reads erode — a player's stats reflect their recent form.
  double hands = 0;

  // Preflop.
  double vpip = 0; // voluntarily put chips in
  double pfr = 0; // raised first-in / over limpers
  double threeBet = 0, threeBetOpp = 0; // reraised facing an open
  double foldTo3bet = 0, faced3bet = 0; // was the opener, faced a reraise
  double squeeze = 0, squeezeOpp = 0; // raised over an open + caller(s)
  double steal = 0, stealOpp = 0; // first-in raise from CO/BTN/SB
  double foldBlindSteal = 0, blindStealFaced = 0; // in the blinds vs a steal

  // Postflop.
  double cbet = 0, cbetOpp = 0; // preflop aggressor's flop continuation bet
  double foldToCbet = 0, cbetFaced = 0;
  double postAggr = 0, postCalls = 0; // bets/raises vs calls postflop (for AF)

  /// Per-observation decay: each newly observed hand fades prior totals by this,
  /// giving an effective window of ~1/(1−decay) ≈ 200 recent hands. Bounds the
  /// running totals (and hence [confidence]), so reads stay recency-weighted.
  static const double decayPerHand = 0.995;

  void decay() {
    hands *= decayPerHand;
    vpip *= decayPerHand;
    pfr *= decayPerHand;
    threeBet *= decayPerHand;
    threeBetOpp *= decayPerHand;
    foldTo3bet *= decayPerHand;
    faced3bet *= decayPerHand;
    squeeze *= decayPerHand;
    squeezeOpp *= decayPerHand;
    steal *= decayPerHand;
    stealOpp *= decayPerHand;
    foldBlindSteal *= decayPerHand;
    blindStealFaced *= decayPerHand;
    cbet *= decayPerHand;
    cbetOpp *= decayPerHand;
    foldToCbet *= decayPerHand;
    cbetFaced *= decayPerHand;
    postAggr *= decayPerHand;
    postCalls *= decayPerHand;
  }

  // ---- Priors / smoothing --------------------------------------------------
  static const double _priorHands = 14; // ~1.5 orbits before a read firms up
  double _rate(double made, double opp, double prior) =>
      (made + prior * _priorHands) / (opp + _priorHands);

  double get vpipRate => _rate(vpip, hands, 0.24);
  double get pfrRate => _rate(pfr, hands, 0.16);
  double get threeBetRate => _rate(threeBet, threeBetOpp, 0.07);
  double get foldTo3betRate => _rate(foldTo3bet, faced3bet, 0.55);
  double get squeezeRate => _rate(squeeze, squeezeOpp, 0.05);
  double get stealRate => _rate(steal, stealOpp, 0.42);
  double get foldBlindStealRate => _rate(foldBlindSteal, blindStealFaced, 0.55);
  double get cbetRate => _rate(cbet, cbetOpp, 0.55);
  double get foldToCbetRate => _rate(foldToCbet, cbetFaced, 0.45);

  /// Postflop aggression factor (bets+raises)/calls; 1.0 when no calls yet.
  double get aggressionFactor => postCalls == 0 ? 1.0 : postAggr / postCalls;

  /// How much to trust these reads, in [0,1): grows with hands observed. Used to
  /// scale an exploit adjustment so a thin sample barely moves play.
  double get confidence => hands / (hands + _priorHands);

  /// The minimum observed hands before a read is trusted at all — you can't read
  /// a player off one or two hands, so below this the exploit stays dormant and
  /// the HUD shows "still building a read".
  static const double baselineHands = 20;
  bool get established => hands >= baselineHands;

  Map<String, dynamic> toJson() => {
        'hands': hands,
        'vpip': vpip,
        'pfr': pfr,
        'threeBet': threeBet,
        'threeBetOpp': threeBetOpp,
        'foldTo3bet': foldTo3bet,
        'faced3bet': faced3bet,
        'squeeze': squeeze,
        'squeezeOpp': squeezeOpp,
        'steal': steal,
        'stealOpp': stealOpp,
        'foldBlindSteal': foldBlindSteal,
        'blindStealFaced': blindStealFaced,
        'cbet': cbet,
        'cbetOpp': cbetOpp,
        'foldToCbet': foldToCbet,
        'cbetFaced': cbetFaced,
        'postAggr': postAggr,
        'postCalls': postCalls,
      };

  static PlayerStats fromJson(Map<String, dynamic> j) {
    double g(String k) => (j[k] as num?)?.toDouble() ?? 0;
    return PlayerStats()
      ..hands = g('hands')
      ..vpip = g('vpip')
      ..pfr = g('pfr')
      ..threeBet = g('threeBet')
      ..threeBetOpp = g('threeBetOpp')
      ..foldTo3bet = g('foldTo3bet')
      ..faced3bet = g('faced3bet')
      ..squeeze = g('squeeze')
      ..squeezeOpp = g('squeezeOpp')
      ..steal = g('steal')
      ..stealOpp = g('stealOpp')
      ..foldBlindSteal = g('foldBlindSteal')
      ..blindStealFaced = g('blindStealFaced')
      ..cbet = g('cbet')
      ..cbetOpp = g('cbetOpp')
      ..foldToCbet = g('foldToCbet')
      ..cbetFaced = g('cbetFaced')
      ..postAggr = g('postAggr')
      ..postCalls = g('postCalls');
  }
}

/// A book of [PlayerStats] keyed by a stable identity, accumulated across hands.
///
/// Keys come in three shapes:
///  * `<identity>` — a player's own observed play (a personality's `profile.id`,
///    or an ephemeral `gen:<seat>` for an anonymous field-filler). This is what
///    an observer who has seen them reads.
///  * `me@<observerId>` — the human as seen *by that one observer*, built only
///    from the hands that observer actually shared with the human. Each opponent
///    forms its own impression, so a freshly-met player knows only what it saw.
///  * `human` is **not** used as a read target — reads of the human are always
///    per-observer (`me@…`), honouring "no free information".
///
/// Keys prefixed `gen:` / `me@gen:` are **ephemeral**: a generated player is a
/// unique instance that won't exist next session, so its reads (and others'
/// reads of it) are dropped on persist ([persistable]). Everything else — real
/// personalities and their impressions of the human — persists across sessions.
class PlayerStatsBook {
  PlayerStatsBook([Map<String, PlayerStats>? byId]) : _byId = byId ?? {};

  final Map<String, PlayerStats> _byId;

  /// The identity key under which observer [observerId] stores its private read
  /// of the human.
  static String meKey(String observerId) => 'me@$observerId';

  /// Whether [key] belongs to an anonymous generated player (either their own
  /// play or an impression involving them) and so must not be persisted.
  static bool isEphemeral(String key) =>
      key.startsWith('gen:') || key.startsWith('me@gen:');

  Iterable<String> get ids => _byId.keys;
  PlayerStats? read(String id) => _byId[id];
  PlayerStats _of(String id) => _byId.putIfAbsent(id, PlayerStats.new);

  /// A copy with ephemeral (generated-player) entries removed — what gets
  /// written to disk so a unique instance never leaks into a future session.
  PlayerStatsBook persistable() => PlayerStatsBook({
        for (final e in _byId.entries)
          if (!isEphemeral(e.key)) e.key: e.value,
      });

  Map<String, dynamic> toJson() =>
      {for (final e in _byId.entries) e.key: e.value.toJson()};

  static PlayerStatsBook fromJson(Map<String, dynamic> j) => PlayerStatsBook({
        for (final e in j.entries)
          e.key: PlayerStats.fromJson(e.value as Map<String, dynamic>),
      });

  String encode() => jsonEncode(toJson());
  static PlayerStatsBook decode(String s) {
    if (s.trim().isEmpty) return PlayerStatsBook();
    return fromJson(jsonDecode(s) as Map<String, dynamic>);
  }

  /// The identity used for the human seat; reads of it are kept per-observer.
  static const String humanIdentity = 'human';

  /// Folds one completed hand into the book. [identityOf] maps a seat player id
  /// (e.g. `bot_2`) to its stable identity (`profile.id`, `gen:<seat>`, or
  /// `'human'`); seats with no mapping are skipped. Only observed action is used.
  ///
  /// Each non-human seat's own play accrues to `<identity>`. The human's play is
  /// folded separately into `me@<observer>` for every *other* seat in the hand,
  /// so each opponent builds its own read of the human from only the hands it
  /// actually shared with them.
  void observe(HandHistory hand, String? Function(String seatId) identityOf) {
    final replay = _HandReplay(hand);
    final seatIdentity = <String, String>{}; // seat playerId → identity
    String? humanSeatId;
    for (final p in hand.players) {
      final id = identityOf(p.id);
      if (id == null) continue;
      seatIdentity[p.id] = id;
      if (id == humanIdentity) humanSeatId = p.id;
    }

    // Each non-human seat's own observed play.
    for (final entry in seatIdentity.entries) {
      if (entry.value == humanIdentity) continue;
      final r = replay.forSeat(entry.key);
      if (r != null) _apply(r, _of(entry.value));
    }

    // The human's play, recorded once per observer that shared this hand, plus
    // once under `human` as the human's own self-view (their HUD stats — never
    // read by a bot, which always consults its private `me@…` impression).
    if (humanSeatId != null) {
      final hr = replay.forSeat(humanSeatId);
      if (hr != null) {
        _apply(hr, _of(humanIdentity));
        for (final entry in seatIdentity.entries) {
          if (entry.key == humanSeatId) continue;
          _apply(hr, _of(meKey(entry.value)));
        }
      }
    }
  }

  /// Folds one hand's observed flags [r] into a running [s].
  static void _apply(_SeatFlags r, PlayerStats s) {
    s.decay(); // fade prior totals so recent hands dominate the read
    s.hands++;
    if (r.vpip) s.vpip++;
    if (r.pfr) s.pfr++;
    if (r.threeBetOpp) {
      s.threeBetOpp++;
      if (r.threeBet) s.threeBet++;
    }
    if (r.faced3bet) {
      s.faced3bet++;
      if (r.foldTo3bet) s.foldTo3bet++;
    }
    if (r.squeezeOpp) {
      s.squeezeOpp++;
      if (r.squeeze) s.squeeze++;
    }
    if (r.stealOpp) {
      s.stealOpp++;
      if (r.steal) s.steal++;
    }
    if (r.blindStealFaced) {
      s.blindStealFaced++;
      if (r.foldBlindSteal) s.foldBlindSteal++;
    }
    if (r.cbetOpp) {
      s.cbetOpp++;
      if (r.cbet) s.cbet++;
    }
    if (r.cbetFaced) {
      s.cbetFaced++;
      if (r.foldToCbet) s.foldToCbet++;
    }
    s.postAggr += r.postAggr;
    s.postCalls += r.postCalls;
  }
}

/// Per-seat boolean/counter flags derived by replaying one hand's action list
/// with positions. Internal to [PlayerStatsBook.observe].
class _SeatFlags {
  bool vpip = false, pfr = false;
  bool threeBetOpp = false, threeBet = false;
  bool faced3bet = false, foldTo3bet = false;
  bool squeezeOpp = false, squeeze = false;
  bool stealOpp = false, steal = false;
  bool blindStealFaced = false, foldBlindSteal = false;
  bool cbetOpp = false, cbet = false;
  bool cbetFaced = false, foldToCbet = false;
  int postAggr = 0, postCalls = 0;
}

class _HandReplay {
  _HandReplay(HandHistory hand) {
    _run(hand);
  }

  final Map<String, _SeatFlags> _flags = {};
  _SeatFlags? forSeat(String id) => _flags[id];

  void _run(HandHistory hand) {
    final players = hand.players;
    final n = players.length;
    if (n < 2) return;
    final btn = players.indexWhere((p) => p.isButton).clamp(0, n - 1);
    // Offset from the button: 0 = button, 1 = SB, 2 = BB, ... (heads-up: the
    // button is the SB). "Steal seats" are the button and cutoff (n-1) — plus
    // the SB stealing the BB — where a first-in open is usually a steal.
    int offset(int idx) => (idx - btn + n) % n;
    bool inBlinds(int idx) => n == 2
        ? offset(idx) <= 1
        : (offset(idx) == 1 || offset(idx) == 2);
    bool isStealSeat(int idx) {
      final o = offset(idx);
      if (n == 2) return o == 0; // button/SB opens vs the BB
      return o == 0 || o == n - 1 || o == 1; // BTN, CO, SB
    }

    final seatOf = {for (var i = 0; i < n; i++) players[i].id: i};
    final flags = {for (final p in players) p.id: _SeatFlags()};

    // ---- Preflop ----------------------------------------------------------
    var raiseCount = 0; // voluntary raises so far preflop
    var callers = 0; // callers of the current open (for squeeze detection)
    String? lastRaiser;
    final acted = <String>{};
    for (final a in hand.actions.where((a) => a.street == BettingRound.preflop)) {
      final f = flags[a.playerId]!;
      final idx = seatOf[a.playerId]!;
      final facingOpen = raiseCount >= 1;
      final firstIn = raiseCount == 0 && !acted.contains(a.playerId);

      // Opportunities are assessed at the moment the player first faces the spot.
      if (facingOpen && !f.threeBetOpp && !f.faced3bet) {
        // Facing a single raise with the option to reraise: a 3-bet spot (a
        // second raise makes it a 4-bet spot, still "reraise" for our purposes).
        f.threeBetOpp = true;
        if (callers >= 1) f.squeezeOpp = true;
        if (inBlinds(idx) && raiseCount == 1 && _openWasSteal(lastRaiser, seatOf,
            isStealSeat)) {
          f.blindStealFaced = true;
        }
      }
      if (firstIn && isStealSeat(idx)) f.stealOpp = true;

      switch (a.type) {
        case ActionType.fold:
          if (f.faced3bet) f.foldTo3bet = true;
          if (f.blindStealFaced) f.foldBlindSteal = true;
        case ActionType.check:
          break;
        case ActionType.call:
          f.vpip = true;
          if (raiseCount >= 1) callers++;
        case ActionType.bet:
        case ActionType.raise:
        case ActionType.allIn:
          // An aggressive preflop action. Blinds are posted outside the action
          // list, so any raise here is voluntary.
          final aggressive = a.type != ActionType.allIn || _isRaiseAllIn(a);
          if (aggressive) {
            f.vpip = true;
            f.pfr = true;
            if (facingOpen) {
              f.threeBet = true;
              if (f.squeezeOpp) f.squeeze = true;
              // The prior open now faces a reraise.
              final opener = flags[lastRaiser];
              if (opener != null) opener.faced3bet = true;
            } else if (firstIn && isStealSeat(idx)) {
              f.steal = true;
            }
            raiseCount++;
            callers = 0;
            lastRaiser = a.playerId;
          } else {
            f.vpip = true; // a calling all-in still puts chips in
          }
      }
      acted.add(a.playerId);
    }

    // ---- Postflop (c-bet + aggression factor) -----------------------------
    final preflopAggressor = lastRaiser;
    for (final street in [BettingRound.flop, BettingRound.turn, BettingRound.river]) {
      final streetActions =
          hand.actions.where((a) => a.street == street).toList();
      if (streetActions.isEmpty) continue;
      var betOpened = false;
      String? aggressor;
      for (final a in streetActions) {
        final f = flags[a.playerId]!;
        // Flop c-bet: the preflop aggressor's first bet before anyone else bet.
        if (street == BettingRound.flop && a.playerId == preflopAggressor &&
            !f.cbetOpp && !betOpened) {
          f.cbetOpp = true;
          if (a.type == ActionType.bet ||
              (a.type == ActionType.allIn && _isRaiseAllIn(a))) {
            f.cbet = true;
          }
        }
        // Facing a flop c-bet from the preflop aggressor.
        if (street == BettingRound.flop &&
            aggressor == preflopAggressor &&
            betOpened &&
            !f.cbetFaced &&
            a.playerId != preflopAggressor) {
          f.cbetFaced = true;
          if (a.type == ActionType.fold) f.foldToCbet = true;
        }
        switch (a.type) {
          case ActionType.bet:
          case ActionType.raise:
            f.postAggr++;
            betOpened = true;
            aggressor = a.playerId;
          case ActionType.allIn:
            if (_isRaiseAllIn(a)) {
              f.postAggr++;
              betOpened = true;
              aggressor = a.playerId;
            } else {
              f.postCalls++;
            }
          case ActionType.call:
            f.postCalls++;
          case ActionType.fold:
          case ActionType.check:
            break;
        }
      }
    }

    _flags.addAll(flags);
  }

  // An all-in with a positive "to" amount that exceeds a prior call is treated
  // as aggressive; the recorder stores the total for bet/raise/all-in, so we
  // approximate: an all-in is aggressive unless it's clearly a flat call. We
  // lack the facing amount here, so count all-ins as aggressive (the common
  // case for our purposes); a calling all-in is rare and low-impact on rates.
  bool _isRaiseAllIn(ActionRecord a) => true;

  bool _openWasSteal(
    String? opener,
    Map<String, int> seatOf,
    bool Function(int) isStealSeat,
  ) {
    if (opener == null) return false;
    final idx = seatOf[opener];
    return idx != null && isStealSeat(idx);
  }
}
