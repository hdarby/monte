import 'dart:convert';
import 'dart:io';

import 'package:monte/features/tournament/domain/tournament_save.dart';

/// Where saved tournaments live.
///
/// Deliberately one file per save rather than a single index: a corrupt or
/// half-written file then costs you that one tournament instead of every one,
/// and deleting is an unlink rather than a rewrite.
abstract class TournamentSaveStore {
  /// Every save, newest first.
  Future<List<TournamentSave>> list();

  Future<void> save(TournamentSave save);

  /// Removes the save with this [id]. Silent if it is already gone.
  Future<void> delete(String id);

  Future<void> deleteAll();
}

class FileTournamentSaveStore implements TournamentSaveStore {
  FileTournamentSaveStore(this._dir);

  final Directory _dir;

  static const _suffix = '.tourney.json';

  Directory get _saves =>
      Directory('${_dir.path}${Platform.pathSeparator}tournaments');

  @override
  Future<List<TournamentSave>> list() async {
    final dir = _saves;
    if (!dir.existsSync()) return const [];
    final out = <TournamentSave>[];
    for (final f in dir.listSync()) {
      if (f is! File || !f.path.endsWith(_suffix)) continue;
      try {
        final json = jsonDecode(await f.readAsString());
        out.add(TournamentSave.fromJson(json as Map<String, dynamic>));
      } on Object {
        // A save we cannot read is not worth taking the whole list down for;
        // skip it so the others still load.
        continue;
      }
    }
    out.sort((a, b) => b.savedAt.compareTo(a.savedAt));
    return out;
  }

  @override
  Future<void> save(TournamentSave save) async {
    final dir = _saves;
    if (!dir.existsSync()) dir.createSync(recursive: true);
    final f = File('${dir.path}${Platform.pathSeparator}${save.id}$_suffix');
    await f.writeAsString(jsonEncode(save.toJson()));
  }

  @override
  Future<void> delete(String id) async {
    final f = File('${_saves.path}${Platform.pathSeparator}$id$_suffix');
    if (f.existsSync()) await f.delete();
  }

  @override
  Future<void> deleteAll() async {
    final dir = _saves;
    if (dir.existsSync()) await dir.delete(recursive: true);
  }
}

/// Used where there is nowhere to write (tests, the web build).
class NoopTournamentSaveStore implements TournamentSaveStore {
  const NoopTournamentSaveStore();

  @override
  Future<List<TournamentSave>> list() async => const [];

  @override
  Future<void> save(TournamentSave save) async {}

  @override
  Future<void> delete(String id) async {}

  @override
  Future<void> deleteAll() async {}
}

/// An in-memory store, for tests and for a session with no disk access.
class MemoryTournamentSaveStore implements TournamentSaveStore {
  final Map<String, TournamentSave> _byId = {};

  @override
  Future<List<TournamentSave>> list() async =>
      _byId.values.toList()..sort((a, b) => b.savedAt.compareTo(a.savedAt));

  @override
  Future<void> save(TournamentSave save) async => _byId[save.id] = save;

  @override
  Future<void> delete(String id) async => _byId.remove(id);

  @override
  Future<void> deleteAll() async => _byId.clear();
}
