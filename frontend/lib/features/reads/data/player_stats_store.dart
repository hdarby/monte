import 'dart:async';
import 'dart:io';

import 'package:monte/core/domain/ai/opponent_reads.dart';
import 'package:monte/core/domain/ai/player_stats.dart';
import 'package:monte/core/domain/hand_history.dart';

/// Persists the accumulated per-opponent [PlayerStatsBook] across sessions —
/// the reads an exploitative pro builds on the field (and the human) over time.
/// Keyed by a stable identity (`profile.id` / `'human'`), never by seat.
abstract class PlayerStatsStore {
  /// Loads the accumulated book (empty if none saved yet).
  Future<PlayerStatsBook> load();

  /// Persists the current book (debounced by the service; safe to call often).
  Future<void> save(PlayerStatsBook book);

  /// Erases all accumulated reads.
  Future<void> wipe();
}

/// File-backed store writing the whole book as one JSON object to
/// `opponent_stats.json` under [dir]. The book is small (one record per known
/// identity), so a full rewrite per save is cheap. [dir] is injected for tests.
class FilePlayerStatsStore implements PlayerStatsStore {
  FilePlayerStatsStore(this.dir);

  final Directory dir;
  static const _fileName = 'opponent_stats.json';
  File get _file => File('${dir.path}/$_fileName');

  @override
  Future<PlayerStatsBook> load() async {
    if (!_file.existsSync()) return PlayerStatsBook();
    try {
      return PlayerStatsBook.decode(await _file.readAsString());
    } catch (_) {
      return PlayerStatsBook(); // corrupt/partial file → start fresh
    }
  }

  @override
  Future<void> save(PlayerStatsBook book) async {
    dir.createSync(recursive: true);
    await _file.writeAsString(book.encode(), flush: false);
  }

  @override
  Future<void> wipe() async {
    if (_file.existsSync()) await _file.delete();
  }
}

/// A store that persists nothing — the default binding for headless/test runs.
class NoopPlayerStatsStore implements PlayerStatsStore {
  const NoopPlayerStatsStore();

  @override
  Future<PlayerStatsBook> load() async => PlayerStatsBook();

  @override
  Future<void> save(PlayerStatsBook book) async {}

  @override
  Future<void> wipe() async {}
}

/// Owns the live [PlayerStatsBook], folds completed hands into it (rekeyed to a
/// stable identity), and debounces persistence. One instance is shared by the
/// cash repository and the tournament controller via the composition root.
class OpponentStatsService {
  OpponentStatsService(this._store, this._book);

  /// Builds a service with the persisted book already loaded.
  static Future<OpponentStatsService> load(PlayerStatsStore store) async =>
      OpponentStatsService(store, await store.load());

  final PlayerStatsStore _store;
  PlayerStatsBook _book;
  Timer? _saveTimer;

  PlayerStatsBook get book => _book;

  /// Folds one completed hand into the book, rekeying each seat to its stable
  /// identity via [identityOf] (returns null to skip a seat), then schedules a
  /// debounced save.
  void record(HandHistory hand, String? Function(String seatId) identityOf) {
    _book.observe(hand, identityOf);
    _scheduleSave();
  }

  /// A read view bound to a seat→identity resolver for one game/table, as seen
  /// by [observerId] (the player doing the reading). Reads of the human are
  /// remapped to that observer's private impression, so a player never uses
  /// hands it didn't observe. Pass null for [observerId] for a neutral view
  /// (used for the human's own perspective / display of a seat's own play).
  OpponentReads readsFor(String? Function(String seatId) identityOf,
          {String? observerId}) =>
      _BookReads(_book, identityOf, observerId);

  Future<void> wipe() async {
    _book = PlayerStatsBook();
    _saveTimer?.cancel();
    await _store.wipe();
  }

  Future<void> flush() async {
    _saveTimer?.cancel();
    await _store.save(_book.persistable());
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    // Persist only durable identities; a generated player's reads die with the
    // session (see [PlayerStatsBook.persistable]).
    _saveTimer =
        Timer(const Duration(seconds: 3), () => _store.save(_book.persistable()));
  }
}

class _BookReads implements OpponentReads {
  _BookReads(this._book, this._identityOf, this._observerId);
  final PlayerStatsBook _book;
  final String? Function(String seatId) _identityOf;

  /// The reader's own identity; when set, a read of the human resolves to this
  /// observer's private impression instead of a shared/global one.
  final String? _observerId;

  @override
  PlayerStats? forSeat(String seatPlayerId) {
    final id = _identityOf(seatPlayerId);
    if (id == null) return null;
    // Reads of the human are always per-observer: use only what this reader saw.
    if (id == PlayerStatsBook.humanIdentity) {
      return _observerId == null
          ? null
          : _book.read(PlayerStatsBook.meKey(_observerId));
    }
    return _book.read(id);
  }
}
