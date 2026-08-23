import 'package:meta/meta.dart';

/// The permanent record of one finished tournament.
///
/// Separate from the hand log on purpose: `eval_hands.jsonl` is per-hand and
/// knows nothing about buy-ins, finishing places or prizes, so it can describe
/// how somebody played and never whether they cashed. Career statistics — ROI,
/// cash rate, tournaments played — need the event, not the hands.
///
/// Written when the tournament reaches a champion, including the part played out
/// headless after the human busted, so a career page has full fields rather than
/// only the events its owner survived.
@immutable
class TournamentResult {
  const TournamentResult({
    required this.timestampMs,
    required this.structureName,
    required this.buyIn,
    required this.entrants,
    required this.finishes,
  });

  final int timestampMs;
  final String structureName;
  final int buyIn;
  final int entrants;

  /// Every entrant's finish, champion first.
  final List<TournamentFinish> finishes;

  /// The human's finish, or null for an all-bots event.
  TournamentFinish? get human =>
      finishes.where((f) => f.isHuman).firstOrNull;

  factory TournamentResult.fromJson(Map<String, dynamic> j) => TournamentResult(
        timestampMs: j['timestampMs'] as int,
        structureName: j['structureName'] as String? ?? '',
        buyIn: j['buyIn'] as int? ?? 0,
        entrants: j['entrants'] as int? ?? 0,
        finishes: [
          for (final f in (j['finishes'] as List? ?? const [])
              .cast<Map<String, dynamic>>())
            TournamentFinish.fromJson(f),
        ],
      );

  Map<String, dynamic> toJson() => {
        'timestampMs': timestampMs,
        'structureName': structureName,
        'buyIn': buyIn,
        'entrants': entrants,
        'finishes': [for (final f in finishes) f.toJson()],
      };
}

/// Where one entrant finished, and what it paid.
@immutable
class TournamentFinish {
  const TournamentFinish({
    required this.profileId,
    required this.name,
    required this.place,
    required this.prize,
    this.isHuman = false,
    this.facedHuman = false,
  });

  /// The personality's stable id, so results accumulate across events even
  /// though seat ids and generated names do not.
  final String profileId;
  final String name;
  final int place;
  final int prize;
  final bool isHuman;

  /// Whether this entrant ever shared a table with the human. A field-wide
  /// record is more complete; this is the column that makes it *meaningful*,
  /// since these are the only players actually played against.
  final bool facedHuman;

  factory TournamentFinish.fromJson(Map<String, dynamic> j) => TournamentFinish(
        profileId: j['profileId'] as String? ?? '',
        name: j['name'] as String? ?? '',
        place: j['place'] as int? ?? 0,
        prize: j['prize'] as int? ?? 0,
        isHuman: j['isHuman'] as bool? ?? false,
        facedHuman: j['facedHuman'] as bool? ?? false,
      );

  Map<String, dynamic> toJson() => {
        'profileId': profileId,
        'name': name,
        'place': place,
        'prize': prize,
        if (isHuman) 'isHuman': true,
        if (facedHuman) 'facedHuman': true,
      };
}

/// A personality's career across many events.
@immutable
class CareerRow {
  const CareerRow({
    required this.profileId,
    required this.name,
    required this.played,
    required this.cashes,
    required this.buyIns,
    required this.won,
    required this.bestPlace,
    required this.facedYou,
  });

  final String profileId;
  final String name;
  final int played;
  final int cashes;
  final int buyIns;
  final int won;
  final int bestPlace;
  final int facedYou;

  double get cashRate => played == 0 ? 0 : 100 * cashes / played;

  /// Return on investment as a percentage: +100% means doubling the money in.
  double get roi => buyIns == 0 ? 0 : 100 * (won - buyIns) / buyIns;
  int get net => won - buyIns;

  /// Aggregates [results] into one row per personality, best ROI first.
  static List<CareerRow> from(List<TournamentResult> results) {
    final acc = <String, List<dynamic>>{};
    for (final r in results) {
      for (final f in r.finishes) {
        final key = f.isHuman ? 'human' : f.profileId;
        if (key.isEmpty) continue;
        final a = acc.putIfAbsent(
            key, () => [f.name, 0, 0, 0, 0, 1 << 30, 0]);
        a[0] = f.name;
        a[1] = (a[1] as int) + 1;
        if (f.prize > 0) a[2] = (a[2] as int) + 1;
        a[3] = (a[3] as int) + r.buyIn;
        a[4] = (a[4] as int) + f.prize;
        if (f.place < (a[5] as int)) a[5] = f.place;
        if (f.facedHuman) a[6] = (a[6] as int) + 1;
      }
    }
    final rows = [
      for (final e in acc.entries)
        CareerRow(
          profileId: e.key,
          name: e.value[0] as String,
          played: e.value[1] as int,
          cashes: e.value[2] as int,
          buyIns: e.value[3] as int,
          won: e.value[4] as int,
          bestPlace: e.value[5] as int,
          facedYou: e.value[6] as int,
        )
    ];
    rows.sort((a, b) => b.roi.compareTo(a.roi));
    return rows;
  }
}
