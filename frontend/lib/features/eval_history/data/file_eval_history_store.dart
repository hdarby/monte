import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:monte/features/eval_history/domain/eval_hand.dart';

/// Persists the full-information tuning history — the permanent record used to
/// evaluate model behavior. Separate from anything a bot can see.
abstract class EvalHistoryStore {
  /// Appends one completed hand to the record.
  void record(EvalHand hand);

  /// Persists any buffered writes to disk.
  Future<void> flush();

  /// All recorded hands, oldest first (flushes first so nothing is missed).
  Future<List<EvalHand>> loadAll();

  /// Number of hands recorded so far.
  Future<int> count();

  /// Erases the entire tuning history — the reset for a clean tuning sample.
  Future<void> wipe();
}

/// File-backed [EvalHistoryStore] writing one JSON object per line
/// (JSON Lines) to `eval_hands.jsonl` under [dir]. Appends stream through a
/// single lazily-opened [IOSink] so a long simulation doesn't reopen the file
/// per hand. [dir] is injected so tests can point at a temp directory.
class FileEvalHistoryStore implements EvalHistoryStore {
  FileEvalHistoryStore(this.dir);

  final Directory dir;

  static const _fileName = 'eval_hands.jsonl';

  IOSink? _sink;
  int? _count;
  int _sinceFlush = 0;

  /// Fire-and-forget flush cadence: bounds how many hands can sit unflushed
  /// (durable enough for interactive play; cheap during a big simulation).
  static const _flushEvery = 25;

  File get _file => File('${dir.path}/$_fileName');

  IOSink _openSink() =>
      _sink ??= _file.openWrite(mode: FileMode.writeOnlyAppend);

  @override
  void record(EvalHand hand) {
    dir.createSync(recursive: true);
    _openSink().writeln(jsonEncode(hand.toJson()));
    if (_count != null) _count = _count! + 1;
    if (++_sinceFlush >= _flushEvery) {
      _sinceFlush = 0;
      unawaited(flush());
    }
  }

  @override
  Future<void> flush() => _sink?.flush() ?? Future.value();

  @override
  Future<List<EvalHand>> loadAll() async {
    await flush();
    if (!_file.existsSync()) return const [];
    final out = <EvalHand>[];
    for (final line in await _file.readAsLines()) {
      if (line.trim().isEmpty) continue;
      out.add(EvalHand.fromJson(jsonDecode(line) as Map<String, dynamic>));
    }
    _count = out.length;
    return out;
  }

  @override
  Future<int> count() async {
    if (_count != null) return _count!;
    await flush();
    if (!_file.existsSync()) return _count = 0;
    var n = 0;
    for (final line in await _file.readAsLines()) {
      if (line.trim().isNotEmpty) n++;
    }
    return _count = n;
  }

  @override
  Future<void> wipe() async {
    await _sink?.close();
    _sink = null;
    if (_file.existsSync()) await _file.delete();
    _count = 0;
    _sinceFlush = 0;
  }
}

/// A store that records nothing — the default binding, so headless/test runs and
/// the pure engine don't touch disk. Production overrides it with a
/// [FileEvalHistoryStore] in `main`.
class NoopEvalHistoryStore implements EvalHistoryStore {
  const NoopEvalHistoryStore();

  @override
  void record(EvalHand hand) {}

  @override
  Future<void> flush() async {}

  @override
  Future<List<EvalHand>> loadAll() async => const [];

  @override
  Future<int> count() async => 0;

  @override
  Future<void> wipe() async {}
}
