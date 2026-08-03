import 'dart:math';

import 'package:flutter/material.dart';
import 'package:monte/core/domain/ai/home_game_profiles.dart';
import 'package:monte/core/domain/ai/player_profile.dart';
import 'package:monte/core/domain/ai/player_profiles.dart';
import 'package:monte/features/tournament/domain/tournament_structure.dart';
import 'package:monte/features/tournament/presentation/tournament_screen.dart';

/// Tournament lobby: pick a structure, size and buy-in, choose which
/// personalities play, and let the rest of the field auto-fill with a mix of
/// reg-like and pro-like players.
class LobbyScreen extends StatefulWidget {
  const LobbyScreen({super.key, this.humanName = 'You'});

  final String humanName;

  @override
  State<LobbyScreen> createState() => _LobbyScreenState();
}

class _LobbyScreenState extends State<LobbyScreen> {
  String _preset = 'turbo';
  int _fieldSize = 9;
  int _buyIn = 100;
  final _selected = <String>{}; // profile ids the owner explicitly added

  static const _presets = ['turbo', 'standard', 'deep', 'circuit', 'wsop'];
  static const _presetLabels = {
    'turbo': 'Turbo',
    'standard': 'Standard',
    'deep': 'Deep',
    'circuit': 'WSOP Circuit',
    'wsop': 'WSOP Main',
  };
  static const _fields = [6, 9, 80, 180, 1000, 8000];
  static const _buyIns = [11, 55, 100, 500, 1000, 10000];

  // Personality pools (each includes the owner-created customs).
  List<PlayerProfile> get _regs => homeGameProfiles;
  List<PlayerProfile> get _pros => builtInProfiles;
  PlayerProfile? _byId(String id) =>
      [..._regs, ..._pros].where((p) => p.id == id).firstOrNull;

  TournamentStructure get _structure => switch (_preset) {
        'standard' => TournamentStructure.standard(clockMode: LevelClockMode.hands),
        'deep' => TournamentStructure.deep(clockMode: LevelClockMode.hands),
        'circuit' => TournamentStructure.wsopCircuit(clockMode: LevelClockMode.hands),
        'wsop' => TournamentStructure.wsopMainEvent(clockMode: LevelClockMode.hands),
        _ => TournamentStructure.turbo(clockMode: LevelClockMode.hands),
      };

  /// Effective entrants: the chosen field size, but grown so every explicitly
  /// selected player fits (they take a seat, the human takes one, the rest fill).
  int get _entrants => max(_fieldSize, _selected.length + 1);
  int get _tableSize => _entrants <= 9 ? _entrants.clamp(2, 9) : 9;

  /// The bot field: the selected personalities (under their real names) plus an
  /// alternating reg/pro mix to complete the seats. Auto-filled seats play a real
  /// personality's style but wear a unique fictitious name, so the field never
  /// shows the same person twice.
  List<PlayerProfile> _buildField() {
    final rng = Random();
    final field = [for (final id in _selected) _byId(id)].whereType<PlayerProfile>().toList();
    final botsNeeded = _entrants - 1;
    final used = <String>{widget.humanName, for (final p in field) p.name};
    var i = 0;
    while (field.length < botsNeeded) {
      final pool = (i % 2 == 0) ? _regs : _pros;
      i++;
      final src = pool.isNotEmpty ? pool : (_regs.isNotEmpty ? _regs : _pros);
      if (src.isEmpty) break;
      final profile = src[rng.nextInt(src.length)];
      field.add(profile.renamed(_uniqueName(used, rng)));
    }
    return field.take(botsNeeded).toList()..shuffle(rng);
  }

  String _uniqueName(Set<String> used, Random rng) {
    for (var attempt = 0; attempt < 1000; attempt++) {
      final name = '${_firsts[rng.nextInt(_firsts.length)]} '
          '${_lasts[rng.nextInt(_lasts.length)]}';
      if (used.add(name)) return name;
    }
    // Exhausted the pool (huge field) — suffix a number.
    final base = '${_firsts[rng.nextInt(_firsts.length)]} '
        '${_lasts[rng.nextInt(_lasts.length)]}';
    var n = 2;
    while (!used.add('$base $n')) {
      n++;
    }
    return '$base $n';
  }

