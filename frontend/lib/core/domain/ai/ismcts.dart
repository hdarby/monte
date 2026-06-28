import 'dart:math';

import 'package:monte/core/domain/ai/action_abstraction.dart';
import 'package:monte/core/domain/ai/determinizer.dart';
import 'package:monte/core/domain/ai/opponent_model.dart';
import 'package:monte/core/domain/ai/personality.dart';
import 'package:monte/core/domain/ai/personality_policy.dart';
import 'package:monte/core/domain/engine/actions.dart';
import 'package:monte/core/domain/engine/bot.dart';
import 'package:monte/core/domain/engine/decision_policy.dart';
import 'package:monte/core/domain/engine/game.dart';
import 'package:monte/core/domain/engine/player.dart';

/// Tunables for the ISMCTS search.
class IsmctsConfig {
  const IsmctsConfig({
    this.iterations = 1500,
    this.explorationConstant = 1.4,
    this.biasWeight = 2.0,
    this.abstraction = const ActionAbstraction(),
    this.rolloutGuard = 400,
  });

  /// Number of determinized playouts per decision. More = stronger but slower.
  final int iterations;

  /// UCB1 exploration weight `C`. Rewards are normalized to ~[-1, 1], so the
  /// classic √2 ≈ 1.4 is a sensible default.
  final double explorationConstant;

  /// Progressive-bias weight pulling selection toward the default policy's
  /// recommended action, decaying as `biasWeight / (1 + visits)`. Makes a
  /// shallow search default to sound play instead of noisy over-exploration;
  /// 0 disables it (pure UCB1).
  final double biasWeight;

  /// How continuous bets are discretized into the search's move set.
  final ActionAbstraction abstraction;

  /// Safety cap on actions per rollout, so a pathological line can't hang.
  final int rolloutGuard;
}

/// Information Set Monte Carlo Tree Search for No-Limit Hold'em.
///
/// Imperfect information is handled by **determinization**: each iteration
/// samples a concrete world (opponent holes + future board) consistent with the
/// hero's view, then plays it forward through the real engine. The search tree
/// branches only on the *hero's* decisions, selected by UCB1; opponents act via
/// a fast default policy during both descent and rollout. The action returned
/// is the hero's most-visited move at the root.
class IsmctsEngine implements DecisionPolicy {
  IsmctsEngine({
    IsmctsConfig? config,
    Random? random,
    PersonalityProfile? profile,
    DecisionPolicy? rolloutPolicy,
    OpponentModel? opponentModel,
    double exploitBase = 0,
  }) : _config = config ?? const IsmctsConfig(),
       _random = random ?? Random(),
       _profile = profile ?? const PersonalityProfile.balanced(),
       // ignore: prefer_initializing_formals
       _opponentModel = opponentModel,
       // ignore: prefer_initializing_formals
       _exploitBase = exploitBase {
    _determinizer = Determinizer(random: _random);
    _rolloutPolicy = rolloutPolicy ?? BotStrategy(random: _random);
  }

  final IsmctsConfig _config;
  final Random _random;
  final PersonalityProfile _profile;
  late final Determinizer _determinizer;
  late final DecisionPolicy _rolloutPolicy;

  /// Opponent reads + how strongly to exploit them. When [_exploitBase] > 0 and a
  /// model is present, opponents in rollouts are played by a style lerped from
  /// neutral toward their observed tendencies by `exploitBase × confidence`, so
  /// exploitation emerges from the search. exploitBase =
  /// (1 − gto_adherence) × exploitative_weight × weight_on_opponent_history.
  final OpponentModel? _opponentModel;
  final double _exploitBase;

  // Root context, captured per [chooseAction] call.
  late List<int> _rootStacks;
  late double _chipScale;
  late int _heroIndex;
  late String _heroId;
  Map<String, DecisionPolicy> _opponentPolicies = const {};

  /// [DecisionPolicy] entry point — equivalent to [chooseAction].
  @override
  GameAction decide(PokerGame game, Player player) =>
      chooseAction(game, player);

  /// Chooses an action for [hero], who must be the player currently to act.
  GameAction chooseAction(PokerGame game, Player hero) {
    _heroIndex = game.players.indexWhere((p) => p.id == hero.id);
    _heroId = hero.id;
    _opponentPolicies = _buildOpponentPolicies(game, hero);
    _rootStacks = [for (final p in game.players) p.stack];
    // Total chips in play is conserved, so it bounds every payoff: use it to
    // normalize rewards into ~[-1, 1] for a stable exploration constant.
    _chipScale = (_rootStacks.fold<int>(0, (s, v) => s + v) + game.pot)
        .toDouble()
        .clamp(1, double.infinity);

    final root = _Node();
    for (var i = 0; i < _config.iterations; i++) {
      _descend(root, _determinizer.determinize(game, hero));
    }

    // Robust choice: the most-visited root action (tie-break by mean reward).
    final actions = _config.abstraction.actionsFor(game, hero);
    var bestKey = 0;
    var bestVisits = -1;
    var bestMean = -double.infinity;
    for (var k = 0; k < actions.length; k++) {
      final e = root.edges[k];
      if (e == null) continue;
      final mean = e.visits == 0 ? -double.infinity : e.totalReward / e.visits;
      if (e.visits > bestVisits ||
          (e.visits == bestVisits && mean > bestMean)) {
        bestVisits = e.visits;
        bestMean = mean;
        bestKey = k;
      }
    }
    return actions[bestKey];
  }

