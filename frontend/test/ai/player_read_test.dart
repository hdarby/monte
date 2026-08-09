import 'package:flutter_test/flutter_test.dart';
import 'package:monte/core/domain/ai/player_profiles.dart';
import 'package:monte/core/domain/ai/player_read.dart';
import 'package:monte/core/domain/ai/player_stats.dart';

void main() {
  test('reads firm up in stages: nothing, impression, idea, then a read', () {
    PlayerRead read(double hands) {
      final s = PlayerStats()
        ..hands = hands
        ..vpip = hands * 0.5
        ..pfr = hands * 0.4;
      return PlayerRead.of(s);
    }

    // A tiny sample over-reads nothing — it says so.
    expect(read(3).thin, isTrue);
    expect(read(3).description, contains('forming a read'));
    expect(read(3).tags, isEmpty);
    // 5 hands → an "impression"; 10 → an "idea"; both still tentative (thin).
    expect(read(6).description, contains('impression'));
    expect(read(6).thin, isTrue);
    expect(read(12).description, contains('idea'));
    expect(read(12).thin, isTrue);
    // Past the baseline it's a trusted read.
    expect(read(30).thin, isFalse);
  });

  test('a loose-aggressive preflop player reads as such', () {
    // 40 hands: VPIP ~0.55, PFR ~0.45 → very loose + aggressive preflop.
    final s = PlayerStats()
      ..hands = 40
      ..vpip = 22
      ..pfr = 18
      ..threeBet = 5
      ..threeBetOpp = 20
      ..postAggr = 12
      ..postCalls = 6;
    final r = PlayerRead.of(s);
    expect(r.description, contains('loose'));
    expect(r.description, contains('aggressive'));
    expect(r.tags, contains('3-bets a lot'));
    expect(r.thin, isFalse);
    expect(r.stats.map((e) => e.$1), containsAll(['VPIP', 'PFR', '3B']));
  });

  int vpipPct(PlayerRead r) =>
      int.parse(r.stats.firstWhere((e) => e.$1 == 'VPIP').$2.replaceAll('%', ''));

  test('perceivedBy is biased by the observer style (contrast effect)', () {
    // A fixed loose-aggressive player, established sample.
    final s = PlayerStats()
      ..hands = 40
      ..vpip = 22
      ..pfr = 18
      ..postAggr = 12
      ..postCalls = 6;
    // isaacHaxton is tighter (vpipTarget 0.24) than michaelAddamo (0.30), so the
    // tighter observer should over-read the same player as even looser.
    final tightObs = builtInProfiles.firstWhere((p) => p.id == isaacHaxton.id);
    final looseObs = builtInProfiles.firstWhere((p) => p.id == michaelAddamo.id);
    final byTight = PlayerRead.perceivedBy(s, tightObs);
    final byLoose = PlayerRead.perceivedBy(s, looseObs);
    expect(vpipPct(byTight), greaterThan(vpipPct(byLoose)));
    // The objective read sits between the two subjective ones.
    final objective = vpipPct(PlayerRead.of(s));
    expect(vpipPct(byTight), greaterThanOrEqualTo(objective));
  });

  test('a thin perceived read still reports building-a-read, not noise', () {
    final s = PlayerStats()..hands = 4;
    final r = PlayerRead.perceivedBy(s, danielNegreanu);
    expect(r.thin, isTrue);
    expect(r.tags, isEmpty);
  });

  test('the read grows more detailed as more hands accrue', () {
    PlayerStats stats(double hands) => PlayerStats()
      ..hands = hands
      ..vpip = hands * 0.5
      ..pfr = hands * 0.4
      ..threeBet = hands * 0.12
      ..threeBetOpp = hands * 0.5
      ..cbet = hands * 0.85
      ..cbetOpp = hands
      ..postAggr = hands * 0.6
      ..postCalls = hands * 0.2;
    // Just established (20-30 hands): terse preflop-only read, few/no tags.
    final early = PlayerRead.of(stats(22));
    expect(early.thin, isFalse);
    expect(early.description, isNot(contains('postflop')));
    // A deep sample: postflop clause plus the finer behavioural tags appear.
    final deep = PlayerRead.of(stats(60));
    expect(deep.description, contains('postflop'));
    expect(deep.tags.length, greaterThan(early.tags.length));
    expect(deep.tags, contains('c-bets relentlessly'));
  });

  test('a nit reads as tight/standard', () {
    final s = PlayerStats()
      ..hands = 40
      ..vpip = 6
      ..pfr = 5
      ..postAggr = 3
      ..postCalls = 4;
    final r = PlayerRead.of(s);
    expect(r.description, contains('tight'));
  });
}
