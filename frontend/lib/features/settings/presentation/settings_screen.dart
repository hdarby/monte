import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:monte/core/domain/ai/bot_spec.dart';
import 'package:monte/core/domain/ai/decider_factory.dart';
import 'package:monte/core/presentation/bot_lineup_editor.dart';
import 'package:monte/core/theme/app_theme.dart';
import 'package:monte/features/settings/domain/game_settings.dart';
import 'package:monte/features/settings/presentation/settings_controller.dart';

/// Lets the player choose the table size and display units, writing changes
/// through the [settingsControllerProvider] (which persists them).
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  late int _count;
  late bool _showBigBlinds;
  late bool _showBehavior;
  late bool _allBots;
  late List<BotSpec> _specs;
  late GameSettings _initial;
  final _sbController = TextEditingController();
  final _bbController = TextEditingController();
  final _stackController = TextEditingController();

  @override
  void initState() {
    super.initState();
    final settings =
        ref.read(settingsControllerProvider).value ?? const GameSettings();
    _initial = settings;
    _count = settings.playerCount;
    _showBigBlinds = settings.showBigBlinds;
    _showBehavior = settings.showBehavior;
    _allBots = settings.allBots;
    _specs = settings.seatBotsFor(settings.botSeatCount);
    _sbController.text = '${settings.smallBlind}';
    _bbController.text = '${settings.bigBlind}';
    _stackController.text = '${settings.startingStack}';
  }

  /// The number of bot seats for the current draft (human takes one unless
  /// all-bots).
  int get _botSeatCount => _allBots ? _count : _count - 1;

  /// Pads (with a usable Personality default) or truncates the per-seat lineup
  /// to match the current bot-seat count — call inside setState after a change
  /// to player count or all-bots.
  void _resizeSpecs() {
    final n = _botSeatCount;
    _specs = [
      for (var i = 0; i < n; i++)
        i < _specs.length ? _specs[i] : const BotSpec(brain: BotType.personality),
    ];
  }

  @override
  void dispose() {
    _sbController.dispose();
    _bbController.dispose();
    _stackController.dispose();
    super.dispose();
  }

  String get _countLabel {
    if (_count == 2) return 'Heads-up';
    if (_count == GameSettings.maxPlayers) return 'Full table';
    return '$_count players';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Table Settings'),
        backgroundColor: AppTheme.surface,
        // No back arrow: changes are a draft until you Cancel or Apply, so we
        // don't want a back gesture to silently discard a toggle.
        automaticallyImplyLeading: false,
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                const Text(
                  'Number of players',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                const Text(
                  'You plus the rest of the seats filled by bots.',
                  style: TextStyle(color: Colors.white60),
                ),
                const SizedBox(height: 24),
                Center(
                  child: Column(
                    children: [
                      Text(
                        '$_count',
                        style: const TextStyle(
                          fontSize: 64,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.gold,
                          height: 1,
                        ),
                      ),
                      Text(
                        _countLabel,
                        style: const TextStyle(
                          fontSize: 16,
                          color: Colors.white70,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    activeTrackColor: AppTheme.gold,
                    thumbColor: AppTheme.gold,
                    overlayColor: AppTheme.gold.withValues(alpha: 0.2),
                  ),
                  child: Slider(
                    value: _count.toDouble(),
                    min: GameSettings.minPlayers.toDouble(),
                    max: GameSettings.maxPlayers.toDouble(),
                    divisions:
                        GameSettings.maxPlayers - GameSettings.minPlayers,
                    label: '$_count',
                    onChanged: (v) => setState(() {
                      _count = v.round();
                      _resizeSpecs();
                    }),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Heads-up (2)',
                        style: TextStyle(color: Colors.white54, fontSize: 13),
                      ),
                      Text(
                        'Full table (10)',
                        style: TextStyle(color: Colors.white54, fontSize: 13),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 28),
                const Divider(color: Colors.white12),
                const SizedBox(height: 12),
                const Text(
                  'Stakes',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Blinds and buy-in (each seat\'s starting stack). Changing '
                  'these starts a new game at the new stake.',
                  style: TextStyle(color: Colors.white60),
                ),
                const SizedBox(height: 16),
                _stakeField('Small blind', _sbController),
                _stakeField('Big blind', _bbController),
                _stakeField('Buy-in (starting stack)', _stackController),
                const SizedBox(height: 28),
                const Divider(color: Colors.white12),
                const SizedBox(height: 12),
                const Text(
                  'Display amounts',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  activeThumbColor: AppTheme.gold,
                  value: _showBigBlinds,
                  onChanged: (v) => setState(() => _showBigBlinds = v),
                  title: Text(
                    _showBigBlinds ? 'Big blinds (BB)' : 'Dollars (\$)',
                  ),
                  subtitle: Text(
                    _showBigBlinds
                        ? 'Stacks and bets shown as multiples of the big blind.'
                        : 'Stacks and bets shown as actual chip amounts.',
                    style: const TextStyle(color: Colors.white54),
                  ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  activeThumbColor: AppTheme.gold,
                  value: _showBehavior,
                  onChanged: (v) => setState(() => _showBehavior = v),
                  title: const Text('Show behavior model on seats'),
                  subtitle: const Text(
                    'Badge each bot with its brain and playing style '
                    '(e.g. "Maniac · MCTS").',
                    style: TextStyle(color: Colors.white54),
                  ),
                ),
                const SizedBox(height: 20),
                const Divider(color: Colors.white12),
                const SizedBox(height: 12),
                const Text(
                  'Bots',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Set each opponent: a named Pro, or a custom Brain + '
                  'Personality.',
                  style: TextStyle(color: Colors.white60),
                ),
                const SizedBox(height: 16),
                BotLineupEditor(
                  seatNames: [
                    for (var i = 0; i < _specs.length; i++) 'Bot ${i + 1}',
                  ],
                  specs: _specs,
                  onChanged: (s) => setState(() => _specs = s),
                ),
                const SizedBox(height: 20),
                const Divider(color: Colors.white12),
                const SizedBox(height: 12),
                const Text(
                  'Evaluation',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  activeThumbColor: AppTheme.gold,
                  value: _allBots,
                  onChanged: (v) => setState(() {
                    _allBots = v;
                    _resizeSpecs();
                  }),
                  title: const Text('All bots (no human)'),
                  subtitle: const Text(
                    'Every seat is a bot. Watch hands play out, or batch-'
                    'simulate from Analytics, then mine the recorded histories.',
                    style: TextStyle(color: Colors.white54),
                  ),
                ),
                const SizedBox(height: 8),
                    ],
                  ),
                ),
              ),
              _footer(context),
            ],
          ),
        ),
      ),
    );
  }

  /// A plain numeric text field for a stake amount (blank/invalid falls back to
  /// the loaded value on Apply).
  Widget _stakeField(String label, TextEditingController controller) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      decoration: InputDecoration(
        labelText: label,
        isDense: true,
        border: const OutlineInputBorder(),
      ),
    ),
  );

  /// A pinned footer so Cancel/Apply are always visible — the settings list can
  /// scroll behind it, but the actions never disappear below the fold.
  Widget _footer(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(28, 12, 28, 16),
    decoration: const BoxDecoration(
      color: AppTheme.surface,
      border: Border(top: BorderSide(color: Colors.white12)),
    ),
    child: Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: () => Navigator.pop(context),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            child: const Text('Cancel'),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.gold,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            onPressed: () {
              // Blank/invalid entries keep the loaded value; then coerce into a
              // coherent stake (bb ≥ 1, sb ≤ bb, buy-in ≥ bb).
              final stake = GameSettings.sanitizeStake(
                int.tryParse(_sbController.text) ?? _initial.smallBlind,
                int.tryParse(_bbController.text) ?? _initial.bigBlind,
                int.tryParse(_stackController.text) ?? _initial.startingStack,
              );
              ref.read(settingsControllerProvider.notifier).save(
                    GameSettings(
                      playerCount: _count,
                      showBigBlinds: _showBigBlinds,
                      showBehavior: _showBehavior,
                      allBots: _allBots,
                      // Global brain/personality are kept only as fallbacks;
                      // the per-seat lineup is the real bot config now.
                      botType: _initial.botType,
                      botPersonality: _initial.botPersonality,
                      smallBlind: stake.smallBlind,
                      bigBlind: stake.bigBlind,
                      startingStack: stake.startingStack,
                      seatBots: _specs,
                    ),
                  );
              Navigator.pop(context);
            },
            child: const Text('Apply'),
          ),
        ),
      ],
    ),
  );
}
