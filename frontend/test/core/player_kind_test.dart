import 'package:flutter_test/flutter_test.dart';
import 'package:monte/core/domain/ai/home_game_profiles.dart';
import 'package:monte/core/domain/ai/player_kind.dart';
import 'package:monte/core/domain/ai/player_profiles.dart';
import 'package:monte/core/presentation/player_kind_color.dart';
import 'package:monte/features/tournament/domain/tournament_snapshot.dart';

void main() {
  group('classification', () {
    test('the human is always human, profile or not', () {
      expect(PlayerKind.of(null, isHuman: true), PlayerKind.human);
      expect(
        PlayerKind.of(builtInProfiles.first, isHuman: true),
        PlayerKind.human,
      );
    });

    test('home-game personalities are recreational', () {
      expect(
        PlayerKind.of(homeGameProfiles.first, isHuman: false),
        PlayerKind.amateur,
      );
    });

    test('built-in personalities are pros', () {
      expect(
        PlayerKind.of(builtInProfiles.first, isHuman: false),
        PlayerKind.pro,
      );
    });

    test('an untracked bot defaults to pro, not recreational', () {
      expect(PlayerKind.of(null, isHuman: false), PlayerKind.pro);
    });
  });

  group('StandingKind is the same enum', () {
    test('so the standings and the seats cannot drift apart', () {
      expect(StandingKind.pro, PlayerKind.pro);
      expect(StandingKind.amateur, PlayerKind.amateur);
      expect(StandingKind.human, PlayerKind.human);
      expect(StandingKind.values, PlayerKind.values);
    });
  });

  group('colours', () {
    test('each kind gets a distinct hue', () {
      final hues = PlayerKind.values.map((k) => k.hue).toSet();
      expect(hues, hasLength(PlayerKind.values.length));
    });

    test('generated filler is tinted more softly than a chosen personality', () {
      for (final k in [PlayerKind.pro, PlayerKind.amateur]) {
        expect(
          k.tint(generated: true).a,
          lessThan(k.tint(generated: false).a),
          reason: '$k filler should be dimmer',
        );
      }
    });

    test('strength scales the tint without leaving the valid range', () {
      final base = PlayerKind.pro.tint();
      expect(PlayerKind.pro.tint(strength: 1.5).a, greaterThan(base.a));
      expect(PlayerKind.pro.tint(strength: 100).a, lessThanOrEqualTo(1.0));
      expect(PlayerKind.pro.tint(strength: 0).a, 0.0);
    });

    test('tints stay translucent so seat content stays readable', () {
      for (final k in PlayerKind.values) {
        expect(k.tint().a, lessThan(0.5));
      }
    });

    test('the human tint does not depend on the generated flag', () {
      expect(
        PlayerKind.human.tint(generated: true).a,
        PlayerKind.human.tint(generated: false).a,
      );
    });
  });
}