  /// One iteration: descend the hero tree (opponents auto-played) to a leaf,
  /// roll out, and back up the normalized hero reward. Returns that reward.
  double _descend(_Node node, PokerGame state) {
    _autoPlayToHero(state);
    if (state.currentPlayer == null) return _heroPayoff(state);

    final hero = state.players[_heroIndex];
    final actions = _config.abstraction.actionsFor(state, hero);
    // The default policy's pick for this (determinized) spot, used to bias
    // selection toward sound play while visit counts are low.
    final recommended = _recommendedKey(state, hero, actions);
    final key = _select(node, actions, recommended);
    state.applyAction(actions[key]);

    final edge = node.edges[key]!;
    final double reward;
    if (edge.child == null) {
      edge.child = _Node();
      reward = _rollout(state);
    } else {
      reward = _descend(edge.child!, state);
    }

    node.visits++;
    edge.visits++;
    edge.totalReward += reward;
    return reward;
  }

  /// UCB1 selection with progressive bias toward [recommended] (the default
  /// policy's pick): try every untried action once — the recommended one first —
  /// then exploit/explore with a decaying bias term.
  int _select(_Node node, List<GameAction> actions, int recommended) {
    final untried = <int>[];
    for (var k = 0; k < actions.length; k++) {
      final e = node.edges.putIfAbsent(k, () => _Edge());
      if (e.visits == 0) untried.add(k);
    }
    if (untried.isNotEmpty) {
      return untried.contains(recommended)
          ? recommended
          : untried[_random.nextInt(untried.length)];
    }

    final logN = log(node.visits.toDouble());
    var best = 0;
    var bestVal = -double.infinity;
    for (var k = 0; k < actions.length; k++) {
      final e = node.edges[k]!;
      final bias = k == recommended
          ? _config.biasWeight / (1 + e.visits)
          : 0.0;
      final value =
          e.totalReward / e.visits +
          _config.explorationConstant * sqrt(logN / e.visits) +
          bias;
      if (value > bestVal) {
        bestVal = value;
        best = k;
      }
    }
    return best;
  }

  /// The abstracted action that best matches what [_rolloutPolicy] would do at
  /// this spot — same type, nearest size. Used as the progressive-bias target.
  int _recommendedKey(PokerGame state, Player hero, List<GameAction> actions) {
    final rec = _rolloutPolicy.decide(state, hero);
    var best = 0;
    var bestScore = -double.infinity;
    for (var k = 0; k < actions.length; k++) {
      final a = actions[k];
      // Prefer same action type; among those, the nearest bet/raise size.
      final score =
          (a.type == rec.type ? 0.0 : -1e6) - (a.amount - rec.amount).abs();
      if (score > bestScore) {
        bestScore = score;
        best = k;
      }
    }
    return best;
  }

  /// Advances [state] by letting opponents act (their modelled policy) until it
  /// is the hero's turn or the hand is over.
  void _autoPlayToHero(PokerGame state) {
    var guard = 0;
    while (state.currentPlayer != null &&
        state.currentPlayer!.id != _heroId) {
      final p = state.currentPlayer!;
      state.applyAction(_policyFor(p).decide(state, p));
      if (++guard > _config.rolloutGuard) break;
    }
  }

  /// Plays [state] to terminal — opponents by their modelled policy, the hero by
  /// the default — then scores.
  double _rollout(PokerGame state) {
    var guard = 0;
    while (state.currentPlayer != null) {
      final p = state.currentPlayer!;
      state.applyAction(_policyFor(p).decide(state, p));
      if (++guard > _config.rolloutGuard) break;
    }
    return _heroPayoff(state);
  }

  /// The policy that plays seat [p] inside the search: the hero uses the default
  /// rollout policy; opponents use their exploit-modelled policy when one was
  /// built, else the default.
  DecisionPolicy _policyFor(Player p) =>
      p.id == _heroId ? _rolloutPolicy : (_opponentPolicies[p.id] ?? _rolloutPolicy);

  /// Builds an opponent's rollout policy by lerping a neutral style toward their
  /// observed style by `exploitBase × confidence` — so a high-exploit, confident
  /// read shifts the model fully onto their tendencies, while a pure-GTO bot
  /// (exploitBase 0) or an unread opponent stays neutral (no modelling cost).
  Map<String, DecisionPolicy> _buildOpponentPolicies(
    PokerGame game,
    Player hero,
  ) {
    final model = _opponentModel;
    if (model == null || _exploitBase <= 0) return const {};
    final out = <String, DecisionPolicy>{};
    for (final p in game.players) {
      if (p.id == hero.id) continue;
      final obs = model.of(p.id);
      final w = (_exploitBase * obs.confidence).clamp(0.0, 1.0);
      if (w < 0.02) continue; // not enough signal to bother modelling
      out[p.id] = PersonalityPolicy(_lerpToNeutral(obs.readProfile(), w),
          random: _random);
    }
    return out;
  }

  /// `w = 0` → balanced (neutral); `w = 1` → the read profile unchanged.
  PersonalityProfile _lerpToNeutral(PersonalityProfile p, double w) {
    double m(double v) => 0.5 + (v - 0.5) * w;
    return PersonalityProfile(
      aggression: m(p.aggression),
      bluffFrequency: m(p.bluffFrequency),
      tightness: m(p.tightness),
      riskTolerance: m(p.riskTolerance),
    );
  }

  /// Hero's net chips for the rest of the hand, normalized to ~[-1, 1] and run
  /// through the personality's risk-utility curve (identity when risk-neutral).
  double _heroPayoff(PokerGame state) => _profile.utility(
    (state.players[_heroIndex].stack - _rootStacks[_heroIndex]) / _chipScale,
  );
}

/// A hero decision point in the search tree.
class _Node {
  int visits = 0;
  final Map<int, _Edge> edges = {};
}

/// Statistics for one abstracted action out of a node.
class _Edge {
  int visits = 0;
  double totalReward = 0;
  _Node? child;
}
