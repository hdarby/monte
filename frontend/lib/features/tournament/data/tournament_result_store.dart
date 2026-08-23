import 'dart:convert';
import 'dart:io';

import 'package:monte/features/tournament/domain/tournament_result.dart';

/// Persists finished tournaments as JSON Lines, one event per line.
///
/// Mirrors the eval-hand store deliberately: append-only, one record per line,
/// so a corrupt or half-written line costs one event rather than the career.
abstract class TournamentResultStore {
  void record(TournamentResult result);
  Future<List<TournamentResult>> loadAll();

  /// Deletes the career record. Money won and lost is the one statistic a
  /// player may legitimately want to reset without touching how the bots read
  /// them — the two wipes clear different things and neither does the other's
  /// job.
  Future<void> wipe();
}

class FileTournamentResultStore implements TournamentResultStore {
  FileTournamentResultStore(this.dir);

  final Directory dir;
  static const _fileName = 'tournament_results.jsonl';

  File get _file => File('${dir.path}/$_fileName');

  @override
  void record(TournamentResult result) {
    try {
      _file.writeAsStringSync('${jsonEncode(result.toJson())}\n',
          mode: FileMode.append, flush: true);
    } catch (_) {
      // Career bookkeeping must never break the end of a tournament.
    }
  }

  @override
  Future<List<TournamentResult>> loadAll() async {
    if (!_file.existsSync()) return const [];
    final out = <TournamentResult>[];
    for (final line in await _file.readAsLines()) {
      if (line.trim().isEmpty) continue;
      try {
        out.add(TournamentResult.fromJson(
            jsonDecode(line) as Map<String, dynamic>));
      } catch (_) {
        continue; // one bad line, not one bad career
      }
    }
    return out;
  }

  @override
  Future<void> wipe() async {
    if (_file.existsSync()) await _file.delete();
  }
}

/// No-op store for tests and headless runs.
class NullTournamentResultStore implements TournamentResultStore {
  const NullTournamentResultStore();
  @override
  void record(TournamentResult result) {}
  @override
  Future<List<TournamentResult>> loadAll() async => const [];
  @override
  Future<void> wipe() async {}
}
