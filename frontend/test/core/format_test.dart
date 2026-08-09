import 'package:flutter_test/flutter_test.dart';
import 'package:monte/core/util/format.dart';

void main() {
  group('formatChips', () {
    test('groups thousands', () {
      expect(formatChips(0), '0');
      expect(formatChips(999), '999');
      expect(formatChips(1000), '1,000');
      expect(formatChips(8000), '8,000');
      expect(formatChips(250000), '250,000');
      expect(formatChips(1234567), '1,234,567');
    });

    test('preserves a leading sign', () {
      expect(formatChips(-2500), '-2,500');
      expect(formatChips(-1), '-1');
    });
  });

  group('formatChipsWithBb', () {
    test('appends the big-blind equivalent', () {
      expect(formatChipsWithBb(250000, 2000), '250,000 (125 BB)');
    });

    test('rounds to the nearest big blind', () {
      expect(formatChipsWithBb(1500, 1000), '1,500 (2 BB)');
    });

    test('falls back to bare chips when the big blind is unknown', () {
      expect(formatChipsWithBb(250000, 0), '250,000');
    });
  });

  group('ordinal', () {
    test('uses st/nd/rd for 1-3', () {
      expect(ordinal(1), '1st');
      expect(ordinal(2), '2nd');
      expect(ordinal(3), '3rd');
      expect(ordinal(4), '4th');
    });

    test('treats the 11-13 teens as th', () {
      expect(ordinal(11), '11th');
      expect(ordinal(12), '12th');
      expect(ordinal(13), '13th');
    });

    test('handles compound numbers', () {
      expect(ordinal(21), '21st');
      expect(ordinal(102), '102nd');
      expect(ordinal(113), '113th');
    });
  });

  group('name formatting', () {
    test('titleCase uppercases only the first character', () {
      expect(titleCase('turbo'), 'Turbo');
      expect(titleCase(''), '');
      expect(titleCase('wSOP'), 'WSOP');
    });

    test('abbreviateName produces "F. Last"', () {
      expect(abbreviateName('Daniel Negreanu'), 'D. Negreanu');
      expect(abbreviateName('Mary Jane Watson'), 'M. Watson');
    });

    test('firstLastName drops middle names', () {
      expect(firstLastName('Mary Jane Watson'), 'Mary Watson');
      expect(firstLastName('Daniel Negreanu'), 'Daniel Negreanu');
    });

    test('single-word names pass through both forms', () {
      expect(abbreviateName('Ada'), 'Ada');
      expect(firstLastName('Ada'), 'Ada');
    });

    test('displayName marks the human only', () {
      expect(displayName('Ada', isHuman: false), 'Ada');
      expect(displayName('Ada', isHuman: true), 'Ada (you)');
      expect(displayName('Ada', isHuman: true, suffix: '  (you)'),
          'Ada  (you)');
    });
  });
}
