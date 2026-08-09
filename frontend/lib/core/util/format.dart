/// Pure-Dart string formatting shared by the domain, data and presentation
/// layers. Deliberately Flutter-free so domain code (e.g. the tournament
/// chronicle, which narrates chip counts) can use it without a layer violation.
///
/// This is *not* the same job as `MoneyScope`/`MoneyFormat`
/// (`core/presentation/money_format.dart`): that decides whether the table shows
/// dollars or big blinds. These are the low-level primitives underneath.
library;

/// Formats a chip/number count with thousands separators, preserving a leading
/// sign: `8000 -> "8,000"`, `-2500 -> "-2,500"`.
String formatChips(int n) {
  final neg = n < 0;
  final s = n.abs().toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return neg ? '-$b' : b.toString();
}

/// Formats a chip amount with its big-blind equivalent, e.g.
/// `"250,000 (125 BB)"`. Falls back to bare chips when [bigBlind] is unknown.
String formatChipsWithBb(int chips, int bigBlind) => bigBlind > 0
    ? '${formatChips(chips)} (${formatChips((chips / bigBlind).round())} BB)'
    : formatChips(chips);

/// The English ordinal for a place: `1 -> "1st"`, `12 -> "12th"`, `23 -> "23rd"`.
///
/// The teens exception applies to *every* hundred, so 111/112/113 are "th" too
/// — which matters here, where a field can run to thousands of places.
String ordinal(int n) {
  final teens = n.abs() % 100;
  if (teens >= 11 && teens <= 13) return '${n}th';
  return switch (n % 10) {
    1 => '${n}st',
    2 => '${n}nd',
    3 => '${n}rd',
    _ => '${n}th',
  };
}

/// Uppercases the first character only: `"turbo" -> "Turbo"`.
String titleCase(String s) =>
    s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

/// Renders a player's name for display, appending `" (you)"` for the human.
/// Centralised so the HUD, standings, recap and results all agree.
String displayName(String name, {required bool isHuman, String suffix = ' (you)'}) =>
    isHuman ? '$name$suffix' : name;

/// Abbreviates a full name to `"F. Lastname"`. Single-word names pass through.
String abbreviateName(String name) {
  final parts = name.trim().split(RegExp(r'\s+'));
  if (parts.length >= 2 && parts.first.isNotEmpty) {
    return '${parts.first[0]}. ${parts.last}';
  }
  return name.trim();
}

/// Reduces a full name to `"First Last"`, dropping any middle names.
String firstLastName(String name) {
  final parts = name.trim().split(RegExp(r'\s+'));
  if (parts.length >= 2) return '${parts.first} ${parts.last}';
  return name.trim();
}
