import 'package:meta/meta.dart';

import 'package:monte/core/domain/ai/player_profile.dart';
import 'package:monte/core/domain/engine/actions.dart';
import 'package:monte/core/domain/engine/game.dart' show BettingRound;
import 'package:monte/core/domain/hand_history.dart';

/// A player's running emotional state within a session.
///
/// Session-scoped and never persisted: nobody sits down still steaming about a
/// pot they lost last week, and a tilt that survived a restart would be a bug
/// rather than a feature.
@immutable
class MentalState {
  const MentalState({this.tiltPressure = 0, this.handsSinceVpip = 0});

  /// How rattled they are, 0–1. Decays every hand.
  final double tiltPressure;

  /// Consecutive hands folded before the flop — the boredom counter.
  final int handsSinceVpip;

  /// Whether the pressure is high enough to change how they play.
  bool get isTilted => tiltPressure >= _tiltedAt;

  static const _tiltedAt = 0.35;

  MentalState copyWith({double? tiltPressure, int? handsSinceVpip}) =>
      MentalState(
        tiltPressure: tiltPressure ?? this.tiltPressure,
        handsSinceVpip: handsSinceVpip ?? this.handsSinceVpip,
      );

  @override
  String toString() =>
      'MentalState(tilt=${tiltPressure.toStringAsFixed(2)}, '
      'folded=$handsSinceVpip)';
}

/// How a finished hand moves a player's mental state. Pure, so it can be tested
/// without a table and ported alongside the rest of the domain.
class MentalModel {
  const MentalModel();

  /// Losing a pot at least this big, in big blinds, is what starts it. Scaled
  /// per player by their tilt resistance.
  static const _baseThresholdBb = 18.0;

  /// Folds a player will sit through before boredom starts widening them.
  static const _patienceHands = 12;

  /// Folds beyond [_patienceHands] before boredom is at full strength.
  static const _patienceRamp = 10;

  /// Folds [state] forward over a completed [hand] as seen by [playerId].
  MentalState afterHand({
    required MentalState state,
    required PlayerProfile profile,
    required HandHistory hand,
    required String playerId,
  }) =>
      afterResult(
        state: state,
        profile: profile,
        net: hand.netFor(playerId),
        bigBlind: hand.bigBlind,
        enteredPot: _voluntarilyEntered(hand, playerId),
      );

  /// The same rules from a bare result, for callers with no [HandHistory] to
  /// hand — simulated tables in a large field never build one, and constructing
  /// thousands of them per level just to track tilt would be absurd.
  MentalState afterResult({
    required MentalState state,
    required PlayerProfile profile,
    required int net,
    required int bigBlind,
    required bool enteredPot,
  }) {
    final resistance =
        profile.behavioralModifiers.tiltResistance.clamp(0.0, 1.0);
    final bb = bigBlind <= 0 ? 1 : bigBlind;

    // Decay first, so a bad hand's own contribution is not immediately eroded.
    // A resistant player sheds it faster as well as accumulating less.
    final decay = 0.90 - 0.06 * resistance;
    var pressure = state.tiltPressure * decay;

    final lostBb = net < 0 ? -net / bb : 0.0;
    final threshold = _baseThresholdBb * (0.6 + 1.2 * resistance);
    if (lostBb >= threshold) {
      // Severity is how far past their own threshold the loss went, so the same
      // pot rattles a rec and barely registers with a professional.
      final severity = ((lostBb - threshold) / threshold).clamp(0.0, 1.5);
      pressure += (0.28 + 0.34 * severity) * (1 - resistance);
    }

    // Boredom: consecutive preflop folds nudge them toward playing something.
    final folds = enteredPot ? 0 : state.handsSinceVpip + 1;

    return MentalState(
      tiltPressure: pressure.clamp(0.0, 1.0),
      handsSinceVpip: folds,
    );
  }

  /// 0–1: how far past their patience this player is. Drives a small widening
  /// of the hands they will enter with, and resets the moment they play one.
  static double boredom(MentalState state) =>
      ((state.handsSinceVpip - _patienceHands) / _patienceRamp).clamp(0.0, 1.0);

  static bool _voluntarilyEntered(HandHistory hand, String playerId) {
    for (final a in hand.actions) {
      if (a.playerId != playerId) continue;
      if (a.street != BettingRound.preflop) break;
      if (a.type == ActionType.call ||
          a.type == ActionType.raise ||
          a.type == ActionType.bet ||
          a.type == ActionType.allIn) {
        return true;
      }
    }
    return false;
  }
}

/// A decider's read on how rattled each seat is.
///
/// The same shape as `OpponentReads`, and for the same reason: the state has to
/// outlive the policies, which are rebuilt whenever the lineup changes.
abstract class MentalReads {
  /// The state for a seat, or null when nothing is being tracked.
  MentalState? stateFor(String seatId);
}

/// Tracks every seat's mental state for one session.
class MentalTable implements MentalReads {
  MentalTable({this.model = const MentalModel()});

  final MentalModel model;
  final Map<String, MentalState> _byId = {};

  @override
  MentalState? stateFor(String seatId) => _byId[seatId];

  /// Folds one finished hand into every tracked seat's state. [profileOf]
  /// returns null for a seat with no personality, which is then left alone.
  void observe(
    HandHistory hand,
    PlayerProfile? Function(String seatId) profileOf,
  ) {
    for (final p in hand.players) {
      final profile = profileOf(p.id);
      if (profile == null) continue;
      _byId[p.id] = model.afterHand(
        state: _byId[p.id] ?? const MentalState(),
        profile: profile,
        hand: hand,
        playerId: p.id,
      );
    }
  }

  /// Folds a finished hand in from bare results, for callers with no
  /// [HandHistory] (see [MentalModel.afterResult]).
  void observeResults({
    required Iterable<String> seatIds,
    required int bigBlind,
    required PlayerProfile? Function(String seatId) profileOf,
    required int Function(String seatId) netOf,
    required bool Function(String seatId) enteredPot,
  }) {
    for (final id in seatIds) {
      final profile = profileOf(id);
      if (profile == null) continue;
      _byId[id] = model.afterResult(
        state: _byId[id] ?? const MentalState(),
        profile: profile,
        net: netOf(id),
        bigBlind: bigBlind,
        enteredPot: enteredPot(id),
      );
    }
  }

  void clear() => _byId.clear();

  @override
  String toString() => _byId.entries
      .where((e) => e.value.tiltPressure > 0.01)
      .map((e) => '${e.key}:${e.value.tiltPressure.toStringAsFixed(2)}')
      .join(' ');
}
