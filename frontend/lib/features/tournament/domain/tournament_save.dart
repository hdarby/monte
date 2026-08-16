import 'package:meta/meta.dart';

import 'package:monte/features/tournament/domain/payout_structure.dart';
import 'package:monte/features/tournament/domain/tournament_state.dart';
import 'package:monte/features/tournament/domain/tournament_structure.dart';

/// A tournament in progress, captured so it can be picked up later.
///
/// Saved **at a hand boundary**. The live `PokerGame` for the hand in flight,
/// and every bot's RNG position, are deliberately not serialised: they would
/// roughly double the format for the sake of resuming mid-street, and the
/// personalities are reconstructed from their profile ids anyway. Loading
/// therefore deals a fresh hand from the saved chip counts, seats and level —
/// which is exactly what walking away from a table and coming back looks like.
@immutable
class TournamentSave {
  const TournamentSave({
    required this.name,
    required this.savedAt,
    required this.structureName,
    required this.startingStack,
    required this.buyIn,
    required this.tableSize,
    required this.seed,
    required this.humanId,
    required this.humanName,
    required this.levelIndex,
    required this.handsThisLevel,
    required this.clockElapsedMs,
    required this.prizePool,
    required this.finishOrder,
    required this.status,
    required this.players,
    required this.tables,
    required this.profileIds,
    required this.payoutFractions,
  });

  /// What the player called it. Unique per save; the store appends a datestamp.
  final String name;
  final DateTime savedAt;

  /// The blind structure, by preset name — the ladder itself is code, not data,
  /// so storing the whole thing would only invite it drifting out of date.
  final String structureName;
  final int startingStack;

  final int buyIn;
  final int tableSize;

  /// The seed the run was created with, so a reload keeps the same character.
  final int seed;

  final String? humanId;
  final String humanName;

  final int levelIndex;
  final int handsThisLevel;
  final int clockElapsedMs;
  final int prizePool;
  final List<String> finishOrder;
  final String status;

  final List<SavedPlayer> players;
  final List<SavedTable> tables;

  /// Seat id → `PlayerProfile.id`, so the same personalities come back rather
  /// than a fresh random field wearing the same names.
  final Map<String, String> profileIds;

  final List<double> payoutFractions;

  /// A display label: the name plus when it was taken.
  String get label => '$name — ${formatStamp(savedAt)}';

  /// `2026-08-15 14:32` — sortable, unambiguous, and short enough for a list.
  static String formatStamp(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} '
        '${two(t.hour)}:${two(t.minute)}';
  }

  /// A file-safe key derived from the name and timestamp.
  String get id {
    final safe = name.replaceAll(RegExp(r'[^A-Za-z0-9 _-]'), '').trim();
    final t = savedAt;
    String two(int v) => v.toString().padLeft(2, '0');
    return '${safe.isEmpty ? 'tournament' : safe}_'
        '${t.year}${two(t.month)}${two(t.day)}_'
        '${two(t.hour)}${two(t.minute)}${two(t.second)}';
  }

  /// The structure this save was taken from, or null if the preset is gone.
  TournamentStructure? get structure {
    final base = TournamentStructure.presetByName(structureName);
    if (base == null) return null;
    return TournamentStructure(
      name: base.name,
      levels: base.levels,
      clockMode: LevelClockMode.hands,
      startingStack: startingStack,
      maxRebuys: base.maxRebuys,
      reentryLevelCutoff: base.reentryLevelCutoff,
    );
  }

  PayoutStructure get payouts => PayoutStructure(payoutFractions);

  Map<String, dynamic> toJson() => {
        'name': name,
        'savedAt': savedAt.toIso8601String(),
        'structureName': structureName,
        'startingStack': startingStack,
        'buyIn': buyIn,
        'tableSize': tableSize,
        'seed': seed,
        'humanId': humanId,
        'humanName': humanName,
        'levelIndex': levelIndex,
        'handsThisLevel': handsThisLevel,
        'clockElapsedMs': clockElapsedMs,
        'prizePool': prizePool,
        'finishOrder': finishOrder,
        'status': status,
        'players': [for (final p in players) p.toJson()],
        'tables': [for (final t in tables) t.toJson()],
        'profileIds': profileIds,
        'payoutFractions': payoutFractions,
      };

  static TournamentSave fromJson(Map<String, dynamic> j) => TournamentSave(
        name: j['name'] as String? ?? 'Tournament',
        savedAt:
            DateTime.tryParse(j['savedAt'] as String? ?? '') ?? DateTime(2000),
        structureName: j['structureName'] as String? ?? 'standard',
        startingStack: (j['startingStack'] as num?)?.toInt() ?? 10000,
        buyIn: (j['buyIn'] as num?)?.toInt() ?? 100,
        tableSize: (j['tableSize'] as num?)?.toInt() ?? 9,
        seed: (j['seed'] as num?)?.toInt() ?? 1,
        humanId: j['humanId'] as String?,
        humanName: j['humanName'] as String? ?? 'You',
        levelIndex: (j['levelIndex'] as num?)?.toInt() ?? 0,
        handsThisLevel: (j['handsThisLevel'] as num?)?.toInt() ?? 0,
        clockElapsedMs: (j['clockElapsedMs'] as num?)?.toInt() ?? 0,
        prizePool: (j['prizePool'] as num?)?.toInt() ?? 0,
        finishOrder: [
          for (final v in (j['finishOrder'] as List? ?? const [])) v as String,
        ],
        status: j['status'] as String? ?? 'running',
        players: [
          for (final v in (j['players'] as List? ?? const []))
            SavedPlayer.fromJson(v as Map<String, dynamic>),
        ],
        tables: [
          for (final v in (j['tables'] as List? ?? const []))
            SavedTable.fromJson(v as Map<String, dynamic>),
        ],
        profileIds: {
          for (final e in (j['profileIds'] as Map? ?? const {}).entries)
            e.key as String: e.value as String,
        },
        payoutFractions: [
          for (final v in (j['payoutFractions'] as List? ?? const []))
            (v as num).toDouble(),
        ],
      );

  /// Captures [state] under [name].
  static TournamentSave from({
    required String name,
    required DateTime savedAt,
    required TournamentState state,
    required int seed,
    required int tableSize,
    required String? humanId,
    required String humanName,
    required String structureName,
    required Map<String, String> profileIds,
  }) =>
      TournamentSave(
        name: name,
        savedAt: savedAt,
        structureName: structureName,
        startingStack: state.structure.startingStack,
        buyIn: state.buyIn,
        tableSize: tableSize,
        seed: seed,
        humanId: humanId,
        humanName: humanName,
        levelIndex: state.levelIndex,
        handsThisLevel: state.handsThisLevel,
        clockElapsedMs: state.clockElapsed.inMilliseconds,
        prizePool: state.prizePool,
        finishOrder: List.of(state.finishOrder),
        status: state.status.name,
        players: [
          for (final p in state.players.values) SavedPlayer.from(p),
        ],
        tables: [
          for (final t in state.tables)
            SavedTable(id: t.id, playerIds: List.of(t.playerIds)),
        ],
        profileIds: profileIds,
        payoutFractions: List.of(state.payouts.fractions),
      );
}

