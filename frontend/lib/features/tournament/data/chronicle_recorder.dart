import 'package:monte/core/domain/ai/player_profile.dart';
import 'package:monte/core/domain/engine/actions.dart';
import 'package:monte/core/domain/engine/game.dart';
import 'package:monte/core/domain/engine/hand_evaluator.dart';
import 'package:monte/core/domain/engine/player.dart';
import 'package:monte/core/domain/hand_history.dart';
import 'package:monte/core/domain/ai/trigger_observer.dart';
import 'package:monte/features/tournament/data/replay_builder.dart';
import 'package:monte/features/tournament/domain/tournament_chronicle.dart';
import 'package:monte/features/tournament/domain/tournament_snapshot.dart';
import 'package:monte/features/tournament/domain/tournament_state.dart';

/// Translates finished engine hands into the factual records the
/// [TournamentChronicle] narrates from.
///
/// Split out of `TournamentController` because it is a distinct job: the
/// controller runs the tournament, this observes it. Everything here is real
/// engine output — hole cards and the full runout — so a recap of an *off-table*
/// pot honestly reports what was shown down.
///
/// Only active during interactive play ([enabled]); headless sims skip it so a
/// huge field stays fast.
class ChronicleRecorder {
  ChronicleRecorder({
    required this.chronicle,
    required this.enabled,
    required this.kindForSeat,
    required this.profileForSeat,
  });

  final TournamentChronicle chronicle;
  final bool enabled;

  /// Whether a seat is the human, a pro, or an amateur.
  final StandingKind Function(String seatId) kindForSeat;

  /// A seat's personality, or null for the human / untracked seats.
  final PlayerProfile? Function(String seatId) profileForSeat;

  /// Snapshots the active field as the start of a level: chips (to measure the
  /// level's swings and detect busts), names, kinds, and which seats are real
  /// chosen personalities rather than anonymous filler.
  void beginLevel(Iterable<TournamentPlayer> active) {
    if (!enabled) return;
    final chips = <String, int>{};
    final names = <String, String>{};
    final kinds = <String, StandingKind>{};
    final personalities = <String>{};
    for (final p in active) {
      chips[p.id] = p.chips;
      names[p.id] = p.name;
      kinds[p.id] = kindForSeat(p.id);
      final prof = profileForSeat(p.id);
      if (prof != null && !prof.generated) personalities.add(p.id);
    }
    chronicle.beginLevel(chips, names, kinds, personalities);
  }

  /// Builds a [HandDigest] from a completed [game] (pre-hand chips in [pre]) and
  /// folds it into the chronicle.
  void recordHand(
    PokerGame game, {
    required Map<String, int> pre,
    required int tableId,
    required Set<String> busted,
    required int levelIndex,
    required int averageStack,
    bool humanTable = false,
    List<String> notables = const [],
    List<ActionRecord> actions = const [],
    List<FiredTrigger> firedTriggers = const [],
  }) {
    if (!enabled) return;

    final showdown = _showdown(game, pre);
    final winners = [
      for (final r in game.results)
        if (r.netWon > 0) r.player.id,
    ];
    final pot = game.results.fold<int>(
      0,
      (a, r) => a + (r.netWon > 0 ? r.netWon : 0),
    );
    final replay = ReplayBuilder.build(
      game: game,
      actions: actions,
      preChips: pre,
      bigBlind: game.bigBlind,
      profileForSeat: profileForSeat,
      firedTriggers: firedTriggers,
    );

    final preflop = _humanPreflopFacts(game, actions);

    chronicle.record(
      HandDigest(
        levelIndex: levelIndex,
        tableId: tableId,
        notables: notables,
        pot: pot,
        showdown: showdown,
        winners: winners,
        busted: busted.toList(),
        humanTable: humanTable,
        replay: replay,
        vpipHuman: preflop.vpip,
        rfiHuman: preflop.rfi,
        stealChanceHuman: preflop.stealChance,
        stealAttemptHuman: preflop.stealAttempt,
      ),
      avgStack: averageStack,
    );
  }