  @override
  Widget build(BuildContext context) {
    final s = _structure;
    final paidApprox = _entrants <= 9 ? 3 : (_entrants * 0.15).round();
    return Scaffold(
      appBar: AppBar(title: const Text('Tournament lobby')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _label('Structure'),
            _choice(_presets, _preset, (v) => setState(() => _preset = v),
                (p) => _presetLabels[p]!),
            const SizedBox(height: 12),
            _label('Field size'),
            _choice(_fields, _fieldSize, (v) => setState(() => _fieldSize = v),
                _fmt),
            const SizedBox(height: 12),
            _label('Buy-in'),
            _choice(_buyIns, _buyIn, (v) => setState(() => _buyIn = v),
                (b) => '\$${_fmt(b)}'),
            const SizedBox(height: 12),
            Row(
              children: [
                _label('Players'),
                const Spacer(),
                Text('${_selected.length} added · '
                    '${_entrants - 1 - _selected.length} auto-filled',
                    style: Theme.of(context).textTheme.bodySmall),
                TextButton(
                  onPressed: () => setState(() => _selected
                    ..clear()
                    ..addAll([
                      for (final p in _regs) p.id,
                      for (final p in _pros) p.id,
                    ])),
                  child: const Text('Select all'),
                ),
                if (_selected.isNotEmpty)
                  TextButton(
                    onPressed: () => setState(_selected.clear),
                    child: const Text('Clear'),
                  ),
              ],
            ),
            Expanded(
              child: Card(
                child: ListView(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  children: [
                    _sectionHeader('Recreational (${_regs.length})'),
                    for (final p in _regs) _playerTile(p),
                    _sectionHeader('Pros (${_pros.length})'),
                    for (final p in _pros) _playerTile(p),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text('${_titleCase(_preset)} · $_entrants runners · '
                '$_tableSize-max · start ${s.startingStack} '
                '(${(s.startingStack / s.levels.first.bigBlind).round()} BB) · '
                'pool \$${_buyIn * _entrants} · top ~$paidApprox paid',
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                icon: const Icon(Icons.emoji_events),
                label: const Text('Register & play'),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => TournamentScreen(
                      structure: _structure,
                      field: _buildField(),
                      buyIn: _buyIn,
                      tableSize: _tableSize,
                      humanName: widget.humanName,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _playerTile(PlayerProfile p) {
    final on = _selected.contains(p.id);
    return CheckboxListTile(
      dense: true,
      value: on,
      onChanged: (v) => setState(() {
        if (v ?? false) {
          _selected.add(p.id);
        } else {
          _selected.remove(p.id);
        }
      }),
      title: Text(p.name),
      subtitle: Text(p.archetype.replaceAll('_', ' '),
          maxLines: 1, overflow: TextOverflow.ellipsis),
    );
  }

  Widget _sectionHeader(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
        child: Text(text,
            style: TextStyle(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.bold,
                fontSize: 12)),
      );

  Widget _choice<T>(
    List<T> options,
    T selected,
    ValueChanged<T> onSelect,
    String Function(T) label,
  ) =>
      Wrap(
        spacing: 6,
        runSpacing: 4,
        children: [
          for (final o in options)
            ChoiceChip(
              label: Text(label(o)),
              selected: o == selected,
              onSelected: (_) => onSelect(o),
            ),
        ],
      );

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(text, style: Theme.of(context).textTheme.titleSmall),
      );
}

String _titleCase(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

/// Formats an int with thousands separators (8000 -> "8,000").
String _fmt(int n) {
  final s = n.toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return b.toString();
}

// Fictitious names for auto-filled seats (first x last = plenty of unique combos).
const _firsts = [
  'Alex', 'Bianca', 'Cole', 'Dana', 'Elias', 'Farah', 'Gio', 'Hana', 'Ivo',
  'Jun', 'Kira', 'Liam', 'Mona', 'Nils', 'Omar', 'Priya', 'Quinn', 'Rosa',
  'Sami', 'Tara', 'Umi', 'Vince', 'Wren', 'Xavi', 'Yara', 'Zane', 'Bo', 'Cass',
  'Dex', 'Esme', 'Finn', 'Greta', 'Hugo', 'Ira', 'Jax', 'Kai',
];
const _lasts = [
  'Aldridge', 'Barros', 'Cho', 'Devlin', 'Engel', 'Ferro', 'Grover', 'Haas',
  'Imani', 'Juno', 'Keller', 'Lund', 'Marek', 'Novak', 'Ohara', 'Pace', 'Quill',
  'Rios', 'Salter', 'Tovar', 'Ustin', 'Volk', 'Ward', 'Xu', 'Yates', 'Zola',
  'Beck', 'Crane', 'Dane', 'Ellis', 'Frost', 'Gale', 'Hollis', 'Ives',
];
