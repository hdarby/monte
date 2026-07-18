import 'package:flutter_test/flutter_test.dart';
import 'package:monte/features/settings/domain/play_pace.dart';

void main() {
  group('PlayPace', () {
    test('instant has zero budget (no artificial delay)', () {
      expect(PlayPace.instant.budget, Duration.zero);
    });

    test('normal is the default 700ms pace', () {
      expect(PlayPace.normal.budget, const Duration(milliseconds: 700));
    });

    test('study caps at 10 seconds', () {
      expect(PlayPace.study.budget, const Duration(seconds: 10));
    });

    test('budgets increase monotonically with pace', () {
      final steps = PlayPace.values;
      for (var i = 1; i < steps.length; i++) {
        expect(
          steps[i].budget,
          greaterThan(steps[i - 1].budget),
          reason: '${steps[i].name} should be slower than ${steps[i - 1].name}',
        );
      }
    });

    test('every step exposes a non-empty label', () {
      for (final p in PlayPace.values) {
        expect(p.label, isNotEmpty);
      }
    });
  });
}
