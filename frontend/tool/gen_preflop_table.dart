// ignore_for_file: avoid_print
//
// Offline generator for the baked preflop-strength table in
// lib/core/domain/engine/hand_strength.dart.
//
// Produces a strength in [0,1] for each of the 169 canonical starting hands by:
//   1. Monte-Carlo heads-up all-in equity vs a random hand (the real
//      HandEvaluator — one rulebook), seeded for reproducibility.
//   2. Histogram-matching those equities onto the *legacy* smooth-formula
//      distribution (weighted by combo counts), so the output distribution is
//      unchanged — existing absolute thresholds and percentile calibration keep
//      their meaning — while the ordering now reflects true equity.
//
// Run: dart tool/gen_preflop_table.dart   (paste the emitted map into
// hand_strength.dart). Not shipped; not part of the app or test suite.
import 'dart:math';

import 'package:monte/core/domain/engine/card.dart';
import 'package:monte/core/domain/engine/hand_evaluator.dart';

const _trials = 40000; // MC samples per canonical hand (SE ~0.25%, ample for ranking)

// Legacy smooth formula (the committed preflopOf) — the distribution we match.
double _legacy(int a, int b, bool suited) {
  if (a == b) return 0.50 + 0.45 * ((a - 2) / 12);
  final high = max(a, b), low = min(a, b), gap = high - low;
  var s = (high + low) / 28.0 * 0.6;
  if (suited) s += 0.08;
  if (gap == 1) s += 0.05;
  if (high == 14) s += 0.05;
  return s.clamp(0.0, 1.0);
}

int _key(int a, int b, bool suited) => a * 100 + b * 2 + (suited ? 1 : 0);

class _Hand {
  _Hand(this.a, this.b, this.suited);
  final int a, b;
  final bool suited;
  bool get isPair => a == b;
  int get weight => isPair ? 6 : (suited ? 4 : 12);
  int get key => _key(a, b, suited);
  double equity = 0;
  double legacy = 0;
}

double _equity(_Hand h, Random rng) {
  // Two concrete cards for the class.
  final heroHi = Card(Rank.values[h.a - 2], Suit.spades);
  final heroLo = Card(
    Rank.values[h.b - 2],
    h.suited ? Suit.spades : Suit.hearts,
  );
  final dead = {heroHi.code, heroLo.code};
  final deck = <Card>[
    for (final r in Rank.values)
      for (final su in Suit.values)
        if (!dead.contains(Card(r, su).code)) Card(r, su),
  ];

  var win = 0, tie = 0;
  for (var t = 0; t < _trials; t++) {
    // Fisher-Yates partial shuffle for the 7 cards we need (2 villain + 5 board).
    for (var i = 0; i < 7; i++) {
      final j = i + rng.nextInt(deck.length - i);
      final tmp = deck[i];
      deck[i] = deck[j];
      deck[j] = tmp;
    }
    final villain = [deck[0], deck[1]];
    final board = [deck[2], deck[3], deck[4], deck[5], deck[6]];
    final hero = HandEvaluator.evaluate([heroHi, heroLo, ...board]);
    final vill = HandEvaluator.evaluate([...villain, ...board]);
    final cmp = hero.compareTo(vill);
    if (cmp > 0) {
      win++;
    } else if (cmp == 0) {
      tie++;
    }
  }
  return (win + tie / 2) / _trials;
}

/// Weighted quantile: value of [sorted] (asc, with weights) at cumulative
/// fraction [p] in [0,1], via midpoint plotting positions + linear interp.
double _weightedQuantile(List<MapEntry<double, int>> sorted, double p) {
  final total = sorted.fold<int>(0, (s, e) => s + e.value);
  var cum = 0.0;
  final pts = <MapEntry<double, double>>[]; // (percentile, value)
  for (final e in sorted) {
    final mid = (cum + e.value / 2) / total;
    pts.add(MapEntry(mid, e.key));
    cum += e.value;
  }
  if (p <= pts.first.key) return pts.first.value;
  if (p >= pts.last.key) return pts.last.value;
  for (var i = 0; i < pts.length - 1; i++) {
    final lo = pts[i], hi = pts[i + 1];
    if (p >= lo.key && p <= hi.key) {
      final t = (p - lo.key) / (hi.key - lo.key);
      return lo.value + t * (hi.value - lo.value);
    }
  }
  return pts.last.value;
}

void main() {
  final rng = Random(0xC0FFEE);
  final hands = <_Hand>[];
  for (var a = 2; a <= 14; a++) {
    for (var b = 2; b <= a; b++) {
      if (a == b) {
        hands.add(_Hand(a, b, false));
      } else {
        hands.add(_Hand(a, b, true));
        hands.add(_Hand(a, b, false));
      }
    }
  }

  for (final h in hands) {
    h.equity = _equity(h, rng);
    h.legacy = _legacy(h.a, h.b, h.suited);
  }

  // Target distribution: legacy strengths, weighted by combo counts.
  final legacySorted = [
    for (final h in hands) MapEntry(h.legacy, h.weight),
  ]..sort((x, y) => x.key.compareTo(y.key));
  final total = hands.fold<int>(0, (s, h) => s + h.weight);

  // Equity percentile per hand (weighted, midpoint), then map through the
  // legacy quantile function.
  final byEquity = [...hands]..sort((x, y) => x.equity.compareTo(y.equity));
  var cum = 0.0;
  final matched = <int, double>{};
  for (final h in byEquity) {
    final p = (cum + h.weight / 2) / total;
    matched[h.key] = double.parse(
      _weightedQuantile(legacySorted, p).toStringAsFixed(4),
    );
    cum += h.weight;
  }

  // Emit as a Dart map literal, grouped for readability.
  final keys = matched.keys.toList()..sort();
  final buf = StringBuffer();
  buf.writeln('  static const Map<int, double> _table = {');
  for (final k in keys) {
    final a = k ~/ 100, b = (k % 100) ~/ 2, suited = k.isOdd;
    final label = a == b
        ? '${Rank.values[a - 2].label}${Rank.values[a - 2].label}'
        : '${Rank.values[a - 2].label}${Rank.values[b - 2].label}${suited ? "s" : "o"}';
    buf.writeln('    $k: ${matched[k]!.toStringAsFixed(4)}, // $label');
  }
  buf.writeln('  };');
  print(buf);
}