/// One entrant's persisted state.
@immutable
class SavedPlayer {
  const SavedPlayer({
    required this.id,
    required this.name,
    required this.isHuman,
    required this.chips,
    required this.tableId,
    required this.seatIndex,
    required this.status,
    required this.rebuysUsed,
    this.finishPlace,
    this.prizeWon = 0,
  });

  final String id;
  final String name;
  final bool isHuman;
  final int chips;
  final int tableId;
  final int seatIndex;
  final String status;
  final int rebuysUsed;
  final int? finishPlace;
  final int prizeWon;

  static SavedPlayer from(TournamentPlayer p) => SavedPlayer(
        id: p.id,
        name: p.name,
        isHuman: p.isHuman,
        chips: p.chips,
        tableId: p.tableId,
        seatIndex: p.seatIndex,
        status: p.status.name,
        rebuysUsed: p.rebuysUsed,
        finishPlace: p.finishPlace,
        prizeWon: p.prizeWon,
      );

  TournamentPlayer toPlayer() => TournamentPlayer(
        id: id,
        name: name,
        isHuman: isHuman,
        chips: chips,
        tableId: tableId,
        seatIndex: seatIndex,
        status: PlayerStatus.values.firstWhere(
          (s) => s.name == status,
          orElse: () => PlayerStatus.active,
        ),
        rebuysUsed: rebuysUsed,
        finishPlace: finishPlace,
        prizeWon: prizeWon,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'isHuman': isHuman,
        'chips': chips,
        'tableId': tableId,
        'seatIndex': seatIndex,
        'status': status,
        'rebuysUsed': rebuysUsed,
        'finishPlace': finishPlace,
        'prizeWon': prizeWon,
      };

  static SavedPlayer fromJson(Map<String, dynamic> j) => SavedPlayer(
        id: j['id'] as String,
        name: j['name'] as String? ?? '',
        isHuman: j['isHuman'] as bool? ?? false,
        chips: (j['chips'] as num?)?.toInt() ?? 0,
        tableId: (j['tableId'] as num?)?.toInt() ?? -1,
        seatIndex: (j['seatIndex'] as num?)?.toInt() ?? -1,
        status: j['status'] as String? ?? 'active',
        rebuysUsed: (j['rebuysUsed'] as num?)?.toInt() ?? 0,
        finishPlace: (j['finishPlace'] as num?)?.toInt(),
        prizeWon: (j['prizeWon'] as num?)?.toInt() ?? 0,
      );
}

/// One table's seating.
@immutable
class SavedTable {
  const SavedTable({required this.id, required this.playerIds});

  final int id;
  final List<String> playerIds;

  Map<String, dynamic> toJson() => {'id': id, 'playerIds': playerIds};

  static SavedTable fromJson(Map<String, dynamic> j) => SavedTable(
        id: (j['id'] as num?)?.toInt() ?? 0,
        playerIds: [
          for (final v in (j['playerIds'] as List? ?? const [])) v as String,
        ],
      );
}
