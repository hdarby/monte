import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:monte/core/di/game_providers.dart';
import 'package:monte/core/presentation/widgets/career_icon.dart';
import 'package:monte/core/domain/ai/player_profile.dart';
import 'package:monte/core/util/format.dart';
import 'package:monte/features/tournament/domain/field_builder.dart';
import 'package:monte/features/tournament/domain/tournament_preset.dart';
import 'package:monte/features/tournament/presentation/career_screen.dart';
import 'package:monte/features/tournament/presentation/tournament_screen.dart';
import 'package:monte/features/tournament/presentation/widgets/lobby_widgets.dart';

/// Tournament lobby: pick a structure, size and buy-in, choose which
/// personalities play, and let the rest of the field auto-fill with a mix of
/// reg-like and pro-like players.
///
/// Field composition itself lives in [FieldBuilder] (domain) — this screen only
/// collects the choices and hands them over.
class LobbyScreen extends ConsumerStatefulWidget {
  const LobbyScreen({super.key, this.humanName = 'You'});

  final String humanName;

  @override
  ConsumerState<LobbyScreen> createState() => _LobbyScreenState();
}

class _LobbyScreenState extends ConsumerState<LobbyScreen> {
  static const _fieldSizes = [6, 9, 18, 27, 64, 100, 150, 180, 1000, 8000];
  static const _buyIns = [11, 55, 100, 500, 1000, 10000];

  /// Seats per table. 0 means "let the field decide" — the previous behaviour,
  /// and still the right default for a large event. The rest are the formats
  /// real tournaments are actually dealt at.
  static const _tableSizes = [0, 2, 6, 9, 10];

  late final FieldBuilder _builder = FieldBuilder(humanName: widget.humanName);

  TournamentPreset _preset = TournamentPreset.turbo;
  int _fieldSize = 9;
  int _buyIn = 100;
  int _tableSizeChoice = 0; // 0 = auto

  /// Profile ids the owner explicitly added. Defaults to everyone — the usual
  /// intent is to play the full cast.
  late final Set<String> _selected = {for (final p in _builder.all) p.id};

  int get _entrants => _builder.entrantsFor(
    fieldSize: _fieldSize,
    selectedCount: _selected.length,
  );
  /// Seats per table: the explicit choice, or the field-derived default.
  ///
  /// Capped at the number of entrants, since a 10-max table cannot be dealt to
  /// six people — picking heads-up for a 180-runner field is legitimate, but
  /// picking 10-max for a six-handed one is not.
  int get _tableSize => _tableSizeChoice == 0
      ? _builder.tableSizeFor(_entrants)
      : _tableSizeChoice.clamp(2, _entrants);

  void _setSelected(String id, bool on) => setState(() {
    if (on) {
      _selected.add(id);
    } else {
      _selected.remove(id);
    }
  });

