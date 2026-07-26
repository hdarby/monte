import 'package:flutter/material.dart';
import 'package:monte/features/tournament/domain/tournament_structure.dart';
import 'package:monte/features/tournament/presentation/tournament_screen.dart';

/// Tournament lobby: pick a structure, field size and buy-in, then register.
class LobbyScreen extends StatefulWidget {
  const LobbyScreen({super.key, this.humanName = 'You'});

  final String humanName;

  @override
  State<LobbyScreen> createState() => _LobbyScreenState();
}

class _LobbyScreenState extends State<LobbyScreen> {
  String _preset = 'turbo';
  int _entrants = 18;
  int _buyIn = 100;

  static const _presets = ['turbo', 'standard', 'deep'];
  static const _fields = [6, 9, 18, 45];
  static const _buyIns = [11, 55, 100, 500];

  TournamentStructure get _structure => switch (_preset) {
        'standard' => TournamentStructure.standard(clockMode: LevelClockMode.hands),
        'deep' => TournamentStructure.deep(clockMode: LevelClockMode.hands),
        _ => TournamentStructure.turbo(clockMode: LevelClockMode.hands),
      };

  int get _tableSize => _entrants <= 9 ? _entrants.clamp(2, 9) : 9;

  @override
  Widget build(BuildContext context) {
    final s = _structure;
    final paidApprox = _entrants <= 9 ? 3 : (_entrants * 0.15).round();
    return Scaffold(
      appBar: AppBar(title: const Text('Tournament lobby')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _label('Structure'),
            SegmentedButton<String>(
              segments: [
                for (final p in _presets)
                  ButtonSegment(value: p, label: Text(_titleCase(p))),
              ],
              selected: {_preset},
              onSelectionChanged: (v) => setState(() => _preset = v.first),
            ),
            const SizedBox(height: 16),
            _label('Field size'),
            SegmentedButton<int>(
              segments: [
                for (final f in _fields)
                  ButtonSegment(value: f, label: Text('$f')),
              ],
              selected: {_entrants},
              onSelectionChanged: (v) => setState(() => _entrants = v.first),
            ),
            const SizedBox(height: 16),
            _label('Buy-in'),
            SegmentedButton<int>(
              segments: [
                for (final b in _buyIns)
                  ButtonSegment(value: b, label: Text('\$$b')),
              ],
              selected: {_buyIn},
              onSelectionChanged: (v) => setState(() => _buyIn = v.first),
            ),
            const SizedBox(height: 24),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${_titleCase(_preset)} · $_entrants runners · '
                        '$_tableSize-max tables'),
                    Text('Starting stack: ${s.startingStack} '
                        '(${(s.startingStack / s.levels.first.bigBlind).round()} BB)'),
                    Text('Prize pool: \$${_buyIn * _entrants} · '
                        'top ~$paidApprox paid'),
                  ],
                ),
              ),
            ),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                icon: const Icon(Icons.emoji_events),
                label: const Text('Register & play'),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => TournamentScreen(
                      structure: _structure,
                      entrants: _entrants,
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

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text, style: Theme.of(context).textTheme.titleSmall),
      );
}

String _titleCase(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
