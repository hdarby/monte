import 'package:monte/core/util/format.dart';
import 'package:monte/features/tournament/domain/chronicle/player_meta.dart';

/// Second-person grammar for recap prose.
///
/// The human appears in the recap alongside everyone else, so every line that
/// names a player needs to work in both third person ("Negreanu is running
/// hot") and second ("you are running hot"). These keep the agreement right
/// without duplicating every template — every generator in `chronicle/` goes
/// through here rather than inlining `m.isHuman ? ... : ...` checks.
class ChronicleGrammar {
  const ChronicleGrammar._();

  /// How to refer to a player: their name, or "you" for the human.
  /// [capital] for sentence-initial use.
  static String who(PlayerMeta m, {bool capital = false}) =>
      m.isHuman ? (capital ? 'You' : 'you') : m.name;

  /// "are still" / "is still" — the leader follow-up's only agreement wrinkle.
  static String areStill(PlayerMeta m) => m.isHuman ? 'are still' : 'is still';

  /// Object form, for "nobody can win a pot off them / you".
  static String whom(PlayerMeta m) => m.isHuman ? 'you' : 'them';

  static String isVerb(PlayerMeta m) => m.isHuman ? 'are' : 'is';
  static String has(PlayerMeta m) => m.isHuman ? 'have' : 'has';
  static String was(PlayerMeta m) => m.isHuman ? 'were' : 'was';
  static String keeps(PlayerMeta m) => m.isHuman ? 'keep' : 'keeps';

  /// Joins names as "A, B and C".
  static String nameList(List<String> names) {
    if (names.isEmpty) return '';
    if (names.length == 1) return names.first;
    return '${names.sublist(0, names.length - 1).join(', ')} and ${names.last}';
  }

  /// A natural-language phrase for a made hand ("a flush", "a set", …).
  static String phrase(String label) {
    switch (label) {
      case 'Three of a Kind':
        return 'a set';
      case 'Two Pair':
        return 'two pair';
      case 'High Card':
        return 'ace-high';
      default:
        return 'a ${label.toLowerCase()}';
    }
  }

  /// A chip amount with its big-blind equivalent, e.g. "250,000 (125 BB)".
  static String amt(int chips, int bigBlind) =>
      formatChipsWithBb(chips, bigBlind);
}
