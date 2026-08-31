import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:monte/core/util/format.dart';
import 'package:monte/features/tournament/domain/field_builder.dart';
import 'package:monte/features/tournament/domain/tournament_preset.dart';

/// The lobby's field composition, extracted out of the widget so it can be
/// tested directly. A seeded [Random] makes every case reproducible.
void main() {
  FieldBuilder builderFor(String humanName, {int seed = 7}) =>
      FieldBuilder(humanName: humanName, rng: Random(seed));

  group('pools', () {
    test('are alphabetical by last name', () {
      final b = builderFor('You');
      final names = b.recreational.map((p) => p.name).toList();
      final sorted = [...names]..sort(compareByLastName);
      expect(names, sorted);
    });

    test("drop the human's own namesake so you never face yourself", () {
      final all = builderFor('You').all;
      expect(all, isNotEmpty);
      final victim = all.first.name;

      final b = builderFor(victim);
      expect(
        b.all.where((p) => p.name.toLowerCase() == victim.toLowerCase()),
        isEmpty,
      );
    });
  });

  group('entrantsFor', () {
    test('uses the chosen field size when it already fits everyone', () {
      final b = builderFor('You');
      expect(b.entrantsFor(fieldSize: 180, selectedCount: 20), 180);
    });

    test('grows so every explicitly selected player gets a seat', () {
      final b = builderFor('You');
      // 40 selected + the human needs 41 seats, more than the chosen 9.
      expect(b.entrantsFor(fieldSize: 9, selectedCount: 40), 41);
    });
  });

  group('tableSizeFor', () {
    test('seats the whole field at one table when it fits', () {
      final b = builderFor('You');
      expect(b.tableSizeFor(6), 6);
      expect(b.tableSizeFor(9), 9);
    });

    test('caps at 9-max for a multi-table field', () {
      final b = builderFor('You');
      expect(b.tableSizeFor(10), 9);
      expect(b.tableSizeFor(8000), 9);
    });

    test('never goes below heads-up', () {
      expect(builderFor('You').tableSizeFor(2), 2);
    });
  });

  group('build', () {
    test('returns exactly one profile per non-human seat', () {
      final b = builderFor('You');
      expect(b.build(selectedIds: const {}, entrants: 180), hasLength(179));
    });

    test('includes every selected personality under its real name', () {
      final b = builderFor('You');
      final picked = b.all.take(3).toList();

      final field = b.build(
        selectedIds: {for (final p in picked) p.id},
        entrants: 80,
      );

      for (final p in picked) {
        expect(
          field.where((f) => f.name == p.name && !f.generated),
          hasLength(1),
          reason: '${p.name} should appear once, un-renamed',
        );
      }
    });

    test('auto-filled seats are marked generated', () {
      final b = builderFor('You');
      final picked = b.all.take(2).toList();
      final field = b.build(
        selectedIds: {for (final p in picked) p.id},
        entrants: 50,
      );
      expect(field.where((f) => f.generated), hasLength(47));
    });

    test('never repeats a name, even in a huge field', () {
      final b = builderFor('You');
      final field = b.build(selectedIds: const {}, entrants: 1000);
      final names = field.map((p) => p.name).toSet();
      expect(names, hasLength(field.length));
    });

    test("never hands a bot the human's name", () {
      final b = builderFor('You');
      final field = b.build(selectedIds: const {}, entrants: 500);
      expect(field.where((p) => p.name == 'You'), isEmpty);
    });

    test('is reproducible for a given seed', () {
      final a = builderFor('You', seed: 42)
          .build(selectedIds: const {}, entrants: 60)
          .map((p) => p.name)
          .toList();
      final c = builderFor('You', seed: 42)
          .build(selectedIds: const {}, entrants: 60)
          .map((p) => p.name)
          .toList();
      expect(a, c);
    });

    test('mixes both pools when nothing is selected', () {
      final b = builderFor('You');
      final field = b.build(selectedIds: const {}, entrants: 200);
      final ids = field.map((p) => p.id).toSet();
      final recIds = b.recreational.map((p) => p.id).toSet();
      final proIds = b.pros.map((p) => p.id).toSet();
      expect(ids.intersection(recIds), isNotEmpty);
      expect(ids.intersection(proIds), isNotEmpty);
    });
  });

  group('uniqueName', () {
    test('adds the name it returns to the used set', () {
      final b = builderFor('You');
      final used = <String>{};
      final name = b.uniqueName(used);
      expect(used, contains(name));
    });

    test('never collides across many draws', () {
      final b = builderFor('You');
      final used = <String>{};
      for (var i = 0; i < 2000; i++) {
        b.uniqueName(used);
      }
      expect(used, hasLength(2000));
    });
  });

  group('TournamentPreset', () {
    test('every preset builds a hand-clocked structure with levels', () {
      for (final p in TournamentPreset.values) {
        final s = p.structure;
        expect(s.levels, isNotEmpty, reason: '${p.name} has no levels');
        expect(s.startingStack, greaterThan(0));
        expect(p.label, isNotEmpty);
      }
    });

    test('blinds never decrease as levels advance', () {
      for (final p in TournamentPreset.values) {
        final levels = p.structure.levels;
        for (var i = 1; i < levels.length; i++) {
          expect(
            levels[i].bigBlind,
            greaterThanOrEqualTo(levels[i - 1].bigBlind),
            reason: '${p.name} level ${i + 1} big blind went down',
          );
        }
      }
    });
  });
}
