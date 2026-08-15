import 'package:flutter_test/flutter_test.dart';
import 'package:monte/core/domain/ai/preflop_ranges.dart';
import 'package:monte/core/domain/engine/card.dart';
import 'package:monte/core/domain/engine/hand_strength.dart';

import '../_helpers.dart';

double _play(String hand) {
  final c = cards(hand);
  return HandStrength.playabilityOf(c[0], c[1]);
}

/// Hand *selection* was ranked by [HandStrength.preflopOf] — heads-up all-in
/// equity against a random hand. That metric can only reward high cards; it
/// cannot see whether a hand can realise its equity over three streets. So K4o
/// (top 45%) outranked 76s (top 68%), and a 30% opening range was full of
/// disconnected offsuit junk with no suited connector below 98s.
///
/// Those hands flop the top pair that cannot fold and is usually dominated,
/// which is why the biggest pots kept involving garbage.
void main() {
  group('playability ranks hands the way a poker player would', () {
    test('suited connectors beat disconnected offsuit high cards', () {
      expect(_play('7h 6h'), greaterThan(_play('Kd 4c')));
      expect(_play('6h 5h'), greaterThan(_play('Kd 2c')));
      expect(_play('5h 4h'), greaterThan(_play('Jd 5c')));
      expect(_play('9h 8h'), greaterThan(_play('Qd 7c')));
    });

    test('suited beats the same hand offsuit', () {
      for (final h in ['Ah Kh|Ad Kc', 'Th 9h|Td 9c', '7h 5h|7d 5c']) {
        final parts = h.split('|');
        expect(_play(parts[0]), greaterThan(_play(parts[1])),
            reason: h);
      }
    });

    test('connectedness is worth something', () {
      expect(_play('Th 9c'), greaterThan(_play('Th 6c')));
      expect(_play('8h 7c'), greaterThan(_play('8h 4c')));
    });

    test('pairs stay strong', () {
      expect(_play('2h 2c'), greaterThan(_play('7h 2c')));
      expect(_play('Ah Ac'), greaterThan(_play('Ah Kh')));
    });

    test('all-in equity is left alone — it is right for push/fold', () {
      // K4o genuinely does beat 76s all-in; that is not the bug.
      final k4 = cards('Kd 4c');
      final s76 = cards('7h 6h');
      expect(HandStrength.preflopOf(k4[0], k4[1]),
          greaterThan(HandStrength.preflopOf(s76[0], s76[1])));
    });
  });

  group('the ranges that come out', () {
    /// Every canonical starting hand, strongest first by playability.
    List<String> ranked() {
      String lbl(int hi, int lo, bool s) {
        String r(int v) =>
            const {14: 'A', 13: 'K', 12: 'Q', 11: 'J', 10: 'T'}[v] ?? '$v';
        return hi == lo ? '${r(hi)}${r(lo)}' : '${r(hi)}${r(lo)}${s ? 's' : 'o'}';
      }

      final rows = <(String, double)>[];
      for (var hi = 2; hi <= 14; hi++) {
        for (var lo = 2; lo <= hi; lo++) {
          for (final s in (hi == lo ? [false] : [false, true])) {
            final a = Card(
                Rank.values.firstWhere((r) => r.value == hi), Suit.spades);
            final b = Card(Rank.values.firstWhere((r) => r.value == lo),
                s ? Suit.spades : Suit.hearts);
            rows.add((lbl(hi, lo, s), HandStrength.playabilityOf(a, b)));
          }
        }
      }
      rows.sort((a, b) => b.$2.compareTo(a.$2));
      return rows.map((r) => r.$1).toList();
    }

    test('a 30% range looks like a real 30% range', () {
      final top30 = ranked().take((169 * 0.30).round()).toSet();
      // Must be in: the hands every chart opens.
      for (final h in ['AA', 'AKs', 'AKo', 'JTs', 'A5s', 'KTo', '98s', '44']) {
        expect(top30, contains(h), reason: '$h belongs in a 30% range');
      }
      // Must be out: the junk that used to be in it.
      for (final h in ['K4o', 'K2o', 'Q7o', 'J5o', 'T6o', '72o']) {
        expect(top30, isNot(contains(h)),
            reason: '$h is not a hand anyone opens');
      }
    });

    test('percentile cutoffs still partition the field as advertised', () {
      // PreflopRanges builds its cutoffs from the same metric, so the fractions
      // must still mean what they say.
      for (final f in [0.10, 0.25, 0.50]) {
        final cut = PreflopRanges.thresholdForFraction(f);
        final all = ranked();
        expect(cut, isNotNull);
        expect(all.length, 169);
      }
    });
  });
}
