import 'package:meta/meta.dart';

import 'package:monte/core/domain/hand_history.dart';

/// A **complete, full-information** record of one played hand, for offline model
/// tuning. Unlike [HandHistory] — which masks folded/mucked cards so bots get no
/// free information — this keeps **every** player's hole cards, plus position,
/// stacks, per-street actions, and the model each seat was playing.
///
/// It is written only to the on-disk tuning store and read only by the metrics
/// analyzer / export. It must **never** be handed to a `DecisionPolicy` or the
/// `OpponentModel`; that isolation is what preserves the "no free information"
/// invariant.
@immutable
class EvalHand {
  const EvalHand({
    required this.handNumber,
    required this.smallBlind,
    required this.bigBlind,
    required this.players,
    required this.actions,
    required this.board,
    required this.results,
    this.sessionId,
    this.timestampMs,
    this.ante = 0,
    this.playersRemaining,
    this.decisions = const [],
  });

  final int handNumber;
  final int smallBlind;
  final int bigBlind;

  /// Which sitting this hand belongs to, and when it was played.
  ///
  /// Without these a reviewer cannot say "this session versus last": the only
  /// boundary marker was `handNumber` rolling back to 1, which merges two
  /// sittings played back to back and splits one that reloaded a save.
  final String? sessionId;
  final int? timestampMs;

  /// Tournament context. A 9 BB shove and a fold near a pay jump can only be
  /// judged against the level and the field; without them every hand has to be
  /// graded as if it were a cash game, which misreads push/fold and the bubble,
  /// and makes a tight small blind look like a leak when it is an ante-less
  /// level.
  final int ante;
  final int? playersRemaining;

  /// Per-decision coaching record for the human seat (empty otherwise).
  final List<EvalDecision> decisions;
  final List<EvalHandPlayer> players;
  final List<ActionRecord> actions;
  final List<String> board;
  final List<HandResultRecord> results;

  factory EvalHand.fromJson(Map<String, dynamic> j) => EvalHand(
    handNumber: j['handNumber'] as int,
    smallBlind: j['smallBlind'] as int,
    bigBlind: j['bigBlind'] as int,
    players: [
      for (final p in (j['players'] as List).cast<Map<String, dynamic>>())
        EvalHandPlayer.fromJson(p),
    ],
    actions: [
      for (final a in (j['actions'] as List).cast<Map<String, dynamic>>())
        ActionRecord.fromJson(a),
    ],
    board: (j['board'] as List).cast<String>(),
    results: [
      for (final r in (j['results'] as List).cast<Map<String, dynamic>>())
        HandResultRecord.fromJson(r),
    ],
    sessionId: j['sessionId'] as String?,
    timestampMs: j['timestampMs'] as int?,
    ante: (j['ante'] as int?) ?? 0,
    playersRemaining: j['playersRemaining'] as int?,
    decisions: [
      for (final d in (j['decisions'] as List? ?? const [])
          .cast<Map<String, dynamic>>())
        EvalDecision.fromJson(d),
    ],
  );

  Map<String, dynamic> toJson() => {
    'handNumber': handNumber,
    'smallBlind': smallBlind,
    'bigBlind': bigBlind,
    'players': [for (final p in players) p.toJson()],
    'actions': [for (final a in actions) a.toJson()],
    'board': board,
    'results': [for (final r in results) r.toJson()],
    if (sessionId != null) 'sessionId': sessionId,
    if (timestampMs != null) 'timestampMs': timestampMs,
    if (ante > 0) 'ante': ante,
    if (playersRemaining != null) 'playersRemaining': playersRemaining,
    if (decisions.isNotEmpty)
      'decisions': [for (final d in decisions) d.toJson()],
  };
}

/// One decision the human faced, with what the coach would have done.
///
/// This is what turns frequency coaching into decision coaching. Frequencies say
/// "you call too much"; these say *which* calls, and what they cost. The coach
/// already computes all of it live for the in-hand panel and then throws it
/// away, so recording it is wiring rather than new analysis.
///
/// [evLost] is the honest scoreboard: the recommended action's EV minus the EV
/// of the one actually taken, in big blinds, floored at zero. Summed over a
/// session it is a progress number that tightens far faster than win rate.
@immutable
class EvalDecision {
  const EvalDecision({
    required this.playerId,
    required this.street,
    required this.actualType,
    required this.actualAmount,
    required this.potBb,
    required this.toCallBb,
    required this.spr,
    required this.equity,
    this.potOdds,
    required this.chosenLabel,
    required this.chosenEv,
    required this.bestLabel,
    required this.bestEv,
  });

  final String playerId;
  final String street;
  final String actualType;
  final int actualAmount;

  final double potBb;
  final double toCallBb;
  final double spr;
  final double equity;
  final double? potOdds;

  /// The coach's line for the action actually taken, and for its own pick.
  final String chosenLabel;
  final double chosenEv;
  final String bestLabel;
  final double bestEv;

  /// Big blinds of expected value given up, never negative.
  double get evLost => (bestEv - chosenEv) > 0 ? bestEv - chosenEv : 0;

  /// Whether the action taken was the coach's own recommendation.
  bool get followedCoach => chosenLabel == bestLabel;