  /// The human's preflop play this hand, for "how you played this level" —
  /// derived from the ordered [actions] rather than tracked live, since
  /// nothing upstream needed this level of preflop detail before. Only the
  /// human's *first* preflop action is examined: what happens after they've
  /// already voluntarily entered the pot isn't a steal or an open anymore.
  ///
  /// Position is read off [PokerGame.buttonIndex] and the fixed seat order in
  /// [PokerGame.players] — the same button-relative rank every other seat/steal
  /// calculation in this codebase uses (`OpenRanges`, `ProfilePolicy`), not
  /// live fold state, which by the time a hand is fully recorded no longer
  /// reflects who was live when the human actually acted.
  ({bool vpip, bool rfi, bool stealChance, bool stealAttempt})
      _humanPreflopFacts(PokerGame game, List<ActionRecord> actions) {
    Player? human;
    for (final p in game.players) {
      if (p.isHuman) {
        human = p;
        break;
      }
    }
    if (human == null) {
      return (vpip: false, rfi: false, stealChance: false, stealAttempt: false);
    }

    final n = game.players.length;
    final heroIdx = game.players.indexOf(human);
    // Heads-up, the button posts the small blind — the same special case
    // `AmateurPolicy._isSmallBlind` already carries.
    final sbIndex = n == 2 ? game.buttonIndex : (game.buttonIndex + 1) % n;
    final rank = (heroIdx - sbIndex + n) % n; // 0 = SB … n-1 = button
    // A steal spot: the small blind (one player left to act) or the two seats
    // right before it (cutoff, button).
    final lateSeat = rank == 0 || rank == n - 1 || rank == n - 2;

    // Whether anyone — a raiser *or a limper* — has voluntarily entered the
    // pot ahead of the human. A raise over a live limper is an isolation
    // raise, not a steal, and isn't RFI either: both terms mean nobody had
    // acted before you, not merely "nobody has raised yet".
    var enteredYet = false;
    var vpip = false, rfi = false, stealChance = false, stealAttempt = false;
    var seenHuman = false;
    for (final a in actions) {
      if (a.street != BettingRound.preflop || seenHuman) continue;
      final isRaiseType = a.type == ActionType.raise ||
          a.type == ActionType.bet ||
          a.type == ActionType.allIn;
      final isVoluntary = isRaiseType || a.type == ActionType.call;
      if (a.playerId == human.id) {
        seenHuman = true;
        vpip = isVoluntary;
        rfi = !enteredYet && isRaiseType;
        if (!enteredYet && lateSeat) {
          stealChance = true;
          stealAttempt = isRaiseType;
        }
        continue;
      }
      if (isVoluntary) enteredYet = true;
    }
    return (
      vpip: vpip,
      rfi: rfi,
      stealChance: stealChance,
      stealAttempt: stealAttempt
    );
  }

  /// What each contender held at showdown, including whether they were ahead on
  /// the flop — the marker that distinguishes a genuine suck-out from a hand
  /// that was simply best throughout. Empty when the hand ended before a river.
  List<ShowdownEntry> _showdown(PokerGame game, Map<String, int> pre) {
    final contenders = game.players.where((p) => p.inHand).toList();
    if (contenders.length < 2 || game.board.length < 5) return const [];

    final flop = game.board.take(3).toList();
    HandValue? bestFlop;
    String? bestFlopId;
    for (final p in contenders) {
      if (!p.isAllIn) continue;
      final v = HandEvaluator.evaluate([...p.hole, ...flop]);
      if (bestFlop == null || v > bestFlop) {
        bestFlop = v;
        bestFlopId = p.id;
      }
    }

    return [
      for (final p in contenders)
        ShowdownEntry(
          id: p.id,
          name: p.name,
          kind: kindForSeat(p.id),
          wentAllIn: p.isAllIn,
          net: p.stack - (pre[p.id] ?? p.stack),
          rank: HandEvaluator.evaluate([...p.hole, ...game.board]).rank,
          aheadOnFlop: p.id == bestFlopId,
        ),
    ];
  }

}