  /// Offers to wipe the accumulated reads before dealing in.
  ///
  /// The exploitative pros act on persistent per-opponent stats, so a field that
  /// remembers how you played last month is playing against a player who may no
  /// longer exist — and after any change to how you play, those reads describe a
  /// game that is over. Asking here beats relying on the player to remember a
  /// button buried in settings.
  Future<void> _offerWipe() async {
    final svc = ref.read(opponentStatsServiceProvider);
    if (svc == null) return;
    final wipe = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear opponent reads?'),
        content: const Text(
          'The pros in this field remember how you have played and will exploit '
          'it. Clearing gives you a fresh table where nobody has a book on you.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep reads'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Clear and play'),
          ),
        ],
      ),
    );
    if (wipe ?? false) await svc.wipe();
  }

  Future<void> _start() async {
    await _offerWipe();
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TournamentScreen(
          structure: _preset.structure,
          field: _builder.build(
            selectedIds: _selected,
            entrants: _entrants,
            // The buy-in shapes the field: a $10k Main draws a tougher mix, and
            // everyone in it plays tighter and harder than they would for $100.
            buyIn: _buyIn,
          ),
          buyIn: _buyIn,
          tableSize: _tableSize,
          humanName: widget.humanName,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tournament lobby'),
        actions: [
          IconButton(
            tooltip: 'Career',
            icon: const CareerIcon(),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const CareerScreen()),
            ),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LobbyChoiceRow<TournamentPreset>(
              title: 'Structure',
              options: TournamentPreset.values,
              selected: _preset,
              labelOf: (p) => p.label,
              onSelect: (v) => setState(() => _preset = v),
            ),
            const SizedBox(height: 12),
            LobbyChoiceRow<int>(
              title: 'Field size',
              options: _fieldSizes,
              selected: _fieldSize,
              labelOf: formatChips,
              onSelect: (v) => setState(() => _fieldSize = v),
            ),
            const SizedBox(height: 12),
            LobbyChoiceRow<int>(
              title: 'Buy-in',
              options: _buyIns,
              selected: _buyIn,
              labelOf: (b) => '\$${formatChips(b)}',
              onSelect: (v) => setState(() => _buyIn = v),
            ),
            const SizedBox(height: 12),
            LobbyChoiceRow<int>(
              title: 'Seats per table',
              options: _tableSizes,
              selected: _tableSizeChoice,
              labelOf: (n) => switch (n) {
                0 => 'Auto',
                // Deliberately not "heads-up": a heads-up tournament is a
                // seeded bracket of one-on-one matches with fresh stacks each
                // round, not an MTT whose tables happen to seat two. Calling it
                // that would promise a format this does not implement.
                2 => '2-handed',
                _ => '$n-max',
              },
              onSelect: (v) => setState(() => _tableSizeChoice = v),
            ),
            const SizedBox(height: 12),
            _playersHeader(context),
            Expanded(child: _playerList()),
            const SizedBox(height: 8),
            _summary(context),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                icon: const Icon(Icons.emoji_events),
                label: const Text('Register & play'),
                onPressed: _start,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _playersHeader(BuildContext context) => Row(
    children: [
      const LobbyLabel('Players'),
      const Spacer(),
      Text(
        '${_selected.length} added · '
        '${_entrants - 1 - _selected.length} auto-filled',
        style: Theme.of(context).textTheme.bodySmall,
      ),
      TextButton(
        onPressed: () => setState(
          () => _selected
            ..clear()
            ..addAll(_builder.all.map((p) => p.id)),
        ),
        child: const Text('Select all'),
      ),
      if (_selected.isNotEmpty)
        TextButton(
          onPressed: () => setState(_selected.clear),
          child: const Text('Clear'),
        ),
    ],
  );

  Widget _playerList() => Card(
    child: ListView(
      padding: const EdgeInsets.symmetric(vertical: 4),
      children: [
        LobbySectionHeader('Recreational (${_builder.recreational.length})'),
        for (final p in _builder.recreational) _tile(p),
        LobbySectionHeader('Pros (${_builder.pros.length})'),
        for (final p in _builder.pros) _tile(p),
      ],
    ),
  );

  Widget _tile(PlayerProfile profile) => LobbyPlayerTile(
    profile: profile,
    selected: _selected.contains(profile.id),
    onChanged: (on) => _setSelected(profile.id, on),
  );

  Widget _summary(BuildContext context) {
    final s = _preset.structure;
    final startingBb = (s.startingStack / s.levels.first.bigBlind).round();
    final paidApprox = _entrants <= 9 ? 3 : (_entrants * 0.15).round();
    return Text(
      '${_preset.label} · $_entrants runners · '
      '${_tableSize == 2 ? "2-handed" : "$_tableSize-max"} · '
      'start ${s.startingStack} ($startingBb BB) · '
      'pool \$${_buyIn * _entrants} · top ~$paidApprox paid',
      style: Theme.of(context).textTheme.bodySmall,
    );
  }
}