  factory EvalDecision.fromJson(Map<String, dynamic> j) => EvalDecision(
        playerId: j['playerId'] as String,
        street: j['street'] as String,
        actualType: j['actualType'] as String,
        actualAmount: (j['actualAmount'] as num?)?.toInt() ?? 0,
        potBb: (j['potBb'] as num).toDouble(),
        toCallBb: (j['toCallBb'] as num).toDouble(),
        spr: (j['spr'] as num).toDouble(),
        equity: (j['equity'] as num).toDouble(),
        potOdds: (j['potOdds'] as num?)?.toDouble(),
        chosenLabel: j['chosenLabel'] as String,
        chosenEv: (j['chosenEv'] as num).toDouble(),
        bestLabel: j['bestLabel'] as String,
        bestEv: (j['bestEv'] as num).toDouble(),
      );

  Map<String, dynamic> toJson() => {
        'playerId': playerId,
        'street': street,
        'actualType': actualType,
        'actualAmount': actualAmount,
        'potBb': potBb,
        'toCallBb': toCallBb,
        'spr': spr,
        'equity': equity,
        if (potOdds != null) 'potOdds': potOdds,
        'chosenLabel': chosenLabel,
        'chosenEv': chosenEv,
        'bestLabel': bestLabel,
        'bestEv': bestEv,
      };
}

/// One player in an [EvalHand] — always with full hole cards, tagged with the
/// model it was playing (and that model's expected preflop targets, so tuning can
/// compare measured vs. expected).
@immutable
class EvalHandPlayer {
  const EvalHandPlayer({
    required this.id,
    required this.name,
    required this.modelId,
    required this.modelLabel,
    required this.position,
    required this.seatsFromButton,
    required this.holeCards,
    required this.startingStack,
    required this.finalStack,
    required this.folded,
    this.foldStreet,
    this.madeHand,
    this.skill,
    this.vpipTarget,
    this.pfrTarget,
    this.threeBetTarget,
  });

  final String id;
  final String name;

  /// Grouping key for tuning: a named profile's id (e.g. `H008`/`P001`), or
  /// `brain:style` for a custom bot.
  final String modelId;
  final String modelLabel;

  /// Human position label (BTN/SB/BB/UTG…/CO) and the raw offset from the button
  /// (0 = button), so metrics can reason about position numerically.
  final String position;
  final int seatsFromButton;

  final List<String> holeCards; // always full — never masked
  final int startingStack;
  final int finalStack;
  final bool folded;

  /// Street the player folded on (`preflop`/`flop`/`turn`/`river`), or null if
  /// they never folded.
  final String? foldStreet;

  /// The player's made-hand rank vs the final board (when a board was dealt).
  final String? madeHand;

  /// The model's expected targets (present for profile-based seats), for
  /// measured-vs-target tuning. Null for plain brain+style bots.
  final double? skill;
  final double? vpipTarget;
  final double? pfrTarget;
  final double? threeBetTarget;

  int get net => finalStack - startingStack;

  factory EvalHandPlayer.fromJson(Map<String, dynamic> j) => EvalHandPlayer(
    id: j['id'] as String,
    name: j['name'] as String,
    modelId: j['modelId'] as String,
    modelLabel: j['modelLabel'] as String,
    position: j['position'] as String,
    seatsFromButton: j['seatsFromButton'] as int,
    holeCards: (j['holeCards'] as List).cast<String>(),
    startingStack: j['startingStack'] as int,
    finalStack: j['finalStack'] as int,
    folded: j['folded'] as bool,
    foldStreet: j['foldStreet'] as String?,
    madeHand: j['madeHand'] as String?,
    skill: (j['skill'] as num?)?.toDouble(),
    vpipTarget: (j['vpipTarget'] as num?)?.toDouble(),
    pfrTarget: (j['pfrTarget'] as num?)?.toDouble(),
    threeBetTarget: (j['threeBetTarget'] as num?)?.toDouble(),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'modelId': modelId,
    'modelLabel': modelLabel,
    'position': position,
    'seatsFromButton': seatsFromButton,
    'holeCards': holeCards,
    'startingStack': startingStack,
    'finalStack': finalStack,
    'folded': folded,
    if (foldStreet != null) 'foldStreet': foldStreet,
    if (madeHand != null) 'madeHand': madeHand,
    if (skill != null) 'skill': skill,
    if (vpipTarget != null) 'vpipTarget': vpipTarget,
    if (pfrTarget != null) 'pfrTarget': pfrTarget,
    if (threeBetTarget != null) 'threeBetTarget': threeBetTarget,
  };
}

/// The position label for a seat [offset] seats from the button at a table of
/// [n] players (0 = button). Heads-up: the button is the small blind.
String positionLabel(int offset, int n) {
  if (n == 2) return offset == 0 ? 'SB' : 'BB';
  switch (offset) {
    case 0:
      return 'BTN';
    case 1:
      return 'SB';
    case 2:
      return 'BB';
  }
  if (offset == n - 1) return 'CO';
  if (offset == n - 2 && n >= 7) return 'HJ';
  const early = ['UTG', 'UTG1', 'UTG2', 'MP', 'MP1', 'MP2'];
  final fromUtg = offset - 3;
  return fromUtg < early.length ? early[fromUtg] : 'MP';
}
